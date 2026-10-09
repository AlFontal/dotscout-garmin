import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background)
class CgmFaceApp extends Application.AppBase {
    // Time for the phone app to receive a new reading and upload it.
    const FETCH_DELAY_SECONDS = 20;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        scheduleFetch(storedReadingTime());
        return [new CgmFaceView()];
    }

    function getServiceDelegate() {
        return [new CgmServiceDelegate()];
    }

    // Called in the foreground with whatever the background service passed to Background.exit().
    function onBackgroundData(data) as Void {
        var readingTime = null;
        if (data instanceof Dictionary) {
            var err = data["err"];
            if (err == null) {
                var jwt = data["jwt"];
                if (jwt != null) {
                    Application.Storage.setValue(CgmConfig.JWT_KEY, jwt);
                    data.remove("jwt");
                } else if (data["jwtBad"] != null) {
                    Application.Storage.deleteValue(CgmConfig.JWT_KEY);
                    data.remove("jwtBad");
                }
                Application.Storage.setValue(CgmConfig.STORAGE_KEY, mergeHistory(data));
                Application.Storage.deleteValue(CgmConfig.ERROR_KEY);
                readingTime = data["t"];
            } else {
                Application.Storage.setValue(CgmConfig.ERROR_KEY, err.toString());
            }
        }
        scheduleFetch(readingTime);
        WatchUi.requestUpdate();
    }

    // The service only fetches the latest readings, so the 3 h graph is built up here: the stored
    // history is shifted left by the slots elapsed since its newest reading and the new slots are
    // laid over it. Everything except "hist" comes from the new data.
    function mergeHistory(fresh as Dictionary) as Dictionary {
        var old = Application.Storage.getValue(CgmConfig.STORAGE_KEY);
        if (!(old instanceof Dictionary) || !(old["hist"] instanceof Array) || !(old["t"] instanceof Number)) {
            return fresh;
        }
        var n = CgmConfig.HISTORY_SLOTS;
        var oldHist = old["hist"] as Array;
        var newHist = fresh["hist"] as Array;
        var elapsed = (fresh["t"] as Number) - (old["t"] as Number);
        var shift = (elapsed + CgmConfig.SLOT_SECONDS / 2) / CgmConfig.SLOT_SECONDS;
        if (elapsed < 0 || shift >= n || oldHist.size() != n) {
            return fresh;
        }
        for (var i = 0; i < n - shift; i++) {
            if (newHist[i] == null) {
                newHist[i] = oldHist[i + shift];
            }
        }
        return fresh;
    }

    function onSettingsChanged() as Void {
        // A new URL or token invalidates the cached v3 token.
        Application.Storage.deleteValue(CgmConfig.JWT_KEY);
        scheduleFetch(null);
        WatchUi.requestUpdate();
    }

    // Connect IQ allows at most one background run every 5 minutes. For feeds that upload every
    // 5 minutes the next run is timed for just after the following reading should have reached
    // the phone, so the face lags the sensor by seconds. Faster feeds (e.g. 1-minute) always have
    // a fresh reading, so the next run is simply as soon as allowed. Without a reading (first run,
    // errors) it falls back to a recurring 5-minute event.
    function scheduleFetch(readingTime) as Void {
        if (!(Toybox has :Background)) {
            return;
        }
        if (CgmConfig.source() == CgmConfig.SRC_MOCK) {
            Background.deleteTemporalEvent();
            return;
        }
        if (!(readingTime instanceof Number)) {
            Background.registerForTemporalEvent(new Time.Duration(CgmConfig.SLOT_SECONDS));
            return;
        }
        var next = earliestRun();
        var cad = storedCadence();
        if (cad >= 240) {
            var aligned = readingTime + CgmConfig.SLOT_SECONDS + FETCH_DELAY_SECONDS;
            while (aligned < next) {
                aligned += CgmConfig.SLOT_SECONDS;
            }
            next = aligned;
        }
        Background.registerForTemporalEvent(new Time.Moment(next));
    }

    // Each run schedules the next one from onBackgroundData. A run that never reports back (killed
    // for memory or time, or finished while the face wasn't running) would leave nothing
    // scheduled and syncing would stop, so the view calls this once a minute to restart the chain.
    function ensureScheduled() as Void {
        if (!(Toybox has :Background) || CgmConfig.source() == CgmConfig.SRC_MOCK) {
            return;
        }
        var registered = Background.getTemporalEventRegisteredTime();
        if (registered instanceof Time.Moment && registered.value() < Time.now().value() - 60) {
            registered = null;
        }
        if (registered == null) {
            scheduleFetch(storedReadingTime());
        }
    }

    // Called when the wrist is raised: if the reading is over 5 minutes old, bring the next run
    // forward to the earliest time Connect IQ allows.
    function fetchIfStale() as Void {
        if (!(Toybox has :Background) || CgmConfig.source() == CgmConfig.SRC_MOCK) {
            return;
        }
        var t = storedReadingTime();
        var now = Time.now().value();
        if (t instanceof Number && now - t <= CgmConfig.SLOT_SECONDS) {
            return;
        }
        var next = earliestRun();
        var registered = Background.getTemporalEventRegisteredTime();
        // A one-off time that has already passed is not a pending run.
        if (registered instanceof Time.Moment && registered.value() >= now && registered.value() <= next) {
            return;
        }
        Background.registerForTemporalEvent(new Time.Moment(next));
    }

    // Connect IQ rejects (and crashes on) a time less than 5 minutes after the last run.
    private function earliestRun() as Number {
        var earliest = Time.now().value() + 5;
        var last = Background.getLastTemporalEventTime();
        if (last != null && last.value() + CgmConfig.SLOT_SECONDS + 1 > earliest) {
            earliest = last.value() + CgmConfig.SLOT_SECONDS + 1;
        }
        return earliest;
    }

    private function storedCadence() as Number {
        var d = Application.Storage.getValue(CgmConfig.STORAGE_KEY);
        var cad = (d instanceof Dictionary) ? d["cad"] : null;
        return (cad instanceof Number) ? cad : CgmConfig.SLOT_SECONDS;
    }

    function storedReadingTime() {
        var d = Application.Storage.getValue(CgmConfig.STORAGE_KEY);
        return (d instanceof Dictionary) ? d["t"] : null;
    }
}
