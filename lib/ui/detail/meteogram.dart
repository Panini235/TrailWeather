import 'dart:math' as math;

import 'weather_cells.dart';

import 'package:flutter/material.dart';

import '../../core/units.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/wx_importance.dart';
import '../motion.dart';
import '../strings.dart';
import '../tokens.dart';

/// 节点气象时间图（D-035）：同一时间轴上叠放云层、气温/体感、降水量与概率、阵风、紫外线。
///
/// 只画来源给出的整点值，时次之间不插值（折线只是连接相邻整点）；缺失的时次留空。
/// 降水量（柱）与降水概率（列底色）分开画；阵风缺失时风向箭头为灰色，持续风速不顶替阵风。
/// 点按或横向拖动查看某一小时的数值；首次出现从左到右画出一次。
class NodeMeteogram extends StatefulWidget {
  const NodeMeteogram({
    super.key,
    required this.point,
    required this.arrivalUtc,
    required this.settings,
    this.hoursBefore = 3,
    this.span = 24,
  });

  final WxPointForecast point;
  final DateTime arrivalUtc;
  final AppSettings settings;
  final int hoursBefore;
  final int span;

  @override
  State<NodeMeteogram> createState() => _NodeMeteogramState();
}

class _NodeMeteogramState extends State<NodeMeteogram>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: Motion.emphasis,
  );
  late final _curve = CurvedAnimation(parent: _reveal, curve: Motion.enter);
  int? _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reveal.isAnimating || _reveal.isCompleted) return;
    if (Motion.reduced(context, lowPower: widget.settings.lowPower)) {
      _reveal.value = 1;
    } else {
      _reveal.forward();
    }
  }

  @override
  void didUpdateWidget(covariant NodeMeteogram old) {
    super.didUpdateWidget(old);
    if (old.arrivalUtc != widget.arrivalUtc || old.point != widget.point) {
      _selected = null;
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _reveal.dispose();
    super.dispose();
  }

  List<WxHourValue> get _hours {
    final a = widget.arrivalUtc;
    final from = DateTime.utc(
      a.year,
      a.month,
      a.day,
      a.hour,
    ).subtract(Duration(hours: widget.hoursBefore));
    final to = from.add(Duration(hours: widget.span));
    return [
      for (final h in widget.point.displayHours)
        if (!h.validFromUtc.isBefore(from) && h.validFromUtc.isBefore(to)) h,
    ];
  }

  int _arrivalIndex(List<WxHourValue> hours) {
    final a = widget.arrivalUtc;
    final t = DateTime.utc(a.year, a.month, a.day, a.hour);
    final i = hours.indexWhere((h) => h.validFromUtc == t);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final hours = _hours;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (hours.length < 2) {
      return Text(
        S.meteogramNoData,
        style: TextStyle(fontSize: 12, color: muted),
      );
    }
    final arrival = _arrivalIndex(hours);
    final sel = (_selected ?? arrival).clamp(0, hours.length - 1);
    final at = widget.arrivalUtc;
    final showReadout =
        _selected != null &&
        hours[sel].validFromUtc !=
            DateTime.utc(at.year, at.month, at.day, at.hour);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final geom = _Geom(width: c.maxWidth, count: hours.length);
            void pick(Offset p) =>
                setState(() => _selected = geom.columnAt(p.dx));
            return Semantics(
              label: _semantics(hours),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => pick(d.localPosition),
                onHorizontalDragUpdate: (d) => pick(d.localPosition),
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size(c.maxWidth, _Geom.height),
                    painter: _MeteogramPainter(
                      geom: geom,
                      hours: hours,
                      point: widget.point,
                      arrival: arrival,
                      selected: sel,
                      progress: _curve,
                      ink: theme.colorScheme.onSurface,
                      muted: muted,
                      dark: theme.brightness == Brightness.dark,
                      imperial: widget.settings.imperial,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: Space.xs),
        if (showReadout) ...[
          Row(
            children: [
              Expanded(
                child: _Readout(hour: hours[sel], settings: widget.settings),
              ),
              IconButton(
                tooltip: S.close,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _selected = null),
              ),
            ],
          ),
          WeatherHourNotice(wx: hours[sel]),
        ],
        _Legend(color: muted),
      ],
    );
  }

  String _semantics(List<WxHourValue> hours) {
    double? lo, hi, mm;
    for (final h in hours) {
      final t = h.values[WxVar.temperature];
      if (t != null) {
        lo = lo == null ? t : math.min(lo, t);
        hi = hi == null ? t : math.max(hi, t);
      }
      final p = h.values[WxVar.precip];
      if (p != null) mm = (mm ?? 0) + p;
    }
    return S.meteogramSemantics(
      hours: hours.length,
      tempLo: lo?.round(),
      tempHi: hi?.round(),
      precipMm: mm?.toStringAsFixed(1),
    );
  }
}

