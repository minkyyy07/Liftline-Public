import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'nutrition_calc.dart';
import 'theme.dart';

class ChartPt {
  final DateTime date;
  final double value;
  const ChartPt(this.date, this.value);
}

/// Simple line chart: straight segments (no smoothing), visible axis bounds,
/// tap a point to see its date and value. One point is drawn as a dot only.
class LineChartView extends StatefulWidget {
  final List<ChartPt> points;
  final List<ChartPt> trend; // optional second line (labelled by caller)
  final String unit;
  final double height;
  const LineChartView(
      {super.key,
      required this.points,
      this.trend = const [],
      required this.unit,
      this.height = 200});
  @override
  State<LineChartView> createState() => _LineChartViewState();
}

class _LineChartViewState extends State<LineChartView> {
  int? _sel;

  @override
  void didUpdateWidget(covariant LineChartView old) {
    super.didUpdateWidget(old);
    if (_sel != null && _sel! >= widget.points.length) _sel = null;
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    final fmt = DateFormat('d MMM yyyy', 'ru');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (ctx, c) {
        final painter = _ChartPainter(pts, widget.trend, _sel, widget.unit);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final i = painter.nearest(d.localPosition, Size(c.maxWidth, widget.height));
            setState(() => _sel = i);
          },
          child: Semantics(
            label: 'График, точек: ${pts.length}',
            child: CustomPaint(
                size: Size(c.maxWidth, widget.height), painter: painter),
          ),
        );
      }),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _sel == null
              ? 'Нажмите на точку, чтобы увидеть дату и значение'
              : '${fmt.format(pts[_sel!].date)}: ${fmtG(pts[_sel!].value)} ${widget.unit}',
          style: const TextStyle(fontSize: 12, color: LlColors.textSecondary),
        ),
      ),
    ]);
  }
}

class _ChartPainter extends CustomPainter {
  final List<ChartPt> pts;
  final List<ChartPt> trend;
  final int? sel;
  final String unit;
  _ChartPainter(this.pts, this.trend, this.sel, this.unit);

  static const _l = 44.0, _r = 8.0, _t = 8.0, _b = 22.0;

  (double, double) _yRange() {
    final all = [...pts, ...trend].map((p) => p.value);
    var lo = all.reduce(math.min), hi = all.reduce(math.max);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.1;
    return (lo - pad, hi + pad);
  }

  (double, double) _xRange() {
    final all = [...pts, ...trend].map((p) => p.date.millisecondsSinceEpoch.toDouble());
    var lo = all.reduce(math.min), hi = all.reduce(math.max);
    if (hi - lo < 1) hi = lo + 86400000;
    return (lo, hi);
  }

  Offset _pos(ChartPt p, Size s, (double, double) xr, (double, double) yr) {
    final w = s.width - _l - _r, h = s.height - _t - _b;
    final x = pts.length == 1 && trend.isEmpty
        ? _l + w / 2
        : _l + (p.date.millisecondsSinceEpoch - xr.$1) / (xr.$2 - xr.$1) * w;
    final y = _t + (1 - (p.value - yr.$1) / (yr.$2 - yr.$1)) * h;
    return Offset(x, y);
  }

  int? nearest(Offset tap, Size s) {
    if (pts.isEmpty) return null;
    final xr = _xRange(), yr = _yRange();
    int? best;
    var bd = 32.0;
    for (var i = 0; i < pts.length; i++) {
      final d = (_pos(pts[i], s, xr, yr) - tap).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  void _text(Canvas c, String s, Offset o, {bool right = false}) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: const TextStyle(fontSize: 10, color: LlColors.textSecondary)),
        textDirection: TextDirection.ltr)
      ..layout();
    c.drawText(tp, right ? Offset(o.dx - tp.width, o.dy - tp.height / 2) : o);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty) return;
    final xr = _xRange(), yr = _yRange();
    final grid = Paint()..color = LlColors.surfaceHigh..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final v = yr.$1 + (yr.$2 - yr.$1) * i / 3;
      final y = _pos(ChartPt(DateTime.now(), v), size, xr, yr).dy;
      canvas.drawLine(Offset(_l, y), Offset(size.width - _r, y), grid);
      _text(canvas, fmtG(double.parse(v.toStringAsFixed(1))), Offset(_l - 4, y), right: true);
    }
    final df = DateFormat('d MMM', 'ru');
    _text(canvas, df.format(DateTime.fromMillisecondsSinceEpoch(xr.$1.toInt())), Offset(_l, size.height - 14));
    final last = df.format(DateTime.fromMillisecondsSinceEpoch(xr.$2.toInt()));
    _text(canvas, last, Offset(size.width - _r - 36, size.height - 14));

    void line(List<ChartPt> l, Color col, double w) {
      final p = Paint()..color = col..strokeWidth = w..style = PaintingStyle.stroke;
      for (var i = 1; i < l.length; i++) {
        canvas.drawLine(_pos(l[i - 1], size, xr, yr), _pos(l[i], size, xr, yr), p);
      }
    }

    line(trend, LlColors.secondary, 2);
    line(pts, LlColors.accent, 2);
    for (var i = 0; i < pts.length; i++) {
      final o = _pos(pts[i], size, xr, yr);
      canvas.drawCircle(o, i == sel ? 6 : 3.5, Paint()..color = i == sel ? LlColors.text : LlColors.accent);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter o) => true;
}

extension on Canvas {
  void drawText(TextPainter tp, Offset o) => tp.paint(this, o);
}
