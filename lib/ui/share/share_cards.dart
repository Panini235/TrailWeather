import 'package:flutter/material.dart';

import '../../core/units.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/departure_windows.dart';
import '../../data/weather/risk_rules.dart';
import '../detail/detail_state.dart';
import '../../data/weather/node_wx_class.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/weather_phenomena.dart';
import '../detail/node_wx_style.dart';
import 'share_graphics.dart';
import 'share_image.dart';
import '../tokens.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// 降水时段的结束小时：最后一个有雨小时的起点 + 1 小时，午夜写作 24。
String _endHour(DateTime lastWetStartUtc) {
  final h = lastWetStartUtc.toLocal().add(const Duration(hours: 1)).hour;
  return _two(h == 0 ? 24 : h);
}

String _stamp(DateTime utc) {
  final l = utc.toLocal();
  return '${l.month}/${l.day} ${_two(l.hour)}:${_two(l.minute)}';
}

/// 节点在分享图上的一行天气：气温 · 降水 · 阵风（缺失项省略，不显示成 0）。
String shareNodeWeather(NodeWxRow r, AppSettings settings) {
  final v = r.wx?.values;
  if (v == null) return '此来源无该时刻数据';
  final parts = <String>[
    if (v[WxVar.temperature] != null)
      Units.temp(v[WxVar.temperature]!, imperial: settings.imperial),
    if ((v[WxVar.precip] ?? 0) >= 0.1)
      Units.precipMm(v[WxVar.precip]!, imperial: settings.imperial),
    if (v[WxVar.windGust] != null)
      '阵风 ${Units.windMs(v[WxVar.windGust]!, unit: settings.windUnit)}',
  ];
  final phen = phenomenonOf(r.wx);
  if (phen != null) parts.insert(0, phen.label);
  return parts.isEmpty ? '数据不完整' : parts.join(' · ');
}

/// 线路天气分享卡（分层：标题 → 三个大数字 → 醒目提示 → 线路示意 + 海拔剖面 → 关键节点）。
class RouteShareCard extends StatelessWidget {
  const RouteShareCard({
    super.key,
    required this.route,
    required this.timeLabel,
    required this.tripMode,
    required this.reversed,
    required this.summary,
    required this.dayPrecip,
    required this.hints,
    required this.rows,
    required this.settings,
    required this.sourceName,
    required this.fetchedAtUtc,
  });

  final HikingRoute route;
  final String timeLabel;
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
        ? '未提供'
        : '${temp(summary.minTempC!)}~${temp(summary.maxTempC!)}';
    final day = dayPrecip;
    final (precipLabel, precipValue, precipSub) = day != null
        ? (
            '全天降水',
            day.maxDayMm == null
                ? '未提供'
                : Units.precipMm(day.maxDayMm!, imperial: settings.imperial),
            day.firstWetUtc == null
                ? '无明显降水'
                : '${_two(day.firstWetUtc!.toLocal().hour)}–${_endHour(day.lastWetUtc!)} 时',
          )
        : (
            tripMode ? '行程降水' : '该时次降水',
            summary.totalPrecipMm == null
                ? '未提供'
                : Units.precipMm(
                    summary.totalPrecipMm!,
                    imperial: settings.imperial,
                  ),
            null,
          );
    final sorted = [...hints]
      ..sort((a, b) => b.level.index.compareTo(a.level.index));

    return ShareCardFrame(
      title: route.name,
      subtitle: [
        timeLabel,
        '${(route.totalDistanceM / 1000).toStringAsFixed(1)} km',
        if (ascent != null) '↑${ascent.toStringAsFixed(0)} m',
        if (reversed) '反向',
        if (route.isDemo && !route.name.contains('示例')) '演示线路',
      ].join(' · '),
      body: [
        // ① 三个大数字
        Row(
          children: [
            _stat(context, Icons.thermostat, '气温', tempRange, null),
            _stat(
              context,
              Icons.air,
              '最大阵风',
              summary.maxGustMs == null
                  ? '未提供'
                  : Units.windMs(summary.maxGustMs!, unit: settings.windUnit),
              null,
            ),
            _stat(
              context,
              Icons.water_drop,
              precipLabel,
              precipValue,
              precipSub,
            ),
          ],
        ),
        // ② 醒目提示（图标 + 颜色）
        if (sorted.isEmpty)
          _pill(
            Icons.check_circle_outline,
            '未触发阈值提示（不代表安全）',
            SemanticInk.goOnLight,
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final h in sorted.take(4))
                _pill(hintIcon(h), h.title, hintColor(h)),
            ],
          ),
        // ③ 线路示意 + 海拔剖面
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RouteSketch(route: route, rows: rows, keyNodes: keys),
            const SizedBox(height: 6),
            if (ascent != null)
              ShareElevationProfile(route: route, rows: rows, keyNodes: keys),
          ],
        ),
        // ④ 关键节点（编号与示意图一致）
        Column(
          children: [
            for (final i in keys)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    _numberBadge(
                      i + 1,
                      nodeWxColor(classifyNodeWx(rows[i].wx)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${tripMode ? '${_two(rows[i].validUtc.toLocal().hour)}:${_two(rows[i].validUtc.toLocal().minute)}  ' : ''}'
                            '${rows[i].node.label ?? '节点 ${i + 1}'}'
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
        ),
      ],
      footer: [
        '数据：$sourceName · 获取于 ${_stamp(fetchedAtUtc)}（设备时区）',
        '预报非实测；提示按阈值计算，非官方预警、非安全评分${tripMode ? '；到达时间为配速估算' : ''}。示意图不含地图。',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: scheme.primary),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (sub != null)
            Text(
              sub,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
        ],
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
    : glyph = '过',
      level = null,
      insufficient = false,
      past = true;
  const DepartureShareCell.missing()
    : glyph = '缺',
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
      title: '$routeName${isDemo ? '（演示）' : ''}',
      subtitle:
          '出发窗口对比 · ${reversed ? '反向' : '正向'} · 全程约 ${durationHours.toStringAsFixed(1)} 小时（估算）',
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
          '✓ 未触发　风 阵风　雨 降水　冷 低温　晚 晚于日落　缺 信息不足　过 已过去',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Text(
          best == null
              ? '所列时段内没有“未触发阈值且信息完整”的出发时刻。'
              : '最早未触发阈值的出发：${_stamp(best)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
      footer: [
        '数据：$sourceName · 获取于 ${_stamp(fetchedAtUtc)}（设备时区）',
        thresholdText,
        '颜色只表示阈值结果，非安全评分；预报非实测，官方预警与日出未接入。',
      ],
    );
  }
}
