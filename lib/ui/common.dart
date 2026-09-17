import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';

/// ---------- 颜色与格式化 ----------

/// 按涨跌返回颜色（遵循用户设置的红涨绿跌）。
Color upDownColor(double pct, BuildContext context) {
  if (pct.isNaN) return Theme.of(context).colorScheme.outline;
  final redUp = AppState.shared.redUp;
  if (pct > 0) return redUp ? const Color(0xFFE03B3B) : const Color(0xFF1CA349);
  if (pct < 0) return redUp ? const Color(0xFF1CA349) : const Color(0xFFE03B3B);
  return Theme.of(context).colorScheme.outline;
}

/// 涨跌强度因子：|pct| 达到 [maxPct]% 时为 1（最深），低幅较快加深。
double _pctIntensity(double pct, double maxPct) {
  final x = (pct.abs() / maxPct).clamp(0.0, 1.0);
  return math.pow(x, 0.65).toDouble();
}

/// 按涨跌幅渐变加深的文字色：涨/跌越多颜色越深（约 3% 达到最深）。
Color upDownColorDeep(double pct, BuildContext context, {double maxPct = 3}) {
  if (pct.isNaN || pct == 0) return upDownColor(pct, context);
  final redUp = AppState.shared.redUp;
  final deep = pct > 0
      ? (redUp ? const Color(0xFFA50F0F) : const Color(0xFF0B6B2F))
      : (redUp ? const Color(0xFF0B6B2F) : const Color(0xFFA50F0F));
  return Color.lerp(upDownColor(pct, context), deep, _pctIntensity(pct, maxPct))!;
}

/// 涨跌方向色的渐变底色（指数卡整盒背景）：幅度越大底色越浓。
Color upDownTint(double pct, BuildContext context, {double maxPct = 3}) {
  final scheme = Theme.of(context).colorScheme;
  final base = scheme.surfaceContainerLow;
  if (pct.isNaN || pct == 0) return base;
  final c = upDownColor(pct, context);
  return Color.lerp(base, c, 0.16 + 0.4 * _pctIntensity(pct, maxPct))!;
}

/// 涨跌幅文本，如 +1.23%。
String pctText(double pct, {bool withSign = true}) {
  if (pct.isNaN) return '--';
  final v = pct.abs() < 0.005 ? 0 : pct;
  final s = v.toStringAsFixed(2);
  return withSign && v > 0 ? '+$s%' : '$s%';
}

/// 金额：元 → 万/亿。
String fmtMoney(double v) {
  final a = v.abs();
  if (a >= 1e8) return '${(v / 1e8).toStringAsFixed(2)}亿';
  if (a >= 1e4) return '${(v / 1e4).toStringAsFixed(1)}万';
  return v.toStringAsFixed(2);
}

/// 价格（指数大数字加千分位）。
String fmtPrice(double v) {
  if (v.abs() >= 1000) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final buf = StringBuffer();
    for (var i = 0; i < parts[0].length; i++) {
      final idx = parts[0].length - i;
      buf.write(parts[0][i]);
      if (idx > 1 && (idx - 1) % 3 == 0) buf.write(',');
    }
    return '${buf.toString()}.${parts[1]}';
  }
  return v.toStringAsFixed(2);
}

/// 涨跌幅文本组件。
class PctText extends StatelessWidget {
  const PctText(
    this.pct, {
    super.key,
    this.fontSize = 15,
    this.bold = true,
    this.withSign = true,
  });

  final double pct;
  final double fontSize;
  final bool bold;
  final bool withSign;

  @override
  Widget build(BuildContext context) {
    return Text(
      pctText(pct, withSign: withSign),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color: upDownColor(pct, context),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// ---------- 迷你走势（指数卡片） ----------

class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.width = 72,
    this.height = 28,
  });