/// 选中小时的一行数值（图里唯一的文字区）。
class _Readout extends StatelessWidget {
  const _Readout({required this.hour, required this.settings});

  final WxHourValue hour;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final v = hour.values;
    final t = hour.validFromUtc.toLocal();
    String temp(double? x) =>
        x == null ? '—' : Units.temp(x, imperial: settings.imperial);
    final gust = v[WxVar.windGust];
    final dir = v[WxVar.windDir];
    final mm = v[WxVar.precip];
    final prob = v[WxVar.precipProb];
    final uv = v[WxVar.uvIndex];
    final parts = [
      S.meteogramViewing(t.month, t.day, t.hour.toString().padLeft(2, '0')),
      S.meteogramTempFeels(
        temp(v[WxVar.temperature]),
        temp(v[WxVar.apparentTemp]),
      ),
      '${mm == null ? '—' : Units.precipMm(mm, imperial: settings.imperial)}'
          '${prob == null ? '' : ' ${prob.round()}%'}',
      '${S.envGust(gust == null ? '—' : Units.windMs(gust, unit: settings.windUnit))}'
          '${dir == null ? '' : ' ${Units.windDirectionLabel(dir).split(' ').first}'}',
      if (uv != null && uv >= 1) 'UV ${uv.round()}',
    ];
    return Text(
      parts.join('  ·  '),
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 10, color: color);
    Widget item(Widget glyph, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        glyph,
        const SizedBox(width: 3),
        Text(text, style: style),
      ],
    );
    Widget bar(Color c, {double h = 8, double w = 3}) =>
        Container(width: w, height: h, color: c);
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      children: [
        item(bar(Palette.sun, h: 2, w: 12), S.meteogramTemp),
        item(
          bar(Palette.sun.withValues(alpha: 0.5), h: 2, w: 12),
          S.meteogramFeel,
        ),
        item(bar(Semantic.cold), S.meteogramPrecip),
        item(bar(Semantic.cold.withValues(alpha: 0.18), w: 8), S.meteogramProb),
        item(Icon(Icons.navigation, size: 10, color: color), S.meteogramGust),
        item(bar(_uvColor(UvLevel.high), w: 6, h: 6), 'UV'),
      ],
    );
  }
}

/// 世界卫生组织紫外线配色（中等起显示）。
Color _uvColor(UvLevel l) => switch (l) {
  UvLevel.low => Colors.transparent,
  UvLevel.moderate => const Color(0xFFF2C12E),
  UvLevel.high => const Color(0xFFEF8A17),
  UvLevel.veryHigh => const Color(0xFFD7301F),
  UvLevel.extreme => const Color(0xFF8E44AD),
};

/// 图内布局（逻辑像素）。
class _Geom {
  _Geom({required this.width, required this.count});

