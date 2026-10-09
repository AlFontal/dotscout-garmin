import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Icons drawn as anti-aliased vector shapes at their final size, which renders much cleaner on
// the watch than small bitmaps. Shapes are defined on a 28-unit grid. Less common fields fall
// back to the white bitmaps from tools/gen_assets.py, tinted.
module Icons {
    var _bitmaps as Dictionary = {};
    var _heart as Array? = null;
    // Colour behind the icon, for cut-outs such as the phone's screen.
    var cutout as Number = 0x000000;

    // Draws icon `key` with its top-left at (x, y), `size` px square.
    function draw(dc as Dc, key as Symbol, x as Numeric, y as Numeric, size as Numeric, color as Number) as Void {
        var k = size / 28.0;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (key == :heart) {
            heart(dc, x + size / 2.0, y + size / 2.0, size);
        } else if (key == :steps) {
            // Two footprints, each a sole and a heel.
            ellipse(dc, x, y, k, 8.5, 8.5, 4.6, 6.4);
            ellipse(dc, x, y, k, 8.5, 19, 3.4, 2.6);
            ellipse(dc, x, y, k, 19.5, 12.5, 4.6, 6.4);
            ellipse(dc, x, y, k, 19.5, 23, 3.4, 2.6);
        } else if (key == :ascent) {
            poly(dc, x, y, k, [[2, 24], [11, 8], [16, 16], [19, 12], [26, 24]]);
            poly(dc, x, y, k, [[20, 1.5], [25, 7], [21.5, 7], [21.5, 10.5], [18.5, 10.5], [18.5, 7], [15, 7]]);
        } else if (key == :bodyBattery) {
            poly(dc, x, y, k, [[17, 1.5], [6, 16], [13, 16], [11, 26.5], [22.5, 11], [15.5, 11], [18, 1.5]]);
        } else if (key == :floors) {
            poly(dc, x, y, k, [[3, 25], [3, 19.5], [9, 19.5], [9, 14], [15, 14], [15, 8.5], [21, 8.5], [21, 3], [26, 3], [26, 25]]);
        } else if (key == :temperature) {
            // Solid silhouette (stem and bulb) with two scale ticks; outlines look broken this small.
            dc.fillRoundedRectangle(x + 10 * k, y + 2 * k, 7 * k, 18 * k, 3.5 * k);
            dc.fillCircle(x + 13.5 * k, y + 21 * k, 5.5 * k);
            dc.setPenWidth(stroke(k, 2.4));
            dc.drawLine(x + 19.5 * k, y + 6 * k, x + 24 * k, y + 6 * k);
            dc.drawLine(x + 19.5 * k, y + 11 * k, x + 24 * k, y + 11 * k);
        } else if (key == :battery) {
            dc.setPenWidth(stroke(k, 2.4));
            dc.drawRoundedRectangle(x + 2 * k, y + 8 * k, 21 * k, 12 * k, 2.5 * k);
            dc.fillRectangle(x + 23.5 * k, y + 11.5 * k, 2.5 * k, 5 * k);
            dc.fillRectangle(x + 5 * k, y + 11 * k, 12 * k, 6 * k);
        } else if (key == :bluetooth) {
            // Sharp joins: round ones merge into a blob at status-row size.
            dc.setPenWidth(stroke(k, 3.0));
            var b = [[7.5, 8.5], [20, 19.5], [14, 25.5], [14, 2.5], [20, 8.5], [7.5, 19.5]];
            for (var i = 1; i < b.size(); i++) {
                dc.drawLine(x + b[i - 1][0] * k, y + b[i - 1][1] * k, x + b[i][0] * k, y + b[i][1] * k);
            }
        } else if (key == :phone) {
            // Solid body with a cut-out screen, so it doesn't read as a "0".
            dc.fillRoundedRectangle(x + 7.5 * k, y + 1.5 * k, 13 * k, 25 * k, 3 * k);
            dc.setColor(cutout, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x + 10 * k, y + 5 * k, 8 * k, 15 * k);
        } else if (key == :bell) {
            dc.fillCircle(x + 14 * k, y + 12.5 * k, 7.5 * k);
            poly(dc, x, y, k, [[6.5, 12.5], [21.5, 12.5], [22, 18.5], [25, 21.5], [3, 21.5], [6, 18.5]]);
            dc.fillCircle(x + 14 * k, y + 23.5 * k, 2.5 * k);
            dc.fillCircle(x + 14 * k, y + 4 * k, 1.8 * k);
        } else if (key == :clock) {
            dc.setPenWidth(stroke(k, 2.6));
            dc.drawCircle(x + 14 * k, y + 14 * k, 11 * k);
            lines(dc, x, y, k, [[14, 7.5], [14, 14], [18.5, 17]], stroke(k, 2.6));
        } else if (key == :arrowUp) {
            lines(dc, x, y, k, [[14, 25], [14, 5]], stroke(k, 3.2));
            lines(dc, x, y, k, [[6, 13], [14, 4.5], [22, 13]], stroke(k, 3.2));
        } else if (key == :arrowDown) {
            lines(dc, x, y, k, [[14, 3], [14, 23]], stroke(k, 3.2));
            lines(dc, x, y, k, [[6, 15], [14, 23.5], [22, 15]], stroke(k, 3.2));
        } else {
            bitmap(dc, key, x, y, size, color);
        }
    }

