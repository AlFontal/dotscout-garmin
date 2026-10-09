import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.PersistedContent;
import Toybox.System;
import Toybox.Time;

// Background fetch for live sources. Pulls the most recent readings and, for Nightscout,
// IOB/COB/basal from the v2 properties API, then hands a compact dictionary to the app via
// Background.exit(). The shape matches what MockCgm.reading() returns:
//   {"t" => epoch s, "sgv" => mg/dL, "delta" => mg/dL?, "dir" => String?, "hist" => Array (oldest first),
//    "iob" => Float?, "cob" => Float?, "basal" => Float?}
// Also "cad" => median seconds between readings (the source cadence); and
// "jwt" => [token, expiry s] when a new v3 token was issued, or "jwtBad" => true when it was refused.
// "hist" normally covers only the fetched readings; the app merges it into the stored 3 h history.
// When that history is mostly empty (first install, long gap) the service backfills 3 h from the
// Nightscout v3 API, projected to date+sgv: 180 one-minute entries are ~6 KB there, while the
// same from v1 is ~55 KB and fails in the 64 KB background with -402/-403.
// On failure it exits with {"err" => short label} so the face can say why there is no data.
(:background)
class CgmServiceDelegate extends System.ServiceDelegate {
    // Enough to cover a missed run plus the delta even with 1-minute readings.
    const FETCH_COUNT = 12;
    // xDrip+'s brief_mode entries are small, so it can afford more history per run.
    const XDRIP_FETCH_COUNT = 24;
    // 3 h of 1-minute readings.
    const BACKFILL_COUNT = 180;
    // Backfill when fewer stored slots than this hold readings, at most once per BACKFILL_SECONDS.
    const BACKFILL_MIN_SLOTS = 30;
    const BACKFILL_SECONDS = 30 * 60;
    // How far from 5 minutes before the newest reading an entry may be to serve as the delta base.
    const DELTA_TOLERANCE_SECONDS = 90;