  final List<double> values;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _SparkPainter(values, color),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var mn = values.first, mx = values.first;
    for (final v in values) {
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    final span = (mx - mn) == 0 ? 1.0 : mx - mn;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - 2 - (values[i] - mn) / span * (size.height - 4);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values;
}

/// ---------- 分时图（估值 % 或价格） ----------

/// 通用分时/走势折线图：基线、渐变填充、坐标轴标签、触摸读数。
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.base,
    this.height = 220,
    this.isPct = false,
    this.forceColor,
    this.xLabelCount = 4,
  });

  /// 分时点。
  final List<TrendPoint> points;

  /// 基线值（%图传 0，价格图传昨收）。
  final double base;

  final double height;

  /// true: 值本身是涨跌幅；false: 价格相对 [base] 计算涨跌。
  final bool isPct;

  /// 强制线条颜色（如净值走势用主题色）。
  final Color? forceColor;

  final int xLabelCount;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _touchIdx;

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    final scheme = Theme.of(context).colorScheme;
    if (pts.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            '数据采样中，请稍候…',
            style: TextStyle(color: scheme.outline, fontSize: 13),
          ),
        ),
      );
    }
    double pctOf(double v) => widget.isPct
        ? v
        : (widget.base == 0
            ? 0.0
            : (v - widget.base) / widget.base * 100);
    var mn = pctOf(pts.first.value), mx = mn;
    for (final p in pts) {
      final v = pctOf(p.value);
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    if (pctOf(widget.base) < mn) mn = pctOf(widget.base);
    if (pctOf(widget.base) > mx) mx = pctOf(widget.base);
    if (mx - mn < 0.2) {
      final mid = (mx + mn) / 2;
      mn = mid - 0.1;
      mx = mid + 0.1;
    }
    final pad = (mx - mn) * 0.08;
    mn -= pad;
    mx += pad;
    final lastPct = widget.isPct ? pts.last.value : pctOf(pts.last.value);
    final mainColor = widget.forceColor ?? upDownColor(lastPct, context);

    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => _locate(d.localPosition, pts),
            onPanDown: (d) => _locate(d.localPosition, pts),
            onPanCancel: () => setState(() => _touchIdx = null),
            onPanEnd: (_) => setState(() => _touchIdx = null),
            child: CustomPaint(
              size: Size.infinite,
              painter: _TrendPainter(
                points: pts,
                base: widget.base,
                isPct: widget.isPct,
                min: mn,
                max: mx,
                color: mainColor,
                gridColor: scheme.outlineVariant,
                labelColor: scheme.outline,
                touchIdx: _touchIdx,
                xLabelCount: widget.xLabelCount,
              ),
            ),
          ),
        ),
        if (_touchIdx != null && _touchIdx! < pts.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${pts[_touchIdx!].label}  '
              '${widget.isPct ? pctText(pts[_touchIdx!].value) : fmtPrice(pts[_touchIdx!].value)}  '
              '（${pctText(widget.isPct ? pts[_touchIdx!].value : pctOf(pts[_touchIdx!].value))}）',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: mainColor,
              ),
            ),
          ),
      ],
    );
  }

  void _locate(Offset local, List<TrendPoint> pts) {
    final w = context.size?.width ?? 1;
    final idx = ((local.dx - 34) / (w - 34) * (pts.length - 1)).round();
    setState(() => _touchIdx = idx.clamp(0, pts.length - 1));
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.base,
    required this.isPct,
    required this.min,
    required this.max,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    this.touchIdx,
    this.xLabelCount = 4,
  });

  final List<TrendPoint> points;
  final double base;
  final bool isPct;
  final double min, max;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final int? touchIdx;
  final int xLabelCount;

  static const _leftPad = 34.0;
  static const _bottomPad = 18.0;

  double _xOf(int i, Size size) =>
      _leftPad + (size.width - _leftPad - 6) * i / (points.length - 1);

  double _yOf(double pct, Size size) =>
      (size.height - _bottomPad) * (1 - (pct - min) / (max - min)) + 4;

  double _pctOf(double v) =>
      isPct ? v : (base == 0 ? 0.0 : (v - base) / base * 100);

  @override
  void paint(Canvas canvas, Size size) {
    TextPainter tp(String s) => TextPainter(
          text: TextSpan(text: s, style: TextStyle(fontSize: 10, color: labelColor)),
          textDirection: TextDirection.ltr,
        )..layout();

    // 横向网格与 y 轴标签（含基线）。
    final basePct = _pctOf(base);
    final gridVals = <double>{basePct, min + (max - min) * 0.25, min + (max - min) * 0.75, (min + max) / 2};
    for (final gv in gridVals) {
      final y = _yOf(gv, size);
      final isBase = (gv - basePct).abs() < 1e-9;
      canvas.drawLine(
        Offset(_leftPad, y),
        Offset(size.width - 4, y),
        Paint()
          ..color = isBase ? color.withValues(alpha: .55) : gridColor
          ..strokeWidth = isBase ? 1 : 0.5,
      );
      if (isBase) {
        final p = tp(_fmtPct(gv));
        p.paint(canvas, Offset(2, y - p.height / 2));
      }
    }
    final topPct = min + (max - min) * 0.92;
    final p1 = tp(_fmtPct(topPct));
    p1.paint(canvas, Offset(2, 2));
    final botPct = min + (max - min) * 0.08;
    final p2 = tp(_fmtPct(botPct));
    p2.paint(canvas, Offset(2, size.height - _bottomPad - p2.height));

    // 折线与填充。
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = _xOf(i, size);
      final y = _yOf(_pctOf(points[i].value), size);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(_xOf(points.length - 1, size), _yOf(basePct, size))
      ..lineTo(_xOf(0, size), _yOf(basePct, size))
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .18), color.withValues(alpha: 0)],
        ).createShader(fill.getBounds()),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );

    // 末端点。
    final lx = _xOf(points.length - 1, size);
    final ly = _yOf(_pctOf(points.last.value), size);
    canvas.drawCircle(Offset(lx, ly), 2.6, Paint()..color = color);

    // x 轴标签。
    for (var k = 0; k < xLabelCount; k++) {
      final i = (k * (points.length - 1) / (xLabelCount - 1)).round();
      final label = points[i].label;
      final p = tp(label);
      final x = (_xOf(i, size) - p.width / 2)
          .clamp(_leftPad - 6, size.width - p.width - 2)
          .toDouble();
      p.paint(canvas, Offset(x, size.height - _bottomPad + 3));
    }

    // 触摸十字线。
    if (touchIdx != null && touchIdx! >= 0 && touchIdx! < points.length) {
      final x = _xOf(touchIdx!, size);
      final y = _yOf(_pctOf(points[touchIdx!].value), size);
      canvas.drawLine(
        Offset(x, 4),
        Offset(x, size.height - _bottomPad),
        Paint()
          ..color = color.withValues(alpha: .5)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        Offset(x, y),
        3.4,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  String _fmtPct(double v) => v >= 0 ? '+${v.toStringAsFixed(2)}' : v.toStringAsFixed(2);

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points ||
      old.touchIdx != touchIdx ||
      old.min != min ||
      old.max != max ||
      old.color != color;
}

/// ---------- 历史净值走势图 ----------

/// 净值历史折线图：x 为日期，触摸显示日期与净值。
class NavChart extends StatefulWidget {
  const NavChart({
    super.key,
    required this.data,
    required this.rangeDays,
    this.height = 200,
  });

  /// [时间戳ms, 单位净值]。
  final List<List<double>> data;

  /// 显示区间天数，null = 全部。
  final int? rangeDays;

  final double height;

  @override
  State<NavChart> createState() => _NavChartState();
}

class _NavChartState extends State<NavChart> {
  int? _touchIdx;

  List<List<double>> get _sliced {
    if (widget.rangeDays == null) return widget.data;
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - widget.rangeDays! * 86400000;
    final s = widget.data.where((e) => e[0] >= cutoff).toList();
    return s.length >= 2 ? s : widget.data;
  }

  @override
  Widget build(BuildContext context) {
    final data = _sliced;
    final scheme = Theme.of(context).colorScheme;
    if (data.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text('暂无数据', style: TextStyle(color: scheme.outline, fontSize: 13)),
        ),
      );
    }
    return SizedBox(
      height: widget.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) => _locate(d.localPosition, data),
        onPanUpdate: (d) => _locate(d.localPosition, data),
        onPanCancel: () => setState(() => _touchIdx = null),
        onPanEnd: (_) => setState(() => _touchIdx = null),
        child: CustomPaint(
          size: Size.infinite,
          painter: _NavPainter(
            data: data,
            color: scheme.primary,
            gridColor: scheme.outlineVariant,
            labelColor: scheme.outline,
            touchIdx: _touchIdx,
          ),
        ),
      ),
    );
  }

  void _locate(Offset local, List<List<double>> data) {
    final w = context.size?.width ?? 1;
    final idx =
        ((local.dx - 40) / (w - 46) * (data.length - 1)).round();
    setState(() => _touchIdx = idx.clamp(0, data.length - 1));
  }
}