    // Smooth parametric heart centred on (cx, cy), `size` px wide.
    function heart(dc as Dc, cx as Numeric, cy as Numeric, size as Numeric) as Void {
        if (_heart == null) {
            var pts = new [40];
            for (var i = 0; i < 40; i++) {
                var t = 2 * Math.PI * i / 40;
                var sn = Math.sin(t);
                pts[i] = [16 * sn * sn * sn / 34.0, -(13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t)) / 34.0];
            }
            _heart = pts;
        }
        var src = _heart as Array;
        var pts = new [src.size()];
        for (var i = 0; i < src.size(); i++) {
            var p = src[i] as Array;
            pts[i] = [cx + (p[0] as Float) * size, cy + 0.03 * size + (p[1] as Float) * size];
        }
        dc.fillPolygon(pts);
    }

    function stroke(k as Float, units as Float) as Number {
        var w = Math.round(units * k).toNumber();
        return (w < 1) ? 1 : w;
    }

    function poly(dc as Dc, x as Numeric, y as Numeric, k as Float, pts as Array) as Void {
        var out = new [pts.size()];
        for (var i = 0; i < pts.size(); i++) {
            var p = pts[i] as Array;
            out[i] = [x + (p[0] as Numeric) * k, y + (p[1] as Numeric) * k];
        }
        dc.fillPolygon(out);
    }

    // Polyline w px wide with round joins and ends.
    function lines(dc as Dc, x as Numeric, y as Numeric, k as Float, pts as Array, w as Number) as Void {
        dc.setPenWidth(w);
        for (var i = 0; i < pts.size(); i++) {
            var p = pts[i] as Array;
            var px = x + (p[0] as Numeric) * k;
            var py = y + (p[1] as Numeric) * k;
            if (i > 0) {
                var q = pts[i - 1] as Array;
                dc.drawLine(x + (q[0] as Numeric) * k, y + (q[1] as Numeric) * k, px, py);
            }
            if (w >= 2) {
                dc.fillCircle(px, py, w / 2.0);
            }
        }
    }

    function ellipse(dc as Dc, x as Numeric, y as Numeric, k as Float, cx as Numeric, cy as Numeric, rx as Numeric, ry as Numeric) as Void {
        dc.fillEllipse(x + cx * k, y + cy * k, rx * k, ry * k);
    }

    function bitmap(dc as Dc, key as Symbol, x as Numeric, y as Numeric, size as Numeric, color as Number) as Void {
        var ids = {
            :calories => Rez.Drawables.IconCalories, :temperature => Rez.Drawables.IconTemperature,
            :iob => Rez.Drawables.IconIob, :cob => Rez.Drawables.IconCob, :basal => Rez.Drawables.IconBasal,
            :vo2max => Rez.Drawables.IconVo2max, :stress => Rez.Drawables.IconStress,
            :activeMin => Rez.Drawables.IconActivemin
        };
        var id = ids[key];
        if (id == null) {
            return;
        }
        var b = _bitmaps[key];
        if (b == null) {
            b = WatchUi.loadResource(id as ResourceId);
            _bitmaps[key] = b;
        }
        var bmp = b as BitmapResource;
        var bx = x + (size - bmp.getWidth()) / 2;
        var by = y + (size - bmp.getHeight()) / 2;
        if (dc has :drawBitmap2) {
            dc.drawBitmap2(bx, by, bmp, {:tintColor => color});
        } else {
            dc.drawBitmap(bx, by, bmp);
        }
    }
}
