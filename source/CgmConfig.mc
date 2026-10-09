import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;

// Settings access shared by the watch face and the background service.
(:background)
module CgmConfig {
    const STORAGE_KEY = "cgm";
    const ERROR_KEY = "cgmErr";
    // Cached Nightscout v3 JWT as [token, expiry epoch s].
    const JWT_KEY = "nsJwt";
    // 36 slots x 5 min = 3 h of history.
    const HISTORY_SLOTS = 36;
    const SLOT_SECONDS = 300;

    enum {
        SRC_MOCK = 0,
        SRC_NIGHTSCOUT = 1,
        SRC_XDRIP = 2,
        SRC_AAPS = 3
    }

    function getNumber(key as String, fallback as Number) as Number {
        var v = Application.Properties.getValue(key);
        return (v instanceof Number) ? v : fallback;
    }

    function getString(key as String) as String {
        var v = Application.Properties.getValue(key);
        return (v instanceof String) ? v : "";
    }

    function source() as Number {
        return getNumber("DataSource", SRC_NIGHTSCOUT);
    }

    function lowMgdl() as Number {
        return threshold("Low", 70, 40, 150);
    }

    function highMgdl() as Number {
        return threshold("High", 180, 100, 400);
    }

    // A threshold entered in either unit: under 30 is read as mmol/L.
    function threshold(key as String, fallback as Number, min as Number, max as Number) as Number {
        var v = Application.Properties.getValue(key);
        if (!(v instanceof Number || v instanceof Float || v instanceof Double)) {
            return fallback;
        }
        var f = v.toFloat();
        if (f < 30) {
            f = f * 18.0182;
        }
        var mgdl = Math.round(f).toNumber();
        return (mgdl < min || mgdl > max) ? fallback : mgdl;
    }

    // Full URL of the entries endpoint for the selected live source, or null if not configured.
    // xDrip+ and AndroidAPS serve a Nightscout-compatible sgv.json from a web server on the phone.
    function entriesUrl() as String? {
        var src = source();
        if (src == SRC_XDRIP) {
            return "http://127.0.0.1:17580/sgv.json";
        }
        if (src == SRC_AAPS) {
            return "http://127.0.0.1:28891/sgv.json";
        }
        if (src == SRC_NIGHTSCOUT) {
            var base = nightscoutBase();
            return (base == null) ? null : base + "/api/v1/entries/sgv.json";
        }
        return null;
    }

    function nightscoutBase() as String? {
        var url = getString("NightscoutUrl");
        while (url.length() > 0 && url.toCharArray()[url.length() - 1] == '/') {
            url = url.substring(0, url.length() - 1) as String;
        }
        return (url.length() == 0) ? null : url;
    }
}