class _NavPainter extends CustomPainter {
  _NavPainter({
    required this.data,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    this.touchIdx,
  });

  final List<List<double>> data;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final int? touchIdx;

  static const _leftPad = 40.0;
  static const _bottomPad = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    var mn = data.first[1], mx = mn;
    for (final e in data) {
      if (e[1] < mn) mn = e[1];
      if (e[1] > mx) mx = e[1];
    }
    if (mx - mn < 1e-6) {
      mn -= 0.01;
      mx += 0.01;
    }
    final pad = (mx - mn) * 0.08;
    mn -= pad;
    mx += pad;

    double xOf(int i) =>
        _leftPad + (size.width - _leftPad - 6) * i / (data.length - 1);
    double yOf(double v) =>
        (size.height - _bottomPad) * (1 - (v - mn) / (mx - mn)) + 4;

    TextPainter tp(String s) => TextPainter(
          text: TextSpan(text: s, style: TextStyle(fontSize: 10, color: labelColor)),
          textDirection: TextDirection.ltr,
        )..layout();

    // 网格 + y 标签。
    for (var g = 0; g <= 2; g++) {
      final v = mn + (mx - mn) * g / 2;
      final y = yOf(v);
      canvas.drawLine(
        Offset(_leftPad, y),
        Offset(size.width - 4, y),
        Paint()
          ..color = gridColor
          ..strokeWidth = 0.5,
      );
      final p = tp(v.toStringAsFixed(v > 10 ? 2 : 4));
      p.paint(canvas, Offset(_leftPad - p.width - 4, y - p.height / 2));
    }

