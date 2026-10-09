import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.Weather;

// Configurable data fields. To add a new one: add an id here, a case in value(),
// a <listEntry> in settings.xml and a string in strings.xml.
module Fields {
    enum {
        NONE = 0,
        IOB = 1,
        COB = 2,
        BASAL = 3,
        HEART = 4,
        BATTERY = 5,
        STEPS = 6,
        BODY_BATTERY = 7,
        CALORIES = 8,
        VO2_MAX = 9,
        TEMPERATURE = 10,
        STRESS = 11,
        FLOORS = 12,
        ACTIVE_MIN = 13,
        ELEVATION_GAIN = 14
    }

    // Returns [icon key, value, unit] or null for an empty slot. Icons are drawn by Icons.draw;
    // the unit is shown smaller and muted after the value.
    function value(field as Number, cgm as Dictionary?) as Array? {
        if (field == IOB) {
            var v = loop(cgm, "iob");
            return [:iob, (v == null) ? "--" : v.format("%.1f"), "U"];
        }
        if (field == COB) {
            var v = loop(cgm, "cob");
            return [:cob, (v == null) ? "--" : v.toNumber().toString(), "g"];
        }
        if (field == BASAL) {
            var v = loop(cgm, "basal");
            return [:basal, (v == null) ? "--" : v.format("%.2f"), "U/h"];
        }
        if (field == HEART) {
            return [:heart, heartRate(), "bpm"];
        }
        if (field == BATTERY) {
            return [:battery, System.getSystemStats().battery.format("%d"), "%"];
        }
        if (field == STEPS) {
            var steps = ActivityMonitor.getInfo().steps;
            return [:steps, (steps == null) ? "--" : grouped(steps), ""];
        }
        if (field == BODY_BATTERY) {
            return [:bodyBattery, bodyBattery(), "%"];
        }
        if (field == CALORIES) {
            var kcal = ActivityMonitor.getInfo().calories;
            return [:calories, (kcal == null) ? "--" : kcal.toString(), "kcal"];
        }
        if (field == VO2_MAX) {
            return [:vo2max, vo2Max(), ""];
        }
        if (field == TEMPERATURE) {
            return [:temperature, temperature(), ""];
        }
        if (field == STRESS) {
            return [:stress, stress(), ""];
        }
        if (field == FLOORS) {
            var info = ActivityMonitor.getInfo();
            var floors = (info has :floorsClimbed) ? info.floorsClimbed : null;
            return [:floors, (floors == null) ? "--" : floors.toString(), ""];
        }
        if (field == ACTIVE_MIN) {
            return [:activeMin, activeMinutesWeek(), "min"];
        }
        if (field == ELEVATION_GAIN) {
            var statute = System.getDeviceSettings().elevationUnits == System.UNIT_STATUTE;
            return [:ascent, elevationGain(), statute ? "ft" : "m"];
        }
        return null;
    }

    function loop(cgm as Dictionary?, key as String) as Float? {
        if (cgm == null || cgm[key] == null) {
            return null;
        }
        return cgm[key].toFloat();
    }

    function heartRate() as String {
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            return info.currentHeartRate.toString();
        }
        var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
        var hr = (sample != null) ? sample.heartRate : null;
        if (hr != null && hr != ActivityMonitor.INVALID_HR_SAMPLE) {
            return hr.toString();
        }
        return "--";
    }

    // Newest Body Battery sample that has a value; the very latest can be empty.
    function bodyBattery() as String {
        if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
            var it = SensorHistory.getBodyBatteryHistory({:period => 5, :order => SensorHistory.ORDER_NEWEST_FIRST});
            var sample = it.next();
            while (sample != null) {
                if (sample.data != null) {
                    return sample.data.toNumber().toString();
                }
                sample = it.next();
            }
        }
        return "--";
    }

    function vo2Max() as String {
        if (!(Toybox has :UserProfile)) {
            return "--";
        }
        var profile = UserProfile.getProfile();
        var v = (profile has :vo2maxRunning) ? profile.vo2maxRunning : null;
        if (v == null && (profile has :vo2maxCycling)) {
            v = profile.vo2maxCycling;
        }
        return (v == null) ? "--" : v.toString();
    }

    // Garmin weather (synced from the phone) when available. Otherwise the watch's own sensor,
    // marked with "~" because on the wrist it reads body heat rather than air temperature.
    function temperature() as String {
        var celsius = null;
        var prefix = "";
        if ((Toybox has :Weather) && (Weather has :getCurrentConditions)) {
            var cond = Weather.getCurrentConditions();
            if (cond != null && cond.temperature != null) {
                celsius = cond.temperature;
            }
        }
        if (celsius == null && (Toybox has :SensorHistory) && (SensorHistory has :getTemperatureHistory)) {
            var sample = SensorHistory.getTemperatureHistory({:period => 1}).next();
            if (sample != null && sample.data != null) {
                celsius = sample.data;
                prefix = "~";
            }
        }
        if (celsius == null) {
            return "--";
        }
        var statute = System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE;
        var v = statute ? celsius.toFloat() * 9 / 5 + 32 : celsius.toFloat();
        return prefix + Math.round(v).toNumber().toString() + "°";
    }

    function stress() as String {
        if ((Toybox has :SensorHistory) && (SensorHistory has :getStressHistory)) {
            var sample = SensorHistory.getStressHistory({:period => 1}).next();
            if (sample != null && sample.data != null) {
                return sample.data.toNumber().toString();
            }
        }
        return "--";
    }

    function activeMinutesWeek() as String {
        var info = ActivityMonitor.getInfo();
        if ((info has :activeMinutesWeek) && info.activeMinutesWeek != null) {
            return info.activeMinutesWeek.total.toString();
        }
        return "--";
    }

    // Today's ascent, in feet when the watch uses statute elevation units.
    function elevationGain() as String {
        var info = ActivityMonitor.getInfo();
        var meters = (info has :metersClimbed) ? info.metersClimbed : null;
        if (meters == null) {
            return "--";
        }
        var v = meters.toFloat();
        if (System.getDeviceSettings().elevationUnits == System.UNIT_STATUTE) {
            v = v * 3.28084;
        }
        return Math.round(v).toNumber().toString();
    }

    // Plain digits with no thousands separator (12000); very large counts fall back to 123k.
    function grouped(n as Number) as String {
        return (n >= 100000) ? (n / 1000).toString() + "k" : n.toString();
    }

    function compact(n as Number) as String {
        return (n >= 10000) ? (n / 1000.0).format("%.1f") + "k" : n.toString();
    }
}
