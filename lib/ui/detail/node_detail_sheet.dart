import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_providers.dart';
import '../../data/routes/route_sampling.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/weather_repository.dart';
import '../strings.dart';
import '../widgets/common.dart';
import 'detail_state.dart';
import 'weather_cells.dart';

/// 节点级多来源对比面板。
///
/// 原则：
/// - 每个来源独立展示，不默认平均、不拼成“一个天气”；
/// - 缺失值显示“此来源未提供”；
/// - 各来源实际命中的有效时刻可能不同，显示与请求时刻的差值提示；
/// - 未启用的来源不加载（按需请求）；
/// - 同服务商标注模型重叠说明。
class NodeComparePanel extends ConsumerStatefulWidget {
  const NodeComparePanel({
    super.key,
    required this.rows,
    required this.initialIndex,
    this.fixedUtc,
  });

  final List<NodeWxRow> rows;
  final int initialIndex;

  /// 固定时刻模式的请求时刻（行程模式用 rows[i].validUtc）。
  final DateTime? fixedUtc;

  @override
  ConsumerState<NodeComparePanel> createState() => _NodeComparePanelState();
}

class _NodeComparePanelState extends ConsumerState<NodeComparePanel> {
  late int _idx = widget.initialIndex.clamp(0, widget.rows.length - 1);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final providers = ref.watch(weatherProvidersProvider);
    final enabled = settings.enabledProviderIds;
    final row = widget.rows[_idx];
    final wantUtc = widget.fixedUtc ?? row.validUtc;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(S.nodeDetail, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _idx > 0 ? () => setState(() => _idx--) : null,
            ),
            Text('${_idx + 1}/${widget.rows.length}'),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _idx < widget.rows.length - 1
                  ? () => setState(() => _idx++)
                  : null,
            ),
          ],
        ),
        Text(
          '${row.node.label ?? '节点'} · ${S.distFromStart} ${(row.node.distFromStartM / 1000).toStringAsFixed(1)} km'
          '${row.node.elevationM == null ? '' : ' · ${S.elevationLabel} ${row.node.elevationM!.toStringAsFixed(0)} m'}',
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 2),
        Text(
          '${S.validTime}：${_fmt(wantUtc)} UTC（${_fmtLocal(wantUtc)} 本地）'
          '${widget.fixedUtc != null ? '' : '（行程模式：${S.eta}，估算）'}',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        GranularityNotice(text: S.timeAlignmentNote),
        const SizedBox(height: 8),
        for (final p in providers)
          if (enabled.contains(p.caps.providerId))
            _SourceNodeCard(
              providerId: p.caps.providerId,
              node: row.node,
              wantUtc: wantUtc,
              settings: settings,
            ),
      ],
    );
  }

  String _fmt(DateTime t) =>
      '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:00';
  String _fmtLocal(DateTime utc) {
    final t = utc.toLocal();
    return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

class _SourceNodeCard extends ConsumerStatefulWidget {
  const _SourceNodeCard({
    required this.providerId,
    required this.node,
    required this.wantUtc,
    required this.settings,
  });

  final String providerId;
  final RouteNode node;
  final DateTime wantUtc;
  final AppSettings settings;

  @override
  ConsumerState<_SourceNodeCard> createState() => _SourceNodeCardState();
}

/// 请求流保存在 State 中：仅当来源/节点/时刻变化才重新请求，
/// 避免每次重建（如切换节点、设置变化）都重复发起网络请求。
class _SourceNodeCardState extends ConsumerState<_SourceNodeCard> {
  /// 按次计费来源（caps.onDemandOnly）不自动请求：null 表示等待用户点击查询。
  late Stream<RouteWeatherBundle>? _stream = _onDemand ? null : _fetch();

  bool get _onDemand => ref
      .read(weatherProvidersProvider)
      .firstWhere((p) => p.caps.providerId == providerId)
      .caps
      .onDemandOnly;

  @override
  void didUpdateWidget(covariant _SourceNodeCard old) {
    super.didUpdateWidget(old);
    if (old.providerId != widget.providerId ||
        old.node.pos != widget.node.pos ||
        old.node.elevationM != widget.node.elevationM ||
        old.wantUtc != widget.wantUtc) {
      _stream = _onDemand ? null : _fetch();
    }
  }

  String get providerId => widget.providerId;
  RouteNode get node => widget.node;
  DateTime get wantUtc => widget.wantUtc;
  AppSettings get settings => widget.settings;

  Stream<RouteWeatherBundle> _fetch() {
    final repo = ref.read(weatherRepositoryProvider);
    return repo.watchRouteWeatherBundle(
      providerId: providerId,
      nodes: [node],
      startUtc: wantUtc.subtract(const Duration(hours: 6)),
      endUtc: wantUtc.add(const Duration(hours: 30)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref
        .watch(weatherProvidersProvider)
        .firstWhere((p) => p.caps.providerId == providerId)
        .caps;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: StreamBuilder<RouteWeatherBundle>(
          stream: _stream,
          builder: (context, snap) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    SourceBadge(caps: caps),
                    DataKindChip(kind: caps.dataKind),
                  ],
                ),
                const SizedBox(height: 8),
                if (_stream == null)
                  OnDemandQueryPrompt(
                    caps: caps,
                    onQuery: () => setState(() {
                      _stream = _fetch();
                    }),
                  )
                else if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (snap.hasError)
                  Text(
                    '该来源请求失败：${snap.error}',
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  )
                else if (snap.hasData)
                  ..._dataWidgets(context, snap.data!),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _dataWidgets(BuildContext context, RouteWeatherBundle bundle) {
    if (bundle.result.points.isEmpty) {
      return [const Text('该来源未返回此位置数据', style: TextStyle(fontSize: 12))];
    }
    final point = bundle.result.points.first;
    final nearest = _nearestHour(point, wantUtc);
    if (nearest == null) {
      return [
        Text(
          S.outOfRange,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '该来源的时间范围：${_range(point)}。${S.outOfRangeDetail}',
          style: const TextStyle(fontSize: 11, height: 1.4, color: Colors.grey),
        ),
      ];
    }
    final diffMin = nearest.validFromUtc.difference(wantUtc).inMinutes.abs();
    final prov = point.provenance;
    return [
      WeatherCacheNotice(result: bundle.result),
      if (diffMin > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '来源最近有效时次：${nearest.validFromUtc.toIso8601String().substring(5, 16)} UTC（与请求时刻相差 $diffMin 分钟）',
            style: const TextStyle(fontSize: 11, color: Colors.orange),
          ),
        ),
      WxVarGrid(wx: nearest, settings: settings),
      const SizedBox(height: 6),
      GranularityNotice(text: prov.granularityStatement()),
      const SizedBox(height: 4),
      Text(
        '${S.fetchedAt}：${prov.fetchedAtUtc.toIso8601String().substring(0, 16)} UTC'
        '${prov.modelRunUtc == null ? '' : ' · 起报 ${prov.modelRunUtc!.toIso8601String().substring(11, 16)} UTC'}'
        '${bundle.result.stale ? ' · ${S.staleData}' : ''}',
        style: const TextStyle(fontSize: 10, color: Colors.grey),
      ),
    ];
  }

  String _range(WxPointForecast p) {
    final f = p.firstValidUtc;
    final l = p.lastValidUtc;
    if (f == null || l == null) return '未返回时间序列';
    return '${f.toIso8601String().substring(5, 16)} → ${l.toIso8601String().substring(5, 16)} UTC';
  }

  WxHourValue? _nearestHour(WxPointForecast p, DateTime utc) {
    if (p.hours.isEmpty) return null;
    WxHourValue? best;
    var bestDiff = 1 << 30;
    for (final h in p.hours) {
      final d = h.validFromUtc.difference(utc).inMinutes.abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = h;
      }
    }
    if (bestDiff > 180) return null; // 相差超过 3 小时视为无对齐数据
    return best;
  }
}
