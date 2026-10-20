import 'package:flutter/material.dart';

import '../../core/units.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/departure_windows.dart';
import '../../data/weather/risk_rules.dart';
import '../../data/weather/layering.dart';
import '../detail/detail_state.dart';
import '../detail/ridge_band.dart' show RidgeBandGraphic;
import '../detail/layering_card.dart' show LayerFigurePainter;
import '../../data/weather/node_wx_class.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/weather_phenomena.dart';
import '../detail/node_wx_style.dart';
import 'share_graphics.dart';
import 'share_image.dart';
import '../tokens.dart';
import '../strings.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// 降水时段的结束小时：最后一个有雨小时的起点 + 1 小时，午夜写作 24。
String _endHour(DateTime lastWetStartUtc) {
  final h = lastWetStartUtc.toLocal().add(const Duration(hours: 1)).hour;
  return _two(h == 0 ? 24 : h);
}

String _hhmm(DateTime utc) {
  final l = utc.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

String _stamp(DateTime utc) {
  final l = utc.toLocal();
  return '${l.month}/${l.day} ${_two(l.hour)}:${_two(l.minute)}';
}

/// 节点在分享图上的一行天气：气温 · 降水 · 阵风（缺失项省略，不显示成 0）。
String shareNodeWeather(NodeWxRow r, AppSettings settings) {
  final v = r.wx?.values;
  if (v == null) return S.shareNodeNoData;
  final parts = <String>[
    if (v[WxVar.temperature] != null)
      Units.temp(v[WxVar.temperature]!, imperial: settings.imperial),
    if ((v[WxVar.precip] ?? 0) >= 0.1)
      Units.precipMm(v[WxVar.precip]!, imperial: settings.imperial),
    if (v[WxVar.windGust] != null)
      S.shareNodeGust(
        Units.windMs(v[WxVar.windGust]!, unit: settings.windUnit),
      ),
  ];
  final phen = phenomenonOf(r.wx);
  if (phen != null) parts.insert(0, phen.label);
  return parts.isEmpty ? S.shareNodeIncomplete : parts.join(' · ');
}

/// 线路天气分享卡（分层：标题 → 三个大数字 → 醒目提示 → 线路示意 + 山脊天气带 → 关键节点）。
/// 线路分享图版式（D-034）：信息侧重不同，来源与免责说明在每种版式里都保留。
enum ShareLayout {
  /// 长图：数字、提示、示意图与剖面、关键节点逐条说明。
  full(S.shareLayoutFull, Icons.view_agenda_outlined),

  /// 简图：数字、提示与着色剖面，适合群聊与朋友圈一眼看完。
  brief(S.shareLayoutBrief, Icons.crop_portrait),

  /// 横图（约 16:9）：左侧线路示意，右侧数字、提示与剖面，适合 X / Threads / 微博。
  wide(S.shareLayoutWide, Icons.crop_landscape);

  const ShareLayout(this.label, this.icon);
  final String label;
  final IconData icon;
}

class RouteShareCard extends StatelessWidget {
  const RouteShareCard({
    super.key,
    required this.route,
    required this.tripMode,
    required this.reversed,
    required this.summary,
    required this.dayPrecip,
    required this.hints,
    required this.rows,
    required this.settings,
    required this.sourceName,
    required this.fetchedAtUtc,
    this.layout = ShareLayout.full,
    this.sunriseUtc,
    this.sunsetUtc,
  });

  final ShareLayout layout;

  /// 出发日日出、日落（行程模式且来源提供时），用于穿衣建议里的头灯判断。
  final DateTime? sunriseUtc;
  final DateTime? sunsetUtc;
  final HikingRoute route;
  final bool tripMode;
  final bool reversed;
  final RouteWxSummary summary;

  /// 固定时刻模式的全天降水（行程模式为 null，用行程降水）。
  final DayPrecipSummary? dayPrecip;
  final List<WxHint> hints;
  final List<NodeWxRow> rows;
  final AppSettings settings;
  final String sourceName;
  final DateTime fetchedAtUtc;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final ascent = route.totalAscentM;
    final keys = pickKeyNodes(rows);
    String temp(double c) => Units.temp(c, imperial: settings.imperial);
    final tempRange = summary.minTempC == null || summary.maxTempC == null
        ? S.shareNotProvided
        : '${temp(summary.minTempC!)}~${temp(summary.maxTempC!)}';
    final day = dayPrecip;
    final (precipLabel, precipValue, precipSub) = day != null
        ? (
            S.shareDayPrecip,
            day.maxDayMm == null
                ? S.shareNotProvided
                : Units.precipMm(day.maxDayMm!, imperial: settings.imperial),
            day.firstWetUtc == null
                ? S.shareNoNotablePrecip
                : S.shareWetHours(
                    _two(day.firstWetUtc!.toLocal().hour),
                    _endHour(day.lastWetUtc!),
                  ),
          )
        : (
            tripMode ? S.shareTripPrecip : S.shareHourPrecip,
            summary.totalPrecipMm == null
                ? S.shareNotProvided
                : Units.precipMm(
                    summary.totalPrecipMm!,
                    imperial: settings.imperial,
                  ),
            null,
          );
    final sorted = [...hints]
      ..sort((a, b) => b.level.index.compareTo(a.level.index));

    final Widget stats = Row(
      children: [
        _stat(context, Icons.thermostat, S.shareTemp, tempRange, null),
        _stat(
          context,
          Icons.air,
          S.shareMaxGust,
          summary.maxGustMs == null
              ? S.shareNotProvided
              : Units.windMs(summary.maxGustMs!, unit: settings.windUnit),
          null,
        ),
        _stat(context, Icons.water_drop, precipLabel, precipValue, precipSub),
      ],
    );
    final Widget hintsView = sorted.isEmpty
        ? _pill(Icons.info_outline, S.shareNoHints, Semantic.unknown)
        : Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final h in sorted.take(4))
                _pill(hintIcon(h), h.title, hintColor(h)),
            ],
          );
    final sketch = RouteSketch(
      route: route,
      rows: rows,
      keyNodes: keys,
      height: layout == ShareLayout.wide ? 260 : 200,
    );
    // 山脊天气带（与详情页同一套视觉）：行程模式且日落已知时铺出日落后的路段。
    final sunset = sunsetUtc;
    final nightFrom = tripMode && sunset != null
        ? rows.indexWhere((r) => r.validUtc.isAfter(sunset))
        : -1;
    final profile = ascent == null
        ? null
        : RidgeBandGraphic(
            route: route,
            rows: rows,
            keyNodes: keys,
            // 行程模式：编号下标到达时刻，一眼看出“几点走到哪”。
            keyLabels: tripMode
                ? [for (final i in keys) _hhmm(rows[i].validUtc)]
                : null,
            nightFromIndex: nightFrom < 0 ? null : nightFrom,
          );
    final Widget keyList = Column(
      children: [
        for (final (n, i) in keys.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                // 连续编号，与示意图、剖面上的徽章一致。
                _numberBadge(n + 1, nodeWxColor(classifyNodeWx(rows[i].wx))),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${tripMode ? '${_hhmm(rows[i].validUtc)}  ' : ''}'
                        '${rows[i].node.label ?? S.shareNodeAtKm((rows[i].node.distFromStartM / 1000).toStringAsFixed(1))}'
                        '${rows[i].node.elevationM == null ? '' : ' · ${rows[i].node.elevationM!.toStringAsFixed(0)} m'}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        shareNodeWeather(rows[i], settings),
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
                Icon(
                  nodeWxIcon(classifyNodeWx(rows[i].wx)),
                  size: 18,
                  color: nodeWxColor(classifyNodeWx(rows[i].wx)),
                ),
              ],
            ),
          ),
      ],
    );

    final plan = planLayers(
      entries: rowsToEntries(rows),
      sunriseUtc: sunriseUtc,
      sunsetUtc: sunsetUtc,
      coldSensitivity: settings.coldSensitivity,
    );
    final banner = _modeBanner(scheme);
    final body = switch (layout) {
      ShareLayout.full => [
        banner,
        stats,
        hintsView,
        ?(plan == null ? null : _gearRow(plan, muted)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [sketch, const SizedBox(height: 6), ?profile],
        ),
        keyList,
      ],
      // 简图：结论 + 着色剖面；没有海拔时用示意图代替剖面。
      ShareLayout.brief => [banner, stats, hintsView, profile ?? sketch],
      // 横图：三栏（示意图与穿衣 | 数字、提示与山脊天气带 | 关键节点），
      // 信息量与长图接近，在手机上横向看也不是一条细长的窄图。
      ShareLayout.wide => [
        banner,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 250,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  sketch,
                  if (plan != null) ...[
                    const SizedBox(height: 12),
                    _gearRow(plan, muted),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 290,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  stats,
                  const SizedBox(height: 12),
                  hintsView,
                  if (profile != null) ...[const SizedBox(height: 12), profile],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: keyList),
          ],
        ),
      ],
    };

    return ShareCardFrame(
      title: route.name,
      width: layout == ShareLayout.wide ? 820 : 360,
      subtitle: [
        '${(route.totalDistanceM / 1000).toStringAsFixed(1)} km',
        if (ascent != null) '↑${ascent.toStringAsFixed(0)} m',
        if (reversed) S.shareReversed,
        if (route.isDemo && !route.name.contains('示例')) S.shareDemoRoute,
      ].join(' · '),
      body: body,
      footer: [
        S.shareSourceLine(sourceName, _stamp(fetchedAtUtc)),
        S.shareRouteDisclaimer(tripMode: tripMode),
      ],
    );
  }

  /// 时间模式横幅：固定时刻与行程模式对天气判断的含义不同，放在最显眼处，
  /// 避免把“全线同一小时的快照”当成按出发时间推算的行程。
  Widget _modeBanner(ColorScheme scheme) {
    final first = rows.isEmpty ? null : rows.first.validUtc;
    final last = rows.isEmpty ? null : rows.last.validUtc;
    final sunset = sunsetUtc;
    final (icon, title, note) = tripMode
        ? (
            Icons.hiking,
            first == null
                ? S.shareModeTrip
                : S.shareModeTripTitle(_stamp(first), _hhmm(last!)),
            S.shareModeTripNote(sunset == null ? null : _hhmm(sunset)),
          )
        : (
            Icons.schedule,
            first == null
                ? S.shareModeFixed
                : S.shareModeFixedTitle(_stamp(first)),
            S.shareModeFixedNote,
          );
    final color = tripMode ? scheme.primary : SemanticInk.cautionOnLight;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  note,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 穿衣一行（长图）：出发时穿着的、背包里备着的、配件；左侧小人形与 App 内一致。
  Widget _gearRow(LayerPlan plan, Color muted) {
    final worn = [
      for (final l in plan.layers)
        if (l.wear[LayerScene.start] == Wear.worn) l.name,
    ];
    final packed = [
      for (final l in plan.layers)
        if (l.wear[LayerScene.start] == Wear.packed) l.name,
    ];
    final wet = plan.layer(LayerKind.shell)?.name == '防水硬壳';
    double st(LayerKind k) => switch (plan.layer(k)?.wear[LayerScene.start]) {
      Wear.worn => 1.0,
      Wear.packed => 0.5,
      _ => 0.0,
    };
    Widget line(String head, List<String> items) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$head  ',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          TextSpan(text: items.join(' · ')),
        ],
      ),
      style: const TextStyle(fontSize: 12.5, height: 1.45),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          height: 50,
          child: CustomPaint(
            painter: LayerFigurePainter(
              states: [
                st(LayerKind.base),
                st(LayerKind.mid),
                st(LayerKind.shell),
              ],
              shellColor: wet ? Semantic.route : const Color(0xFF5B6B78),
              outline: const Color(0xFF121915),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (worn.isNotEmpty) line(S.shareGearWorn, worn),
              if (packed.isNotEmpty) line(S.shareGearPacked, packed),
              if (plan.accessories.isNotEmpty)
                line(S.shareGearAccessories, [
                  for (final a in plan.accessories) accessoryLabel(a.item),
                ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stat(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    String? sub,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      // 右侧留白：横图窄栏里数值缩小后也不会挤在一起。
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: scheme.primary),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            // 窄栏（横图）与大字号下等比缩小，不截断数值。
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (sub != null)
              Text(
                sub,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _numberBadge(int n, Color color) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Text(
      '$n',
      style: const TextStyle(
        fontSize: 11,
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// 出发窗口分享卡中的一个格子。
class DepartureShareCell {
  const DepartureShareCell.past()
    : glyph = S.shareGlyphPast,
      level = null,
      insufficient = false,
      past = true;
  const DepartureShareCell.missing()
    : glyph = S.shareGlyphMissing,
      level = null,
      insufficient = true,
      past = false;
  const DepartureShareCell(this.glyph, this.level, this.insufficient)
    : past = false;

  final String glyph;
  final DepartureLevel? level;
  final bool insufficient;
  final bool past;

  bool get clear => !past && level == DepartureLevel.none && !insufficient;
}

/// 多日出发窗口对比分享卡：日期 × 出发时刻格子 + 图例 + 最早无阈值时刻。
class DepartureShareCard extends StatelessWidget {
  const DepartureShareCard({
    super.key,
    required this.routeName,
    required this.isDemo,
    required this.reversed,
    required this.durationHours,
    required this.dayLabels,
    required this.dates,
    required this.slotLabels,
    required this.cells,
    required this.startsUtc,
    required this.sourceName,
    required this.fetchedAtUtc,
    required this.thresholdText,
  });

  final String routeName;
  final bool isDemo;
  final bool reversed;
  final double durationHours;
  final List<String> dayLabels;
  final List<DateTime> dates;
  final List<String> slotLabels;

  /// cells[日][时刻]。
  final List<List<DepartureShareCell>> cells;

  /// startsUtc[日][时刻]：出发时刻（UTC）。
  final List<List<DateTime>> startsUtc;
  final String sourceName;
  final DateTime fetchedAtUtc;
  final String thresholdText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    (Color, Color) colors(DepartureShareCell c) {
      if (c.past) {
        return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
      }
      return switch (c.level) {
        DepartureLevel.red => (scheme.errorContainer, scheme.onErrorContainer),
        DepartureLevel.yellow => (
          Semantic.cautionContainerLight,
          SemanticInk.cautionOnLight,
        ),
        _ =>
          c.insufficient
              ? (scheme.surfaceContainerHighest, scheme.onSurface)
              : (scheme.primaryContainer, scheme.onPrimaryContainer),
      };
    }

    DateTime? best;
    for (var d = 0; d < cells.length && best == null; d++) {
      for (var s = 0; s < cells[d].length; s++) {
        if (cells[d][s].clear) {
          best = startsUtc[d][s];
          break;
        }
      }
    }
    return ShareCardFrame(
      title: '$routeName${isDemo ? S.shareDemoSuffix : ''}',
      subtitle: S.shareDepartureSubtitle(
        reversed: reversed,
        hours: durationHours.toStringAsFixed(1),
      ),
      body: [
        Table(
          defaultColumnWidth: const FixedColumnWidth(52),
          columnWidths: const {0: FixedColumnWidth(56)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                for (final s in slotLabels)
                  Text(
                    s,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            for (var d = 0; d < cells.length; d++)
              TableRow(
                children: [
                  Text(dayLabels[d], style: const TextStyle(fontSize: 11)),
                  for (final c in cells[d])
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: Container(
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors(c).$1,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          c.glyph,
                          style: TextStyle(color: colors(c).$2, fontSize: 13),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          S.shareDepartureLegend,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Text(
          best == null
              ? S.shareNoClearDeparture
              : S.shareEarliestClear(_stamp(best)),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
      footer: [
        S.shareSourceLine(sourceName, _stamp(fetchedAtUtc)),
        thresholdText,
        S.shareDepartureDisclaimer,
      ],
    );
  }
}
