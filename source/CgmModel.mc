import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;

// Foreground view of the current CGM state, whichever source it comes from.
module CgmModel {
    const STALE_SECONDS = 15 * 60;
    const VERY_HIGH_MGDL = 250;

    function current(now as Number) as Dictionary? {
        if (CgmConfig.source() == CgmConfig.SRC_MOCK) {
            return MockCgm.reading(CgmConfig.getNumber("MockScenario", MockCgm.DAY), now);
        }
        var d = Application.Storage.getValue(CgmConfig.STORAGE_KEY);
        return (d instanceof Dictionary) ? d : null;
    }

    function lastError() as String? {
        var e = Application.Storage.getValue(CgmConfig.ERROR_KEY);
        return (e instanceof String) ? e : null;
    }

    // Nightscout-style direction name. Uses the source's own direction when it sent one,
    // otherwise derives it from the 5-minute delta with the usual Dexcom per-minute thresholds.
    function direction(cgm as Dictionary) as String {
        var dir = cgm["dir"];
        if (dir instanceof String && !dir.equals("NONE") && !dir.equals("NOT COMPUTABLE")) {
            return dir;
        }
        var delta = cgm["delta"];
        if (delta == null) {
            return "NONE";
        }
        var perMin = delta.toFloat() / 5.0;
        if (perMin > 3.0) { return "DoubleUp"; }
        if (perMin > 2.0) { return "SingleUp"; }
        if (perMin > 1.0) { return "FortyFiveUp"; }
        if (perMin >= -1.0) { return "Flat"; }
        if (perMin >= -2.0) { return "FortyFiveDown"; }
        if (perMin >= -3.0) { return "SingleDown"; }
        return "DoubleDown";
    }

    function isMmol() as Boolean {
        return CgmConfig.getNumber("Units", 0) == 1;
    }

    function formatGlucose(mgdl as Number) as String {
        return isMmol() ? (mgdl / 18.0182).format("%.1f") : mgdl.toString();
    }

    function formatDelta(mgdl) as String {
        if (mgdl == null) {
            return "";
        }
        var sign = (mgdl >= 0) ? "+" : "";
        return isMmol() ? sign + (mgdl / 18.0182).format("%.1f") : sign + mgdl.toString();
    }

    // :low, :inRange, :high, :veryHigh or :stale; Palette turns it into a colour per surface.
    function state(mgdl as Number, stale as Boolean) as Symbol {
        if (stale) { return :stale; }
        if (mgdl < CgmConfig.lowMgdl()) { return :low; }
        if (mgdl > VERY_HIGH_MGDL) { return :veryHigh; }
        if (mgdl > CgmConfig.highMgdl()) { return :high; }
        return :inRange;
    }
}

// Every colour the face draws. Colour is kept for glucose: everything else is white or grey.
module Palette {
    const FG = 0xF2F4F7;           // text and the time
    const MUTE = 0x8FA3AB;         // icons, units, secondary text
    const SOFT = 0xC9CED8;         // the date
    const GUIDE = 0x3A4A50;        // dotted 70 and 180 lines
    const RULE = 0x5E6E75;         // dotted section divider, at its centre
    // Glucose states on black
    const GREEN = 0x34D399;
    const DOT_HIGH = 0xF5B547;
    const DOT_VERY_HIGH = 0xFF8A50;
    const DOT_LOW = 0xFF5E6C;

    // Always-on: dimmed
    const AOD_TIME = 0xB8BEC9;
    const AOD_MUTE = 0x485256;
    const AOD_FG = 0x797A7C;
    const AOD_RED = 0x80262F;
    // Glucose states at 75% on black
    const AOD_IN_RANGE = 0x279E73;
    const AOD_HIGH = 0xBF8835;
    const AOD_VERY_HIGH = 0xBF5C34;
    const AOD_LOW = 0xBF3A47;
    // Graph dots at 50% on black
    const AOD_GREEN = 0x1A6A4C;
    const AOD_DOT_HIGH = 0x7B5A23;
    const AOD_DOT_VERY_HIGH = 0x80452A;
    const AOD_DOT_LOW = 0x802F36;

    // Graph dot colour for a reading's state.
    function dot(state as Symbol, aod as Boolean) as Number {
        if (state == :low) { return aod ? AOD_DOT_LOW : DOT_LOW; }
        if (state == :high) { return aod ? AOD_DOT_HIGH : DOT_HIGH; }
        if (state == :veryHigh) { return aod ? AOD_DOT_VERY_HIGH : DOT_VERY_HIGH; }
        if (state == :stale) { return aod ? AOD_MUTE : MUTE; }
        return aod ? AOD_GREEN : GREEN;
    }

    // Glucose number and time-tint colour: the dot colours, a little brighter in always-on.
    function glucose(state as Symbol, aod as Boolean) as Number {
        if (!aod) { return dot(state, false); }
        if (state == :low) { return AOD_LOW; }
        if (state == :high) { return AOD_HIGH; }
        if (state == :veryHigh) { return AOD_VERY_HIGH; }
        if (state == :stale) { return AOD_MUTE; }
        return AOD_IN_RANGE;
    }

    // a mixed into b by t (0..1), per channel.
    function blend(a as Number, b as Number, t as Float) as Number {
        var r = (((a >> 16) & 0xFF) * t + ((b >> 16) & 0xFF) * (1 - t)).toNumber();
        var g = (((a >> 8) & 0xFF) * t + ((b >> 8) & 0xFF) * (1 - t)).toNumber();
        var bl = ((a & 0xFF) * t + (b & 0xFF) * (1 - t)).toNumber();
        return (r << 16) | (g << 8) | bl;
    }
}