  static const height = 168.0;
  static const gutter = 16.0;
  static const cloudTop = 0.0, cloudRow = 7.0, cloudGap = 1.0;
  static const tempTop = 30.0, tempBottom = 96.0;
  static const precipTop = 98.0, precipBottom = 120.0;
  static const windY = 133.0;
  static const uvTop = 146.0, uvH = 5.0;
  static const labelY = 154.0;

  final double width;
  final int count;

  double get colW => (width - gutter - 2) / count;
  double x(int i) => gutter + colW * (i + 0.5);
  double left(int i) => gutter + colW * i;
  int columnAt(double dx) => ((dx - gutter) / colW).floor().clamp(0, count - 1);
}

class _MeteogramPainter extends CustomPainter {
  _MeteogramPainter({
    required this.geom,
    required this.hours,
    required this.point,
    required this.arrival,
    required this.selected,
    required this.progress,
    required this.ink,
    required this.muted,
    required this.dark,
    required this.imperial,
  }) : super(repaint: progress);

  final _Geom geom;
  final List<WxHourValue> hours;
  final WxPointForecast point;
  final int arrival;
  final int selected;
  final Animation<double> progress;
  final Color ink;
  final Color muted;
  final bool dark;
  final bool imperial;

  double? _v(int i, WxVar v) => hours[i].values[v];

  /// 该小时（中点）是否在日落后、日出前；来源没有日出日落时返回 null（不画夜色）。
  bool? _night(DateTime hourUtc) {
    final mid = hourUtc.add(const Duration(minutes: 30));
    DateTime? lastRise, lastSet;
    for (final s in point.dailySunrisesUtc) {
      if (!s.isAfter(mid)) lastRise = s;
    }
    for (final s in point.dailySunsetsUtc) {
      if (!s.isAfter(mid)) lastSet = s;
    }
    if (point.dailySunrisesUtc.isEmpty || point.dailySunsetsUtc.isEmpty) {
      return null;
    }
    if (lastSet == null) return lastRise == null;
    if (lastRise == null) return true;
    return lastSet.isAfter(lastRise);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = geom;
    final n = hours.length;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(0, 0, size.width * progress.value, size.height),
    );

