import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// "F · Dots" proposal, 454 x 454, everything on black with no panels:
//
//   status row (bluetooth while connected, battery) and date
//   HH:MM as a 5 x 7 dot matrix, white or tinted by glucose (TimeColor setting)
//   reading age, glucose and trend arrow, then delta
//   3 h dot graph between dotted 70/180 lines
//   four stats: tinted icon, value and unit
//   heart rate
//
// Always-on keeps the time as smaller dots, the glucose and the graph, and drifts a few pixels
// each minute against burn-in. Coordinates are Figma-style: text is placed by its text-box top.
// The older D and E drawing functions below are unused while this is a proposal.
class CgmFaceView extends WatchUi.WatchFace {
    private var _sleeping as Boolean = false;
    private var _aod as Boolean = false;
    private var _ox as Number = 0;
    private var _oy as Number = 0;

    private var _fonts as Dictionary = {};
    // Minute of the last fetch-schedule check (see CgmFaceApp.ensureScheduled).
    private var _checkedMin as Number = -1;

    function initialize() {
        WatchFace.initialize();
    }

    // Vector faces in order of preference. Bionic Bold sets the numbers where the watch has it
    // (FR965, fenix 8, epix Pro, Venu 4, D2 Mach 2); the FR970 and FR570 fall back to Roboto
    // Condensed Bold, and the Venu 3, which has neither, to Roboto Regular drawn faux bold.
    private const NUM_FACES = ["BionicBold", "RobotoCondensedBold", "RobotoRegular"];
    private const LABEL_FACES = ["RobotoCondensedBold", "RobotoRegular"];
    private const LABEL_REG_FACES = ["RobotoCondensedRegular", "RobotoRegular"];
    // face => [line height (getVectorFont's size) / em, ascent / em, digit height / em]
    private const FACE_METRICS = {
        "BionicBold" => [1.276, 0.930, 0.643],
        "RobotoCondensedBold" => [1.173, 0.928, 0.730],
        "RobotoCondensedRegular" => [1.173, 0.928, 0.730],
        "RobotoRegular" => [1.173, 0.928, 0.731]
    };
    private const BIONIC_DIGIT = 0.643;

    // key => [role, em px, Figma size]. Number ems are Bionic's; a fallback face is scaled so its
    // digits are as tall, which keeps every layout position valid.
    private const FONT_SPECS = {
        :glucose => [:num, 66, 66],
        :heart => [:num, 32, 32],
        :delta => [:num, 26, 26],
        :deltaG => [:num, 34, 34],
        :stat => [:num, 30, 30],
        :status => [:label, 17, 19],
        :age => [:label, 19, 21],
        :small => [:label, 16, 18],
        :date => [:label, 15, 17],
        :dateL => [:label, 28, 28],
        :minmax => [:label, 14, 16],
        :bpm => [:labelReg, 14, 16]
    };

    // Each entry becomes [font, Figma-top offset, ascent px, faux-bold px].
    function onLayout(dc as Dc) as Void {
        var keys = FONT_SPECS.keys();
        for (var i = 0; i < keys.size(); i++) {
            var spec = FONT_SPECS[keys[i]] as Array;
            var role = spec[0] as Symbol;
            var faces = (role == :num) ? NUM_FACES : ((role == :label) ? LABEL_FACES : LABEL_REG_FACES);
            var f = null;
            var em = (spec[1] as Number).toFloat();
            var m = [1.2, 0.93, 0.73];
            var bold = 0;
            if (Graphics has :getVectorFont) {
                for (var k = 0; k < faces.size() && f == null; k++) {
                    m = FACE_METRICS[faces[k]] as Array;
                    var e = (role == :num) ? em * BIONIC_DIGIT / (m[2] as Float) : em;
                    f = Graphics.getVectorFont({:face => faces[k], :size => Math.round(e * (m[0] as Float)).toNumber()});
                    if (f != null) {
                        em = e;
                        // Roboto Regular stands in for bold faces: thicken it by restamping.
                        if (faces[k].equals("RobotoRegular") && role != :labelReg) {
                            bold = (role == :num && em > 28) ? 2 : 1;
                        }
                    }
                }
            }
            if (f == null) {
                f = Graphics.FONT_SMALL;
            }
            // Figma's 100% line height puts the baseline 0.792 x size below the box top.
            var baseline = Math.round(0.792 * (spec[2] as Number)).toNumber();
            var ascent = Math.round((m[1] as Float) * em).toNumber();
            _fonts[keys[i]] = [f, baseline - ascent, ascent, bold];
        }
    }