    private var _result as Dictionary?;
    private var _off as Array?;
    private var _jwt as String?;

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var url = CgmConfig.entriesUrl();
        if (url == null) {
            Background.exit({"err" => "Set your Nightscout URL"});
            return;
        }
        // xDrip+ and AAPS ignore unknown params; brief_mode trims xDrip's payload, which matters
        // because background memory is small and oversized responses fail with -402.
        var src = CgmConfig.source();
        var params = {"count" => (src == CgmConfig.SRC_XDRIP) ? XDRIP_FETCH_COUNT : FETCH_COUNT};
        if (src == CgmConfig.SRC_NIGHTSCOUT) {
            addToken(params);
        } else {
            params["brief_mode"] = "Y";
        }
        Communications.makeWebRequest(url, params, jsonGet(), method(:onEntries));
    }

    // A top-level JSON array arrives as an Array at runtime even though the API type omits it.
    function onEntries(code as Number, data as Dictionary or String or PersistedContent.Iterator or Null) as Void {
        if (code != 200) {
            Background.exit({"err" => errorLabel(code)});
            return;
        }
        var entries = data as Object?;
        if (!(entries instanceof Array) || entries.size() == 0) {
            Background.exit({"err" => "No readings yet"});
            return;
        }
        _result = parseEntries(entries);
        entries = null;
        data = null;

        if (CgmConfig.source() != CgmConfig.SRC_NIGHTSCOUT || CgmConfig.nightscoutBase() == null) {
            Background.exit(_result);
            return;
        }
        if (needsBackfill()) {
            requestBackfill();
        } else {
            requestProperties();
        }
    }

    // ---- 3 h backfill (Nightscout v3) ----------------------------------------------------

    // Reads what the app stored last time (background may read Storage) to decide whether the
    // graph needs filling. Carries the last backfill time forward in "bf".
    private function needsBackfill() as Boolean {
        var r = _result as Dictionary;
        var now = Time.now().value();
        var old = Application.Storage.getValue(CgmConfig.STORAGE_KEY);
        var filled = 0;
        var lastBf = null;
        if (old instanceof Dictionary) {
            lastBf = old["bf"];
            var hist = old["hist"];
            var t = old["t"];
            if (hist instanceof Array && t instanceof Number && now - t < 3 * 3600) {
                for (var i = 0; i < hist.size(); i++) {
                    if (hist[i] != null) { filled++; }
                }
            }
        }
        if (lastBf instanceof Number) {
            r["bf"] = lastBf;
        }
        if (filled >= BACKFILL_MIN_SLOTS || CgmConfig.getString("NightscoutToken").length() == 0) {
            return false;
        }
        return !(lastBf instanceof Number) || now - lastBf > BACKFILL_SECONDS;
    }

    // v3 needs a JWT, exchanged from the access token and cached by the app until it expires.
    private function requestBackfill() as Void {
        var cached = Application.Storage.getValue(CgmConfig.JWT_KEY);
        if (cached instanceof Array && cached.size() == 2 && cached[1] instanceof Number
                && (cached[1] as Number) > Time.now().value() + 120) {
            _jwt = cached[0] as String;
            requestHistory();
            return;
        }
        var url = CgmConfig.nightscoutBase() + "/api/v2/authorization/request/" + CgmConfig.getString("NightscoutToken");
        Communications.makeWebRequest(url, {}, jsonGet(), method(:onJwt));
    }

    function onJwt(code as Number, data as Dictionary or String or PersistedContent.Iterator or Null) as Void {
        if (code == 200 && data instanceof Dictionary && data["token"] instanceof String && data["exp"] instanceof Number) {
            _jwt = data["token"] as String;
            (_result as Dictionary)["jwt"] = [_jwt, data["exp"]];
            requestHistory();
        } else {
            requestProperties();
        }
    }

    private function requestHistory() as Void {
        var opts = jsonGet();
        opts[:headers] = {"Authorization" => "Bearer " + _jwt};
        var params = {"fields" => "date,sgv", "limit" => BACKFILL_COUNT, "sort$desc" => "date"};
        Communications.makeWebRequest(CgmConfig.nightscoutBase() + "/api/v3/entries", params, opts, method(:onHistory));
    }

    // Fills only the slots the recent fetch left empty, so the newest readings stay authoritative.
    function onHistory(code as Number, data as Dictionary or String or PersistedContent.Iterator or Null) as Void {
        var r = _result as Dictionary;
        if (code == 200 && data instanceof Dictionary && data["result"] instanceof Array) {
            bucket(data["result"] as Array, r["t"] as Number, r["hist"] as Array, _off as Array, true);
            r["bf"] = Time.now().value();
        } else if (code == 401 || code == 403) {
            r["jwtBad"] = true;
        }
        data = null;
        requestProperties();
    }

    private function requestProperties() as Void {
        Communications.makeWebRequest(CgmConfig.nightscoutBase() + "/api/v2/properties/iob,cob,basal", addToken({}), jsonGet(), method(:onProperties));
    }

    // Loop data is optional: a failure here still delivers the glucose readings.
    // Nightscout's properties look like {"iob": {"iob": 1.2}, "cob": {"cob": 20},
    // "basal": {"current": {"basal": 0.8, "tempbasal": 1.1, "totalbasal": 1.1}}}.
    function onProperties(code as Number, data as Dictionary or String or PersistedContent.Iterator or Null) as Void {
        var r = _result;
        if (r != null && code == 200 && data instanceof Dictionary) {
            var iob = data["iob"];
            if (iob instanceof Dictionary && iob["iob"] != null) {
                r["iob"] = iob["iob"].toFloat();
            }
            var cob = data["cob"];
            if (cob instanceof Dictionary && cob["cob"] != null) {
                r["cob"] = cob["cob"].toFloat();
            }
            var basal = data["basal"];
            if (basal instanceof Dictionary) {
                var cur = basal["current"];
                if (cur instanceof Dictionary) {
                    var rate = firstNonNull(cur, ["totalbasal", "tempbasal", "basal"]);
                    if (rate != null) {
                        r["basal"] = rate.toFloat();
                    }
                }
            }
        }
        Background.exit(r);
    }

    private function jsonGet() as Dictionary {
        return {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    // Nightscout access token (Admin Tools > Subjects), sent as ?token=.
    private function addToken(params as Dictionary) as Dictionary {
        var token = CgmConfig.getString("NightscoutToken");
        if (token.length() > 0) {
            params["token"] = token;
        }
        return params;
    }

    // Puts entries (newest first, "date" in ms and "sgv") into 5-minute slots aligned to latestTs,
    // keeping the entry closest to each slot's time so 1-minute data samples evenly. With
    // onlyEmpty, slots that already hold a reading are left alone.
    private function bucket(entries as Array, latestTs as Number, hist as Array, off as Array, onlyEmpty as Boolean) as Void {
        var n = hist.size();
        var half = CgmConfig.SLOT_SECONDS / 2;
        var taken = new [n];
        for (var i = 0; i < entries.size(); i++) {
            var e = entries[i];
            if (!(e instanceof Dictionary) || e["sgv"] == null || e["date"] == null) {
                continue;
            }
            var age = latestTs - toSeconds(e["date"]);
            var slot = (age + half) / CgmConfig.SLOT_SECONDS;
            if (age < 0 || slot >= n) {
                continue;
            }
            var k = n - 1 - slot;
            if (onlyEmpty && hist[k] != null && taken[k] == null) {
                continue;
            }
            var d = (age - slot * CgmConfig.SLOT_SECONDS).abs();
            if (off[k] == null || taken[k] == null || d < off[k]) {
                hist[k] = e["sgv"].toNumber();
                off[k] = d;
                taken[k] = true;
            }
        }
    }

    private function parseEntries(entries as Array) as Dictionary {
        var n = CgmConfig.HISTORY_SLOTS;
        var latest = entries[0] as Dictionary;
        var latestTs = toSeconds(latest["date"]);
        var latestSgv = latest["sgv"].toNumber();
        var hist = new [n];
        _off = new [n];
        bucket(entries, latestTs, hist, _off as Array, false);

        var deltaBase = null;
        var deltaOff = DELTA_TOLERANCE_SECONDS + 1;
        for (var i = 0; i < entries.size(); i++) {
            var e = entries[i];
            if (!(e instanceof Dictionary) || e["sgv"] == null) {
                continue;
            }
            var dd = (latestTs - toSeconds(e["date"]) - CgmConfig.SLOT_SECONDS).abs();
            if (dd < deltaOff) {
                deltaBase = e["sgv"].toNumber();
                deltaOff = dd;
            }
        }

        // Prefer the uploader's delta: on a real 1-minute Nightscout feed it is already a smoothed
        // 5-minute value that agrees with its trend arrow. Otherwise use the reading ~5 minutes back.
        var delta = null;
        if (latest["delta"] != null) {
            delta = Math.round(latest["delta"].toFloat()).toNumber();
        } else if (deltaBase != null) {
            delta = latestSgv - deltaBase;
        }

        var r = {
            "t" => latestTs,
            "sgv" => latestSgv,
            "delta" => delta,
            "dir" => latest["direction"],
            "hist" => hist,
            "cad" => cadence(entries)
        };
        // Some phone-side servers (e.g. AAPS) add loop fields to the newest entry. Use them when present.
        var iob = latest["iob"];
        if (iob != null) { r["iob"] = iob.toFloat(); }
        var cob = latest["cob"];
        if (cob != null) { r["cob"] = cob.toFloat(); }
        var tbr = firstNonNull(latest, ["tbr", "basal"]);
        if (tbr != null) { r["basal"] = tbr.toFloat(); }
        return r;
    }

    // Median spacing between consecutive readings, in seconds, or null with fewer than two.
    private function cadence(entries as Array) as Number? {
        var gaps = [];
        var prev = -1;
        for (var i = 0; i < entries.size(); i++) {
            var e = entries[i];
            if (!(e instanceof Dictionary) || e["date"] == null) {
                continue;
            }
            var t = toSeconds(e["date"]);
            if (prev >= 0 && prev - t > 0) {
                // Insertion sort; there are at most a couple of dozen gaps.
                var g = prev - t;
                var j = gaps.size();
                gaps.add(g);
                while (j > 0 && (gaps[j - 1] as Number) > g) {
                    gaps[j] = gaps[j - 1];
                    j--;
                }
                gaps[j] = g;
            }
            prev = t;
        }
        return (gaps.size() == 0) ? null : gaps[gaps.size() / 2] as Number;
    }

    private function firstNonNull(d as Dictionary, keys as Array) {
        for (var i = 0; i < keys.size(); i++) {
            var v = d[keys[i]];
            if (v != null && (v instanceof Number || v instanceof Float || v instanceof Double || v instanceof Long)) {
                return v;
            }
        }
        return null;
    }

    // Nightscout dates are epoch milliseconds, which overflow a 32-bit Number.
    private function toSeconds(v) as Number {
        if (v == null) {
            return 0;
        }
        return (v.toLong() / 1000l).toNumber();
    }

    private function errorLabel(code) as String {
        if (code == Communications.BLE_CONNECTION_UNAVAILABLE) { return "Phone not connected"; }
        if (code == Communications.NETWORK_REQUEST_TIMED_OUT || code == Communications.BLE_HOST_TIMEOUT) { return "Request timed out"; }
        if (code == Communications.NETWORK_RESPONSE_TOO_LARGE) { return "Response too large"; }
        if (code == 401 || code == 403) { return "Token refused (" + code + ")"; }
        if (code == 404) { return "Not found: check the URL"; }
        return "Error " + code;
    }
}