    // 折线 + 填充。
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      i == 0
          ? path.moveTo(xOf(i), yOf(data[i][1]))
          : path.lineTo(xOf(i), yOf(data[i][1]));
    }
    final fill = Path.from(path)
      ..lineTo(xOf(data.length - 1), size.height - _bottomPad)
      ..lineTo(xOf(0), size.height - _bottomPad)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .16), color.withValues(alpha: 0)],
        ).createShader(fill.getBounds()),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // x 标签（起、中、末）。
    for (final i in [0, (data.length - 1) ~/ 2, data.length - 1]) {
      final d = DateTime.fromMillisecondsSinceEpoch(data[i][0].round());
      final p = tp('${d.year.toString().substring(2)}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
      final x = (xOf(i) - p.width / 2)
          .clamp(_leftPad - 4, size.width - p.width - 2)
          .toDouble();
      p.paint(canvas, Offset(x, size.height - _bottomPad + 3));
    }

    // 触摸。
    if (touchIdx != null && touchIdx! >= 0 && touchIdx! < data.length) {
      final x = xOf(touchIdx!);
      final y = yOf(data[touchIdx!][1]);
      canvas.drawLine(
        Offset(x, 4),
        Offset(x, size.height - _bottomPad),
        Paint()
          ..color = color.withValues(alpha: .5)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        Offset(x, y),
        3.2,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(_NavPainter old) =>
      old.data != data || old.touchIdx != touchIdx;
}

/// 空状态视图。
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.outlineVariant),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// 小圆角信息卡片。
class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

/// 星级显示。
Widget starRow(int star) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < star ? Icons.star : Icons.star_border,
          size: 14,
          color: const Color(0xFFF5A623),
        ),
      ),
    );

/// 数学小工具（避免未使用 import 警告的占位引用）。
double clamp01(double v) => math.min(1, math.max(0, v));
