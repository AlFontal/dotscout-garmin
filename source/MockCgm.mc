import Toybox.Lang;
import Toybox.Math;

// Deterministic fake CGM feed for the simulator. Values are a function of the 5-minute bucket,
// so a new reading "arrives" every 5 minutes of simulator time and history stays stable between redraws.
module MockCgm {
    enum {
        STEADY = 0,
        DAY = 1,
        RISING = 2,
        FALLING = 3,
        HIGH = 4,
        STALE = 5,
        NO_DATA = 6
    }

    function reading(scenario as Number, now as Number) as Dictionary? {
        if (scenario == NO_DATA) {
            return null;
        }
        var n = CgmConfig.HISTORY_SLOTS;
        var gap = (scenario == STALE) ? 5 : 0;
        var latest = now / CgmConfig.SLOT_SECONDS - gap;
        var hist = new [n];
        for (var i = 0; i < n; i++) {
            var k = n - 1 - i;
            hist[i] = value(scenario, latest - k, k + gap);
        }
        var r = {
            "t" => latest * CgmConfig.SLOT_SECONDS,
            "sgv" => hist[n - 1],
            "delta" => hist[n - 1] - hist[n - 2],
            "hist" => hist
        };
        addLoopData(scenario, r);
        return r;
    }

    // bucket: absolute 5-minute bucket; k: buckets before "now" (0 = current).
    function value(scenario as Number, bucket as Number, k as Number) as Number {
        var noise = ((bucket % 10007) * 7919 + 13) % 9 - 4;
        var wave = Math.sin(2 * Math.PI * (bucket % 36) / 36.0);
        var v;
        if (scenario == DAY) {
            v = 150 + 55 * Math.sin(2 * Math.PI * (bucket % 72) / 72.0)
                + 20 * Math.sin(2 * Math.PI * (bucket % 23) / 23.0) + noise;
        } else if (scenario == RISING) {
            v = (k <= 9) ? 240 - k * 16 + noise / 2 : 98 + 6 * wave + noise;
        } else if (scenario == FALLING) {
            v = (k <= 8) ? 62 + k * 12 + noise / 2 : 158 + 6 * wave + noise;
        } else if (scenario == HIGH) {
            v = 268 + 14 * wave + noise;
        } else {
            v = 112 + 12 * wave + noise;
        }
        return Math.round(v).toNumber();
    }

    function addLoopData(scenario as Number, r as Dictionary) as Void {
        if (scenario == RISING) {
            r["iob"] = 3.8; r["cob"] = 42.0; r["basal"] = 1.6;
        } else if (scenario == FALLING) {
            r["iob"] = 0.3; r["cob"] = 0.0; r["basal"] = 0.0;
        } else if (scenario == HIGH) {
            r["iob"] = 2.1; r["cob"] = 0.0; r["basal"] = 2.4;
        } else {
            r["iob"] = 0.9; r["cob"] = 12.0; r["basal"] = 0.85;
        }
    }
}
