import 'package:flutter/material.dart';

import '../../core/units.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/departure_windows.dart';
import '../../data/weather/risk_rules.dart';
import '../detail/detail_state.dart';
import '../detail/weather_cells.dart';
import 'share_image.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _stamp(DateTime utc) {
  final l = utc.toLocal();
  return '${l.month}/${l.day} ${_two(l.hour)}:${_two(l.minute)}';
}

/// 分享图上最多列出的节点数（多了按距离均匀抽取，并注明）。
const int shareMaxNodes = 12;

/// 均匀抽取至多 [max] 个下标，保留首尾。
List<int> sampleShareIndices(int count, {int max = shareMaxNodes}) {
  if (count <= max) return [for (var i = 0; i < count; i++) i];
  return {for (var k = 0; k < max; k++) ((count - 1) * k / (max - 1)).round()}
      .toList();
}

/// 线路天气分享卡：时间、摘要、全天降水、提示、沿途节点。
class RouteShareCard extends StatelessWidget {
  const RouteShareCard({
    super.key,
    required this.route,
    required this.timeLabel,
    required this.tripMode,
    required this.reversed,
    required this.summary,
    required this.dayLine,
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
  final String? dayLine;
  final List<WxHint> hints;
  final List<NodeWxRow> rows;
  final AppSettings settings;
  final String sourceName;
  final DateTime fetchedAtUtc;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final ascent = route.totalAscentM;
    final pick = sampleShareIndices(rows.length);
    String temp(double? c) =>
        c == null ? '未提供' : Units.temp(c, imperial: settings.imperial);
    Widget kv(String k, String v) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: TextStyle(fontSize: 11, color: muted)),
          Text(
            v,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return ShareCardFrame(
      // 名称已含“示例”时不再重复加“（演示）”。
      title:
          '${route.name}${route.isDemo && !route.name.contains('示例') ? '（演示）' : ''}',
      subtitle: [
        '${(route.totalDistanceM / 1000).toStringAsFixed(1)} km',
        if (ascent != null) '↑${ascent.toStringAsFixed(0)} m',
        timeLabel,
        if (reversed) '反向行走',
      ].join(' · '),
      body: [
        Row(
          children: [
            kv(
              '最低/最高温',
              '${temp(summary.minTempC)} / ${temp(summary.maxTempC)}',
            ),
            kv(
              '最大阵风',
              summary.maxGustMs == null
                  ? '未提供'
                  : Units.windMs(summary.maxGustMs!, unit: settings.windUnit),
            ),
            kv(
              tripMode ? '行程降水' : '该时次降水',
              summary.totalPrecipMm == null
                  ? '未提供'
                  : Units.precipMm(
                      summary.totalPrecipMm!,
                      imperial: settings.imperial,
                    ),
            ),
          ],
        ),
        if (dayLine != null) ...[const SizedBox(height: 6), Text(dayLine!)],
        const SizedBox(height: 6),
        Text(
          hints.isEmpty
              ? '未触发阈值提示（不代表安全）'
              : '提示：${hints.map((h) => h.title).join('、')}',
          style: TextStyle(
            fontSize: 12,
            color: hints.any((h) => h.level == HintLevel.warning)
                ? Colors.red.shade700
                : null,
          ),
        ),
        const SizedBox(height: 10),
        for (final i in pick)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 112,
                  child: Text(
                    '${tripMode ? '${_two(rows[i].validUtc.toLocal().hour)}:${_two(rows[i].validUtc.toLocal().minute)} ' : ''}'
                    '${rows[i].node.label ?? '节点 ${i + 1}'}'
                    '${rows[i].node.elevationM == null ? '' : ' ${rows[i].node.elevationM!.toStringAsFixed(0)} m'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: WxBriefLine(wx: rows[i].wx, settings: settings),
                ),
              ],
            ),
          ),
        if (pick.length < rows.length)
          Text(
            '共 ${rows.length} 个节点，图中按距离均匀列出 ${pick.length} 个',
            style: TextStyle(fontSize: 11, color: muted),
          ),
      ],
      footer: [
        '数据：$sourceName · 获取于 ${_stamp(fetchedAtUtc)}（设备时区）',
        '预报非实测；提示按阈值计算，非官方预警、非安全评分。${tripMode ? '到达时间为配速估算。' : ''}',
        if (route.isDemo) '演示线路，仅供体验。',
      ],
    );
  }
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
          const Color(0xFFFFE7A0),
          const Color(0xFF493400),
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