    function onEnterSleep() as Void {
        _sleeping = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _sleeping = false;
        (Application.getApp() as CgmFaceApp).fetchIfStale();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        var settings = System.getDeviceSettings();
        _aod = _sleeping && (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        _ox = 0;
        _oy = 0;
        if (_aod) {
            var min = System.getClockTime().min;
            _ox = (min % 5 - 2) * 3;
            _oy = (min / 5 % 5 - 2) * 3 + 12;
        }
        drawBackground(dc);

        var now = Time.now().value();
        if (now / 60 != _checkedMin) {
            _checkedMin = now / 60;
            (Application.getApp() as CgmFaceApp).ensureScheduled();
        }
        var cgm = CgmModel.current(now);

        // "F · Dots": everything on black, the time as a dot matrix that echoes the dot graph.
        drawStatus(dc, settings);
        drawTimeDots(dc, cgm, now);
        rule(dc, 186, 156);
        // Always-on has no stats or heart rate, so the glucose row and graph move down to sit
        // centred in the space below the time.
        var lower = _aod ? AOD_LOWER : 0;
        _oy += lower;
        drawGlucoseFree(dc, cgm, now);
        drawGraphOpen(dc, cgm, now);
        _oy -= lower;
        // Always-on keeps only the time, glucose and graph.
        if (!_aod) {
            drawStatsOpen(dc, cgm);
            drawBottom(dc, CgmConfig.getNumber("BottomField", Fields.HEART), cgm);
        }
    }

    // ---- F · Dots ---------------------------------------------------------------------------

    private const AOD_LOWER = 40;

    // 5 x 7 digits, one 5-bit row each, top row first; bit 4 is the left column.
    private const GLYPHS = [
        [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
        [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
        [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],
        [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
        [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
        [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
        [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
        [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
        [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C]
    ];
    private const PITCH = 13;
    // Date above an HH:MM dot matrix, 25 columns wide. The TimeColor setting can tint the minutes
    // (1) or the whole time (2) by the glucose range; colour on this face only ever means glucose.
    private function drawTimeDots(dc as Dc, cgm as Dictionary?, now as Number) as Void {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var date = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.day, info.month]);
        textAt(dc, :dateL, 227, 72, date, _aod ? Palette.AOD_MUTE : Palette.SOFT, Graphics.TEXT_JUSTIFY_CENTER);

        var x = 227 - 12 * PITCH;
        var y = 92;
        var plain = _aod ? Palette.AOD_TIME : Palette.FG;
        var tint = CgmConfig.getNumber("TimeColor", 0);
        var minColor = plain;
        if (tint != 0 && cgm != null) {
            minColor = Palette.glucose(CgmModel.state(cgm["sgv"] as Number, isStale(cgm, now)), _aod);
        }
        var hourColor = (tint == 2) ? minColor : plain;
        dotDigit(dc, hour / 10, x, y, hourColor);
        dotDigit(dc, hour % 10, x + 6 * PITCH, y, hourColor);
        dotDigit(dc, clock.min / 10, x + 14 * PITCH, y, minColor);
        dotDigit(dc, clock.min % 10, x + 20 * PITCH, y, minColor);
        // Colon: two dots in the middle column, rows 2 and 4.
        var cx = x + 12 * PITCH + _ox;
        dc.setColor(_aod ? Palette.AOD_MUTE : Palette.MUTE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, y + 2 * PITCH + _oy, _aod ? 3 : 5);
        dc.fillCircle(cx, y + 4 * PITCH + _oy, _aod ? 3 : 5);
    }

    // One digit with its top-left dot centred on (x, y); always-on draws smaller dots.
    private function dotDigit(dc as Dc, d as Number, x as Number, y as Number, color as Number) as Void {
        var rows = GLYPHS[d] as Array;
        x += _ox;
        y += _oy;
        for (var r = 0; r < 7; r++) {
            var bits = rows[r] as Number;
            var c = color;
            for (var col = 0; col < 5; col++) {
                var px = x + col * PITCH;
                var py = y + r * PITCH;
                if (((bits >> (4 - col)) & 1) == 1) {
                    dc.setColor(c, Graphics.COLOR_TRANSPARENT);
                    dc.fillCircle(px, py, _aod ? 3.2 : 4.9);
                }
            }
        }
    }

    // Glucose on black: reading age at the value's top left, then a trend arrow and delta. The
    // age's caps start where the value's caps start; the smaller delta is vertically centred on them.
    private const GLUCOSE_BASE = 248;
    private const AGE_BASE = GLUCOSE_BASE - 42 + 14;    // the 19 px label's caps are about 14 px
    private const TREND_SCALE = 1.18;    // the arrow's 36 px design was for a 56 px em
    private const GLUCOSE_CAP = 42;      // Bionic Bold digits are 0.643 em; 66 px em

    private function drawGlucoseFree(dc as Dc, cgm as Dictionary?, now as Number) as Void {
        var mute = _aod ? Palette.AOD_MUTE : Palette.MUTE;
        if (cgm == null) {
            text(dc, :dateL, 227, 206, "No data", mute, Graphics.TEXT_JUSTIFY_CENTER);
            var err = CgmModel.lastError();
            if (err != null) {
                text(dc, :date, 227, 232, err, mute, Graphics.TEXT_JUSTIFY_CENTER);
            }
            return;
        }
        var sgv = cgm["sgv"] as Number;
        var stale = isStale(cgm, now);
        var state = CgmModel.state(sgv, stale);
        var color = Palette.glucose(state, _aod);
        var value = CgmModel.formatGlucose(sgv);
        var delta = stale ? "" : CgmModel.formatDelta(cgm["delta"]);
        var age = (now - (cgm["t"] as Number)) / 60;
        var ageText = ((age < 0) ? 0 : age).toString() + "'";
        var vw = width(dc, :glucose, value);
        var arrowW = stale ? 0 : 40 + 16;
        var ageW = 19 + width(dc, :age, ageText);
        var dw = width(dc, :deltaG, delta);
        var ageGap = 6;
        var rightW = stale ? 0 : 12 + arrowW + dw;
        var x = 227 - (ageW + ageGap + vw + rightW) / 2;
        var ageColor = stale ? (_aod ? Palette.AOD_RED : Palette.DOT_LOW) : mute;
        icon(dc, :clock, x, AGE_BASE - 15, 16, ageColor);
        textAt(dc, :age, x + 19, AGE_BASE, ageText, ageColor, Graphics.TEXT_JUSTIFY_LEFT);

        var gx = x + ageW + ageGap;
        textAt(dc, :glucose, gx, GLUCOSE_BASE, value, color, Graphics.TEXT_JUSTIFY_LEFT);
        if (!stale) {
            drawTrend(dc, cgm, gx + vw + 12 + 20 + _ox, GLUCOSE_BASE - GLUCOSE_CAP / 2 + _oy, color);
            var sx = gx + vw + 12 + arrowW;
            // Bionic's 34 px delta has a 22 px cap height. Moving its baseline 10 px up centres
            // that cap height inside the glucose value's 42 px cap height.
            textAt(dc, :deltaG, sx, GLUCOSE_BASE - 10, delta, color, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // Dotted rule between sections at the time's dot pitch, fading out towards both ends; none
    // in always-on.
    private function rule(dc as Dc, y as Number, half as Number) as Void {
        if (_aod) {
            return;
        }
        var n = half / PITCH;
        for (var k = -n; k <= n; k++) {
            var t = k.abs().toFloat() / (n + 1);
            dc.setColor(Palette.blend(Palette.RULE, 0x000000, 1.0 - t * t), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(227 + k * PITCH, y, 1.6);
        }
    }

    // Four stats in an open row: muted icon, value and muted unit below.
    private function drawStatsOpen(dc as Dc, cgm as Dictionary?) as Void {
        var slots = ["Stat1", "Stat2", "Stat3", "Stat4b"];
        var defaults = [Fields.STEPS, Fields.ELEVATION_GAIN, Fields.BODY_BATTERY, Fields.TEMPERATURE];
        var xs = [104, 186, 268, 350];
        var tall = tallGraph();
        for (var i = 0; i < 4; i++) {
            var v = Fields.value(CgmConfig.getNumber(slots[i], defaults[i]), cgm);
            if (v == null) {
                continue;
            }
            if (tall) {
                // A column beside the tall graph, one field per row, caps spanning the graph's
                // height: icon, then the value at 30 px with its unit.
                var base = TALL_TOP + 19 + i * 30;
                icon(dc, v[0] as Symbol, 280, base - 20, 20, Palette.MUTE);
                var s = v[1] as String;
                textAt(dc, :stat, 308, base, s, Palette.FG, Graphics.TEXT_JUSTIFY_LEFT);
                var u = v[2] as String;
                if (u.length() > 0) {
                    textAt(dc, :minmax, 308 + width(dc, :stat, s) + 2, base, u, Palette.MUTE, Graphics.TEXT_JUSTIFY_LEFT);
                }
                continue;
            }
            var cx = xs[i];
            icon(dc, v[0] as Symbol, cx - 11, 327, 22, Palette.MUTE);
            var value = v[1] as String;
            var unit = v[2] as String;
            var w = width(dc, :delta, value) + ((unit.length() > 0) ? 2 + width(dc, :minmax, unit) : 0);
            var x = cx - w / 2;
            textAt(dc, :delta, x, 371, value, Palette.FG, Graphics.TEXT_JUSTIFY_LEFT);
            if (unit.length() > 0) {
                textAt(dc, :minmax, x + width(dc, :delta, value) + 2, 371, unit, Palette.MUTE, Graphics.TEXT_JUSTIFY_LEFT);
            }
        }
    }

    // 3 h of dots between dotted 70 and 180 lines, centred under the glucose row.
    private function drawGraphOpen(dc as Dc, cgm as Dictionary?, now as Number) as Void {
        // Always-on is taller and narrower, so its corners clear the round edge at every shift.
        var pw = _aod ? 280 : 300;
        var px = 227 - pw / 2 + _ox;
        var py = 264 + _oy;
        var ph = _aod ? 72 : 40;
        if (tallGraph()) {
            // Two and a half times as tall, on the left, so changes read as real slopes.
            pw = 206;
            px = 56 + _ox;
            py = TALL_TOP + _oy;
            ph = TALL_HEIGHT;
        }
        if (!_aod) {
            // Dotted 70 and 180 lines, in the same dot language as the time.
            var top = plotYh(CgmConfig.highMgdl(), py, ph);
            var bottom = plotYh(CgmConfig.lowMgdl(), py, ph);
            dc.setColor(Palette.GUIDE, Graphics.COLOR_TRANSPARENT);
            for (var gx = px + 3; gx < px + pw - 3; gx += 6) {
                dc.fillCircle(gx, top, 1);
                dc.fillCircle(gx, bottom, 1);
            }
        }
        if (cgm == null) {
            return;
        }
        var hist = cgm["hist"] as Array;
        var n = hist.size();
        var shift = (now - (cgm["t"] as Number)) / CgmConfig.SLOT_SECONDS;
        var stale = isStale(cgm, now);
        var x0 = px + 3;
        var x1 = px + pw - 5;
        var step = (x1 - x0).toFloat() / (n - 1);
        var lastX = -1.0;
        var lastY = 0;
        var lastV = 0;
        for (var i = 0; i < n; i++) {
            var v = hist[i];
            if (v == null) {
                continue;
            }
            var x = x1 - (n - 1 - i + shift) * step;
            if (x < x0) {
                continue;
            }
            var y = plotYh(v as Number, py, ph);
            dc.setColor(Palette.dot(CgmModel.state(v as Number, stale), _aod), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 2.1);
            lastX = x;
            lastY = y;
            lastV = v as Number;
        }
        if (lastX >= 0) {
            dc.setColor(Palette.dot(CgmModel.state(lastV, stale), _aod), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(lastX, lastY, 4.0);
        }
    }

    // The "Tall graph" layout setting; always-on keeps the classic graph.
    private const TALL_TOP = 262;
    private const TALL_HEIGHT = 106;

    private function tallGraph() as Boolean {
        return !_aod && CgmConfig.getNumber("Layout", 1) == 1;
    }

    private function plotYh(mgdl as Number, top as Number, h as Number) as Number {
        var v = (mgdl < 50) ? 50 : ((mgdl > 230) ? 230 : mgdl);
        return top + h - h * (v - 50) / 180;
    }

    // ---- primitives ------------------------------------------------------------------------

    private function font(key as Symbol) {
        return (_fonts[key] as Array)[0];
    }

    // Text at a Figma text-box top.
    private function text(dc as Dc, key as Symbol, x as Number, top as Number, s as String, color as Number, justify as Number) as Void {
        var f = _fonts[key] as Array;
        stamp(dc, f, x + _ox, top + (f[1] as Number) + _oy, s, color, justify);
    }

    // Text with its baseline at y.
    private function textAt(dc as Dc, key as Symbol, x as Number, y as Number, s as String, color as Number, justify as Number) as Void {
        var f = _fonts[key] as Array;
        stamp(dc, f, x + _ox, y - (f[2] as Number) + _oy, s, color, justify);
    }

    // Draws the text once, or restamped 1-2 px to the right for a faux-bold fallback face.
    private function stamp(dc as Dc, f as Array, x as Number, y as Number, s as String, color as Number, justify as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var bold = f[3] as Number;
        for (var i = 0; i <= bold; i++) {
            dc.drawText(x + i, y, f[0], s, justify);
        }
    }

    private function width(dc as Dc, key as Symbol, s as String) as Number {
        return dc.getTextWidthInPixels(s, font(key)) + ((_fonts[key] as Array)[3] as Number);
    }

    // Vector icon `size` px square, top-left at (x, y).
    private function icon(dc as Dc, key as Symbol, x as Numeric, y as Numeric, size as Number, color as Number) as Void {
        Icons.draw(dc, key, x + _ox, y + _oy, size, color);
    }

    private function isStale(cgm as Dictionary, now as Number) as Boolean {
        return now - (cgm["t"] as Number) > CgmModel.STALE_SECONDS;
    }

    // ---- sections --------------------------------------------------------------------------

    // Pure black, active and always-on alike.
    private function drawBackground(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
    }

    // Bluetooth (only while the phone is connected) and battery, centred as a larger group.
    private function drawStatus(dc as Dc, settings as System.DeviceSettings) as Void {
        var mute = _aod ? Palette.AOD_MUTE : Palette.MUTE;
        var pct = System.getSystemStats().battery;
        var label = pct.format("%d") + "%";
        var connected = settings.phoneConnected;
        var w = 29 + 8 + width(dc, :status, label) + (connected ? 20 + 12 : 0);
        var x = 227 - w / 2;
        if (connected) {
            icon(dc, :bluetooth, x, 17, 20, mute);
            x += 32;
        }
        // Battery outline whose fill tracks the charge.
        var bx = x + _ox;
        var by = 20 + _oy;
        dc.setColor(mute, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(bx, by, 26, 15, 4);
        dc.fillRectangle(bx + 26, by + 5, 3, 5);
        var fill = (22 * pct / 100).toNumber();
        if (fill > 0) {
            dc.fillRectangle(bx + 2, by + 2, fill, 11);
        }
        textAt(dc, :status, x + 37, 35, label, mute, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Trend arrow: flat for under 1 mg/dL per minute, 45 degrees for 1-2, vertical for 2-3 and
    // a double arrow above 3, pointing down when falling. Centred on (cx, cy).
    private function drawTrend(dc as Dc, cgm as Dictionary, cx as Number, cy as Number, color as Number) as Void {
        var rate = 0.0;
        var delta = cgm["delta"];
        if (delta != null) {
            rate = delta.toFloat() / 5.0;
        } else {
            var dir = CgmModel.direction(cgm);
            var m = (dir.find("Double") != null) ? 3.5 : ((dir.find("Single") != null) ? 2.5 : ((dir.find("FortyFive") != null) ? 1.5 : 0.0));
            rate = (dir.find("Down") != null) ? -m : m;
        }
        var a = rate.abs();
        var angle = (a > 2.0) ? 90 : ((a > 1.0) ? 45 : 0);
        if (rate < 0) {
            angle = -angle;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (a > 3.0) {
            arrow(dc, cx - 13, cy, angle, 0.75 * TREND_SCALE);
            arrow(dc, cx + 13, cy, angle, 0.75 * TREND_SCALE);
        } else {
            arrow(dc, cx, cy, angle, ((angle == 0) ? 0.94 : 1.0) * TREND_SCALE);
        }
    }

    // Arrow centred on (cx, cy), pointing right and turned anticlockwise by `angle` degrees: a
    // 36 px shaft and an open head, both 7 px wide like Bionic Bold's stems at the glucose size,
    // with square ends. One polygon, so it stays clean when anti-aliased.
    private function arrow(dc as Dc, cx as Number, cy as Number, angle as Number, scale as Float) as Void {
        var w = 7.0;
        var h = 12.0;
        var e = 18.0;
        var d = w * 0.7071;
        var shape = [[-e, -w / 2], [e - 2 * d - w / 2, -w / 2], [e - h - d, -h + d], [e - h, -h], [e, 0],
            [e - h, h], [e - h - d, h - d], [e - 2 * d - w / 2, w / 2], [-e, w / 2]];
        var r = Math.toRadians(angle);
        var c = Math.cos(r) * scale;
        var sn = Math.sin(r) * scale;
        var pts = new [shape.size()];
        for (var i = 0; i < shape.size(); i++) {
            var p = shape[i];
            pts[i] = [cx + p[0] * c + p[1] * sn, cy - p[0] * sn + p[1] * c];
        }
        dc.fillPolygon(pts);
    }

    // Heart rate (or whichever field is chosen) at the bottom. The heart beats once a second
    // while the watch is awake (onUpdate runs every second then), never in always-on.
    private function drawBottom(dc as Dc, field as Number, cgm as Dictionary?) as Void {
        var v = Fields.value(field, cgm);
        if (v == null) {
            return;
        }
        // Muted like the stats icons: red is kept for low glucose.
        var col = _aod ? Palette.AOD_MUTE : Palette.MUTE;
        // Vector heart; the beat shrinks it to 85% every other second.
        var size = (field == Fields.HEART && !_aod && System.getClockTime().sec % 2 == 1) ? 22 : 26;
        icon(dc, v[0] as Symbol, 183 - size / 2, 407 - size / 2, size, col);
        var s = v[1] as String;
        textAt(dc, :heart, 202, 417, s, _aod ? Palette.AOD_FG : Palette.FG, Graphics.TEXT_JUSTIFY_LEFT);
        var unit = v[2] as String;
        if (unit.length() > 0) {
            textAt(dc, :bpm, 202 + width(dc, :heart, s) + 4, 417, unit, _aod ? Palette.AOD_MUTE : Palette.MUTE, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }
}