    // ---- 夜色与选中列 ----
    final nightPaint = Paint()
      ..color = (dark ? Colors.black : Palette.night).withValues(
        alpha: dark ? 0.28 : 0.07,
      );
    for (var i = 0; i < n; i++) {
      if (_night(hours[i].validFromUtc) ?? false) {
        canvas.drawRect(
          Rect.fromLTWH(g.left(i), 0, g.colW + 0.5, _Geom.uvTop + _Geom.uvH),
          nightPaint,
        );
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(g.left(selected), 0, g.colW, _Geom.labelY - 2),
      Paint()..color = ink.withValues(alpha: 0.07),
    );

    // ---- 云层：高 / 中 / 低三行；没有分层时用总云量一行 ----
    final hasLayers = List.generate(
      n,
      (i) => _v(i, WxVar.cloudLow),
    ).any((x) => x != null);
    final cloudRows = hasLayers
        ? [WxVar.cloudHigh, WxVar.cloudMid, WxVar.cloudLow]
        : [WxVar.cloudCover];
    final cloudBase = dark ? const Color(0xFFCFD6DB) : const Color(0xFF6B7785);
    for (var r = 0; r < cloudRows.length; r++) {
      final y =
          _Geom.cloudTop +
          r * (_Geom.cloudRow + _Geom.cloudGap) +
          (hasLayers ? 0 : _Geom.cloudRow + _Geom.cloudGap);
      for (var i = 0; i < n; i++) {
        final c = _v(i, cloudRows[r]);
        if (c == null || c < 5) continue;
        canvas.drawRect(
          Rect.fromLTWH(g.left(i), y, g.colW + 0.5, _Geom.cloudRow),
          Paint()..color = cloudBase.withValues(alpha: 0.85 * c / 100),
        );
      }
    }
    _label(canvas, S.meteogramCloud, const Offset(0, 18), muted);

    // ---- 降水概率（列底色）与降水量（柱）----
    for (var i = 0; i < n; i++) {
      final p = _v(i, WxVar.precipProb);
      if (p != null && p >= 10) {
        canvas.drawRect(
          Rect.fromLTWH(
            g.left(i),
            _Geom.tempTop,
            g.colW + 0.5,
            _Geom.precipBottom - _Geom.tempTop,
          ),
          Paint()..color = Semantic.cold.withValues(alpha: 0.2 * p / 100),
        );
      }
    }
    var maxMm = 2.0;
    for (var i = 0; i < n; i++) {
      final mm = _v(i, WxVar.precip);
      if (mm != null) maxMm = math.max(maxMm, mm);
    }
    for (var i = 0; i < n; i++) {
      final mm = _v(i, WxVar.precip);
      if (mm == null || mm < 0.05) continue;
      final h =
          (_Geom.precipBottom - _Geom.precipTop) *
          (mm / maxMm).clamp(0.08, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            g.left(i) + g.colW * 0.18,
            _Geom.precipBottom - h,
            g.colW * 0.64,
            h,
          ),
          topLeft: const Radius.circular(1.5),
          topRight: const Radius.circular(1.5),
        ),
        Paint()..color = Semantic.cold,
      );
    }
    canvas.drawLine(
      Offset(_Geom.gutter, _Geom.precipBottom),
      Offset(size.width, _Geom.precipBottom),
      Paint()
        ..color = muted.withValues(alpha: 0.4)
        ..strokeWidth = 0.6,
    );

    // ---- 气温 / 体感 ----
    double? lo, hi;
    for (var i = 0; i < n; i++) {
      for (final v in [WxVar.temperature, WxVar.apparentTemp]) {
        final x = _v(i, v);
        if (x == null) continue;
        lo = lo == null ? x : math.min(lo, x);
        hi = hi == null ? x : math.max(hi, x);
      }
    }
    if (lo != null && hi != null) {
      final span = math.max(hi - lo, 4.0);
      final mid = (hi + lo) / 2;
      final top = mid + span / 2 + 0.5, bottom = mid - span / 2 - 0.5;
      double y(double t) =>
          _Geom.tempTop +
          8 +
          (top - t) / (top - bottom) * (_Geom.tempBottom - _Geom.tempTop - 12);
      if (bottom < 0 && top > 0) {
        final zy = y(0);
        _dashed(
          canvas,
          Offset(_Geom.gutter, zy),
          Offset(size.width, zy),
          Semantic.ice,
          0.8,
        );
        _label(canvas, '0°', Offset(0, zy + 4), Semantic.ice);
      }
      _series(
        canvas,
        WxVar.apparentTemp,
        y,
        Palette.sun.withValues(alpha: 0.55),
        dashed: true,
      );
      _series(canvas, WxVar.temperature, y, Palette.sun);
      // 最高 / 最低气温各标一次
      var hiI = -1, loI = -1;
      for (var i = 0; i < n; i++) {
        final t = _v(i, WxVar.temperature);
        if (t == null) continue;
        if (hiI < 0 || t > _v(hiI, WxVar.temperature)!) hiI = i;
        if (loI < 0 || t < _v(loI, WxVar.temperature)!) loI = i;
      }
      if (hiI >= 0) {
        final t = _v(hiI, WxVar.temperature)!;
        _label(
          canvas,
          Units.temp(t, imperial: imperial),
          Offset(g.x(hiI) - 10, y(t) - 4),
          ink,
          center: true,
        );
      }
      if (loI >= 0 && loI != hiI) {
        final t = _v(loI, WxVar.temperature)!;
        _label(
          canvas,
          Units.temp(t, imperial: imperial),
          Offset(g.x(loI) - 10, y(t) + 13),
          ink,
          center: true,
        );
      }
    }

    // ---- 风：箭头指向风的去向；颜色只按阵风 ----
    for (var i = 0; i < n; i++) {
      final dir = _v(i, WxVar.windDir);
      if (dir == null) continue;
      final gust = _v(i, WxVar.windGust);
      final color = gust == null
          ? muted.withValues(alpha: 0.6)
          : gust >= 17.2
          ? Semantic.danger
          : gust >= 13.9
          ? Semantic.caution
          : gust >= 10.8
          ? Semantic.caution.withValues(alpha: 0.7)
          : ink.withValues(alpha: 0.65);
      final len = gust == null ? 7.0 : (6 + gust * 0.4).clamp(6.0, 13.0);
      _arrow(
        canvas,
        Offset(g.x(i), _Geom.windY),
        (dir + 180) * math.pi / 180,
        len,
        color,
      );
    }

    // ---- 紫外线（中等起）----
    for (var i = 0; i < n; i++) {
      final uv = _v(i, WxVar.uvIndex);
      if (uv == null || uv < 3) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(g.left(i) + 1, _Geom.uvTop, g.colW - 2, _Geom.uvH),
          const Radius.circular(1.5),
        ),
        Paint()..color = _uvColor(uvLevelOf(uv)),
      );
    }

    // ---- 时间轴：每 3 小时一个刻度；跨日标日期；到达时刻画小三角 ----
    for (var i = 0; i < n; i++) {
      final t = hours[i].validFromUtc.toLocal();
      if (t.hour % 3 != 0) continue;
      final text = t.hour == 0 ? S.meteogramDay(t.day) : '${t.hour}';
      _label(
        canvas,
        text,
        Offset(g.x(i) - 8, _Geom.labelY + 11),
        muted,
        center: true,
      );
    }
    final ax = g.x(arrival);
    final tri = Path()
      ..moveTo(ax, _Geom.labelY - 1)
      ..lineTo(ax - 4, _Geom.labelY + 5)
      ..lineTo(ax + 4, _Geom.labelY + 5)
      ..close();
    canvas.drawPath(tri, Paint()..color = Palette.sun);
    canvas.drawLine(
      Offset(ax, _Geom.tempTop),
      Offset(ax, _Geom.precipBottom),
      Paint()
        ..color = Palette.sun.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  void _series(
    Canvas canvas,
    WxVar v,
    double Function(double) y,
    Color color, {
    bool dashed = false,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = dashed ? 1.4 : 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    Offset? prev;
    for (var i = 0; i < hours.length; i++) {
      final t = _v(i, v);
      if (t == null) {
        prev = null; // 缺失时断开，不连过去
        continue;
      }
      final p = Offset(geom.x(i), y(t));
      if (prev != null) {
        dashed
            ? _dashed(canvas, prev, p, color, 1.4)
            : canvas.drawLine(prev, p, paint);
      } else {
        canvas.drawCircle(p, dashed ? 0.7 : 1, paint);
      }
      prev = p;
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Color color, double w) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = w;
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final u = d / len;
    for (var s = 0.0; s < len; s += 6) {
      canvas.drawLine(a + u * s, a + u * math.min(s + 3, len), paint);
    }
  }

  void _arrow(Canvas canvas, Offset c, double angle, double len, Color color) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final p = Path()
      ..moveTo(0, -len / 2)
      ..lineTo(len * 0.32, len / 2)
      ..lineTo(0, len * 0.28)
      ..lineTo(-len * 0.32, len / 2)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
    canvas.restore();
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    bool center = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 9.5, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = center ? at.dx + 8 - tp.width / 2 : at.dx;
    tp.paint(canvas, Offset(dx, at.dy - tp.height));
  }

  @override
  bool shouldRepaint(covariant _MeteogramPainter old) =>
      old.hours != hours ||
      old.selected != selected ||
      old.arrival != arrival ||
      old.ink != ink ||
      old.dark != dark ||
      old.imperial != imperial;
}
