import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/units.dart';
import '../../data/app_providers.dart';
import '../../data/routes/route_models.dart';
import '../../data/routes/route_sampling.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/eta.dart';
import '../../data/weather/risk_rules.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/weather_provider.dart';
import '../../data/weather/weather_repository.dart';
import '../strings.dart';
import '../widgets/common.dart';
import '../map/basemap.dart';
import 'detail_state.dart';
import 'elevation_profile.dart';
import 'node_detail_sheet.dart';
import 'weather_cells.dart';

class RouteDetailArgs {
  const RouteDetailArgs({required this.route});
  final HikingRoute route;
}

/// 详情页天气数据提供者：参数为（节点序列, 查询）。
/// 必须实现 ==：family 依赖键相等判断，避免每帧重建触发重复请求。
class DetailFetchKey {
  const DetailFetchKey({required this.nodes, required this.query});
  final List<RouteNode> nodes;
  final RouteWeatherQuery query;

  String _nodesSig() => nodes.isEmpty
      ? '0'
      : '${nodes.length}:${nodes.first.distFromStartM.toStringAsFixed(1)}:'
            '${nodes.last.distFromStartM.toStringAsFixed(1)}';

  @override
  bool operator ==(Object other) =>
      other is DetailFetchKey &&
      other.query == query &&
      other._nodesSig() == _nodesSig();

  @override
  int get hashCode => Object.hash(query, _nodesSig());
}

final detailWeatherProvider = FutureProvider.autoDispose
    .family<RouteWeatherBundle, DetailFetchKey>((ref, key) async {
      final repo = ref.watch(weatherRepositoryProvider);
      return repo.getRouteWeatherBundle(
        providerId: key.query.providerId,
        nodes: key.nodes,
        startUtc: key.query.startUtc,
        endUtc: key.query.endUtc,
      );
    });

class RouteDetailScreen extends ConsumerStatefulWidget {
  const RouteDetailScreen({super.key, required this.args});

  final RouteDetailArgs args;

  @override
  ConsumerState<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends ConsumerState<RouteDetailScreen> {
  TimeMode _mode = TimeMode.fixed;
  // 固定时刻默认：上午 10 点前为当天 10:00，之后为下一个整点（避免默认落在已过去的时刻）。
  late DateTime _date = _defaultFixedLocal();
  late int _hour = _date.hour;
  TimeOfDay _startTime = const TimeOfDay(hour: 7, minute: 0);
  PaceConfig _pace = PaceConfig.defaults;
  late String _providerId;
  int? _selectedNode;
  double? _previewHour; // 滑块拖动中的预览（不触发请求）

  @override
  void initState() {
    super.initState();
    final enabled = ref.read(settingsProvider).enabledProviderIds;
    final providers = ref.read(weatherProvidersProvider);
    _providerId = enabled.firstWhere(
      (e) => providers.any((p) => p.caps.providerId == e),
      orElse: () => providers.first.caps.providerId,
    );
  }

  static DateTime _defaultFixedLocal() {
    final now = DateTime.now();
    if (now.hour < 10) return DateTime(now.year, now.month, now.day, 10);
    return DateTime(now.year, now.month, now.day, now.hour + 1); // 23 点会进位到次日
  }

  (DateTime, DateTime) _utcWindow(List<RouteNode> nodes, List<DateTime> etas) {
    if (_mode == TimeMode.fixed) {
      final f = _fixedUtc();
      return (f, f.add(const Duration(hours: 1)));
    }
    final start = _tripStartUtc();
    final end = (etas.isEmpty ? start : etas.last).add(
      const Duration(hours: 1),
    );
    return (start, end.isBefore(start) ? start : end);
  }

  DateTime _fixedUtc() {
    // 滑块拖动期间仅更新 _previewHour（不触发查询），松手才提交 _hour。
    return DateTime(_date.year, _date.month, _date.day, _hour).toUtc();
  }

  DateTime _tripStartUtc() => DateTime(
    _date.year,
    _date.month,
    _date.day,
    _startTime.hour,
    _startTime.minute,
  ).toUtc();

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final route = widget.args.route;
    final nodes = nodesForRoute(
      route,
      spacingKm: settings.effectiveSamplingSpacingKm,
      maxNodes: settings.effectiveMaxNodes,
    );
    final etas = _mode == TimeMode.trip
        ? computeEtas(nodes: nodes, startUtc: _tripStartUtc(), pace: _pace)
        : List<DateTime>.generate(nodes.length, (_) => _fixedUtc());
    final (startUtc, endUtc) = _utcWindow(nodes, etas);
    final query = RouteWeatherQuery(
      routeId: route.id,
      providerId: _providerId,
      mode: _mode,
      startUtc: startUtc,
      endUtc: endUtc,
      fixedUtc: _mode == TimeMode.fixed ? _fixedUtc() : _tripStartUtc(),
      pace: _pace,
    );
    final bundleAsync = ref.watch(
      detailWeatherProvider(DetailFetchKey(nodes: nodes, query: query)),
    );

    final rows = buildNodeRows(
      nodes: nodes,
      bundle: bundleAsync.value,
      mode: _mode,
      fixedUtc: query.fixedUtc,
      etas: etas,
    );

    return Scaffold(
      appBar: AppBar(
        title: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(route.name, style: const TextStyle(fontSize: 16)),
            if (route.isDemo) const DemoBadge(),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            tooltip: '离线气象与轨迹包（开发中）',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('离线气象与轨迹包（开发中）'),
                content: const Text(
                  '该功能尚未上线：当前不会下载或缓存任何离线数据，'
                  '无信号时请勿依赖本 App 获取天气。\n\n'
                  '已查看过的天气会按来源有效期短暂缓存，过期后会标注“旧数据”。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(S.close),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              ref.watch(favoritesProvider).any((r) => r.id == route.id)
                  ? Icons.star
                  : Icons.star_border,
            ),
            tooltip: S.favorites,
            onPressed: () => ref.read(favoritesProvider.notifier).toggle(route),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          _RouteMiniMap(route: route, rows: rows, selectedIndex: _selectedNode),
          const SizedBox(height: 8),
          _RouteFactsCard(route: route),
          const SizedBox(height: 8),
          _TimeControlsCard(
            mode: _mode,
            onMode: (m) => setState(() => _mode = m),
            date: _date,
            onDate: (d) => setState(() => _date = d),
            hour: _hour,
            previewHour: _previewHour,
            onHourPreview: (h) => setState(() => _previewHour = h),
            onHourCommit: (h) => setState(() {
              _hour = h;
              _previewHour = null;
            }),
            startTime: _startTime,
            onStartTime: (t) => setState(() => _startTime = t),
            pace: _pace,
            onPace: (p) => setState(() => _pace = p),
          ),
          const SizedBox(height: 8),
          _SourceChips(
            selected: _providerId,
            onSelect: (id) => setState(() => _providerId = id),
            onCompare: () => _showNodeSheet(rows, settings),
          ),
          const SizedBox(height: 8),
          ..._weatherSection(
            bundleAsync,
            rows,
            settings,
            nodes,
            etas,
            route,
            query,
          ),
        ],
      ),
    );
  }

  List<Widget> _weatherSection(
    AsyncValue<RouteWeatherBundle> bundleAsync,
    List<NodeWxRow> rows,
    AppSettings settings,
    List<RouteNode> nodes,
    List<DateTime> etas,
    HikingRoute route,
    RouteWeatherQuery query,
  ) {
    final provider = ref
        .read(weatherProvidersProvider)
        .where((p) => p.caps.providerId == _providerId)
        .first;
    if (bundleAsync.isLoading && !bundleAsync.hasValue) {
      return const [
        Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
      ];
    }
    if (bundleAsync.hasError) {
      final err = bundleAsync.error;
      if (err is WxOutOfRange) {
        return [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event_busy, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        S.outOfRange,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    S.outOfRangeDetail,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ];
      }
      return [
        ErrorCard(
          title: '来源请求失败（${provider.caps.displayName}）',
          detail: '${err.toString()}\n数据未获取，以下显示为空，不会用历史值冒充。',
          onRetry: () => ref.invalidate(
            detailWeatherProvider(DetailFetchKey(nodes: nodes, query: query)),
          ),
        ),
      ];
    }

    final bundle = bundleAsync.value;
    final summary = summarizeRows(rows);
    // 日落提示只在行程模式有意义：取出发后的第一次日落（不是“今天”的日落）。
    final tripMode = _mode == TimeMode.trip && etas.isNotEmpty;
    final sunset = tripMode
        ? bundle?.result.points.firstOrNullValue?.nextSunsetAfter(etas.first)
        : null;
    final finishEta = tripMode ? etas.last : null;

    return [
      if (bundle != null && bundle.result.stale)
        StaleDataBanner(
          cachedAtUtc: bundle.result.cachedAtUtc ?? DateTime.now().toUtc(),
        ),
      const SizedBox(height: 8),
      _SummaryCard(summary: summary, settings: settings),
      const SizedBox(height: 8),
      if (route.mainSegment.length != route.flatPoints.length)
        const GranularityNotice(text: S.multiSegmentNote),
      if (route.origin == RouteOrigin.planet)
        const GranularityNotice(text: S.planetElevationNote),
      if (_mode == TimeMode.trip &&
          etas.length > 1 &&
          etas.last.difference(etas.first) > const Duration(hours: 12))
        const GranularityNotice(text: S.longTripNote),
      const SizedBox(height: 8),
      _HintsCard(rows: rows, sunsetUtc: sunset, finishEta: finishEta),
      const SizedBox(height: 8),
      Text(S.weatherAlongRoute, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      if (route.totalAscentM != null) ...[
        ElevationProfile(
          distancesM: [for (final r in rows) r.node.distFromStartM],
          elevationsM: [for (final r in rows) r.node.elevationM],
          selectedIndex: _selectedNode ?? -1,
          onTapNode: (i) => setState(() => _selectedNode = i),
        ),
      ] else
        const GranularityNotice(text: S.noElevation),
      const SizedBox(height: 4),
      for (var i = 0; i < rows.length; i++)
        _NodeTile(
          row: rows[i],
          selected: _selectedNode == i,
          settings: settings,
          onTap: () => setState(() => _selectedNode = i),
          onLongPress: () => _showNodeSheet(rows, settings, initialIndex: i),
        ),
      const SizedBox(height: 8),
      _TransparencyCard(provider: provider, bundle: bundle),
    ];
  }

  void _showNodeSheet(
    List<NodeWxRow> rows,
    AppSettings settings, {
    int? initialIndex,
  }) {
    final idx =
        initialIndex ??
        (_selectedNode != null && _selectedNode! < rows.length
            ? _selectedNode!
            : 0);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            NodeComparePanel(
              rows: rows,
              initialIndex: idx,
              fixedUtc: _mode == TimeMode.fixed ? _fixedUtc() : null,
            ),
          ],
        ),
      ),
    );
  }
}

extension on List<WxPointForecast> {
  WxPointForecast? get firstOrNullValue => isEmpty ? null : first;
}

class _RouteMiniMap extends ConsumerWidget {
  const _RouteMiniMap({
    required this.route,
    required this.rows,
    required this.selectedIndex,
  });

  final HikingRoute route;
  final List<NodeWxRow> rows;
  final int? selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basemap = Basemap(ref.watch(settingsProvider).basemap);
    final pts = route.mainSegment;
    final (minLat, maxLat) = Geo.minMaxLat(pts);
    final (minLon, maxLon) = Geo.minMaxLon(pts);
    final center = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: basemap.toDisplay(center),
            initialZoom: 12,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            basemap.tileLayer(),
            PolylineLayer(
              polylines: [
                for (final seg in route.segments)
                  Polyline(
                    points: [
                      for (final pt in Geo.simplify(seg, 15))
                        basemap.toDisplay(pt),
                    ],
                    strokeWidth: 4,
                    color: const Color(0xFF1565C0),
                  ),
              ],
            ),
            MarkerLayer(
              markers: [
                for (var i = 0; i < rows.length; i++)
                  Marker(
                    point: basemap.toDisplay(rows[i].node.pos),
                    width: 26,
                    height: 26,
                    child: GestureDetector(
                      onTap: () {},
                      child: Icon(
                        selectedIndex == i ? Icons.place : Icons.circle,
                        size: selectedIndex == i ? 24 : 10,
                        color: selectedIndex == i
                            ? Colors.red
                            : (rows[i].wx == null
                                  ? Colors.grey
                                  : Colors.deepOrange),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteFactsCard extends ConsumerWidget {
  const _RouteFactsCard({required this.route});

  final HikingRoute route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = const TextStyle(fontSize: 13);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${S.distanceLabel}：${(route.totalDistanceM / 1000).toStringAsFixed(1)} km',
                  style: style,
                ),
                const SizedBox(width: 16),
                Text(
                  '${S.ascentLabel}：${route.totalAscentM == null ? S.unknown : '${route.totalAscentM!.toStringAsFixed(0)} m'}',
                  style: style,
                ),
              ],
            ),
            const SizedBox(height: 4),
            RouteSourceLine(route: route),
          ],
        ),
      ),
    );
  }
}

class _TimeControlsCard extends StatelessWidget {
  const _TimeControlsCard({
    required this.mode,
    required this.onMode,
    required this.date,
    required this.onDate,
    required this.hour,
    this.previewHour,
    required this.onHourPreview,
    required this.onHourCommit,
    required this.startTime,
    required this.onStartTime,
    required this.pace,
    required this.onPace,
  });

  final TimeMode mode;
  final void Function(TimeMode) onMode;
  final DateTime date;
  final void Function(DateTime) onDate;
  final int hour;
  final double? previewHour;
  final void Function(double) onHourPreview;
  final void Function(int) onHourCommit;
  final TimeOfDay startTime;
  final void Function(TimeOfDay) onStartTime;
  final PaceConfig pace;
  final void Function(PaceConfig) onPace;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<TimeMode>(
              segments: [
                ButtonSegment(value: TimeMode.fixed, label: Text(S.modeFixed)),
                ButtonSegment(value: TimeMode.trip, label: Text(S.modeTrip)),
              ],
              selected: {mode},
              onSelectionChanged: (s) => onMode(s.first),
            ),
            const SizedBox(height: 4),
            Text(
              mode == TimeMode.fixed ? S.modeFixedDesc : S.modeTripDesc,
              style: const TextStyle(fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    '${date.year}-${_two(date.month)}-${_two(date.day)}',
                  ),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: now.subtract(const Duration(days: 1)),
                      lastDate: now.add(const Duration(days: 30)),
                    );
                    if (d != null) onDate(d);
                  },
                ),
                const SizedBox(width: 8),
                if (mode == TimeMode.trip)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 16),
                    label: Text(
                      '${S.departure} ${_two(startTime.hour)}:${_two(startTime.minute)}',
                    ),
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: startTime,
                      );
                      if (t != null) onStartTime(t);
                    },
                  ),
              ],
            ),
            if (mode == TimeMode.fixed) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('时刻', style: Theme.of(context).textTheme.labelMedium),
                  Expanded(
                    child: Slider(
                      value: hour.toDouble(),
                      min: 0,
                      max: 23,
                      divisions: 23,
                      label: '${_two(hour)}:00（本地时区）',
                      onChanged: onHourPreview,
                      onChangeEnd: (v) => onHourCommit(v.round()),
                    ),
                  ),
                  Text('${_two((previewHour ?? hour.toDouble()).round())}:00'),
                ],
              ),
            ],
            if (mode == TimeMode.trip)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.directions_walk),
                title: const Text(
                  S.paceSettings,
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  '速度 ${pace.speedKmh} km/h · 上升 ${pace.ascentMinPer100m} min/100m · 休息 ${pace.restMinutesTotal} min',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.tune, size: 18),
                onTap: () => _showPaceSheet(context),
              ),
            if (mode == TimeMode.trip)
              Text(
                S.etaIsEstimate,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPaceSheet(BuildContext context) {
    var speed = pace.speedKmh;
    var ascent = pace.ascentMinPer100m;
    var rest = pace.restMinutesTotal;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.paceSettings, style: Theme.of(ctx).textTheme.titleMedium),
              ...pace.assumptionNotes().map(
                (n) => Text('· $n', style: const TextStyle(fontSize: 11)),
              ),
              const SizedBox(height: 8),
              Text('平地速度：${speed.toStringAsFixed(1)} km/h'),
              Slider(
                value: speed,
                min: 1.5,
                max: 6,
                divisions: 18,
                label: speed.toStringAsFixed(1),
                onChanged: (v) => setSheet(() => speed = v),
              ),
              Text('每上升 100 m 加时：${ascent.toStringAsFixed(0)} 分钟'),
              Slider(
                value: ascent,
                min: 4,
                max: 40,
                divisions: 36,
                label: ascent.toStringAsFixed(0),
                onChanged: (v) => setSheet(() => ascent = v),
              ),
              Text('全程休息：$rest 分钟'),
              Slider(
                value: rest.toDouble(),
                min: 0,
                max: 180,
                divisions: 18,
                label: '$rest',
                onChanged: (v) => setSheet(() => rest = v.round()),
              ),
              FilledButton(
                onPressed: () {
                  onPace(
                    PaceConfig(
                      speedKmh: speed,
                      ascentMinPer100m: ascent,
                      descentMinPer100m: (ascent / 2).roundToDouble(),
                      restMinutesTotal: rest,
                    ),
                  );
                  Navigator.pop(ctx);
                },
                child: const Text(S.ok),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}

class _SourceChips extends ConsumerWidget {
  const _SourceChips({
    required this.selected,
    required this.onSelect,
    required this.onCompare,
  });

  final String selected;
  final void Function(String) onSelect;
  final VoidCallback onCompare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(weatherProvidersProvider);
    final enabled = ref.watch(settingsProvider).enabledProviderIds;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in providers)
                  if (enabled.contains(p.caps.providerId))
                    ChoiceChip(
                      label: Text(
                        p.caps.displayName,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: selected == p.caps.providerId,
                      onSelected: (_) => onSelect(p.caps.providerId),
                    ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.compare_arrows, size: 16),
                label: Text(
                  S.compareSources,
                  style: const TextStyle(fontSize: 13),
                ),
                onPressed: onCompare,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.settings});

  final RouteWxSummary summary;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    if (!summary.hasAnyData) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '当前选定时间与来源没有可用数据（${summary.nodesWithData}/${summary.totalNodes} 节点有数据）。信息不足时无法给出摘要。',
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.routeSummary, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _kv(
                  '最低/最高温',
                  '${Units.temp(summary.minTempC ?? 0, imperial: settings.imperial, digits: 0)} / ${Units.temp(summary.maxTempC ?? 0, imperial: settings.imperial)}',
                ),
                _kv(
                  '沿途降水（估算）',
                  summary.totalPrecipMm == null
                      ? S.notProvided
                      : Units.precipMm(
                          summary.totalPrecipMm!,
                          imperial: settings.imperial,
                        ),
                ),
                _kv(
                  '最大阵风',
                  summary.maxGustMs == null
                      ? S.notProvided
                      : Units.windMs(
                          summary.maxGustMs!,
                          unit: settings.windUnit,
                        ),
                ),
                _kv(
                  '有降水节点',
                  '${summary.precipNodeCount}/${summary.totalNodes}',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '按当前选定来源汇总，不与其他来源拼接。',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Text(
        v,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _HintsCard extends StatelessWidget {
  const _HintsCard({
    required this.rows,
    required this.sunsetUtc,
    required this.finishEta,
  });

  final List<NodeWxRow> rows;
  final DateTime? sunsetUtc;
  final DateTime? finishEta;

  @override
  Widget build(BuildContext context) {
    final hints = computeHints(entries: rowsToEntries(rows));
    final sunset = (sunsetUtc != null && finishEta != null)
        ? sunsetHint(sunsetUtc: sunsetUtc!, finishEtaUtc: finishEta!)
        : null;
    final all = [...hints, ?sunset];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.riskHints, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (all.isEmpty)
              const Text(
                '当前数据未触发任何阈值提示（这不代表安全）。',
                style: TextStyle(fontSize: 12),
              ),
            for (final h in all)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      h.level == HintLevel.warning
                          ? Icons.warning_amber_rounded
                          : h.level == HintLevel.caution
                          ? Icons.info
                          : Icons.info_outline,
                      size: 16,
                      color: h.level == HintLevel.warning
                          ? Colors.red
                          : h.level == HintLevel.caution
                          ? Colors.orange
                          : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${h.title}：${h.detail}',
                            style: const TextStyle(fontSize: 12, height: 1.4),
                          ),
                          Text(
                            '依据：${h.basis}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 16),
            Text(
              S.officialAlerts,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            const Text(
              officialAlertsNotAvailable,
              style: TextStyle(fontSize: 11, height: 1.4, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.row,
    required this.selected,
    required this.settings,
    required this.onTap,
    required this.onLongPress,
  });

  final NodeWxRow row;
  final bool selected;
  final AppSettings settings;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final local = row.validUtc.toLocal();
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer
          .withValues(alpha: 0.3),
      leading: Icon(
        row.node.label == '起点'
            ? Icons.flag_outlined
            : row.node.label == '终点'
            ? Icons.outlined_flag
            : row.node.label == '高点'
            ? Icons.terrain_outlined
            : Icons.circle,
        size: 18,
      ),
      title: Text(
        '${row.node.label ?? '节点'} · ${(row.node.distFromStartM / 1000).toStringAsFixed(1)} km'
        '${row.node.elevationM == null ? '' : ' · ${row.node.elevationM!.toStringAsFixed(0)} m'}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_fmt(local)}（UTC ${_fmtUtc(row.validUtc)}）${row.sharedWithPrev ? ' · 与上一节点共享同一查询点' : ''}',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          WxBriefLine(wx: row.wx, settings: settings),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  String _fmt(DateTime t) =>
      '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String _fmtUtc(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _TransparencyCard extends StatelessWidget {
  const _TransparencyCard({required this.provider, required this.bundle});

  final WeatherProvider provider;
  final RouteWeatherBundle? bundle;

  @override
  Widget build(BuildContext context) {
    final caps = provider.caps;
    final prov = bundle?.result.points.isEmpty == false
        ? bundle!.result.points.first.provenance
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.sourceTransparency,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                SourceBadge(caps: caps),
                DataKindChip(kind: caps.dataKind),
              ],
            ),
            const SizedBox(height: 8),
            GranularityNotice(
              text:
                  prov?.granularityStatement() ??
                  caps.spatialResolutionNote ??
                  '来源未提供空间分辨率，位置颗粒度未确认',
            ),
            if (bundle?.sharedGridNote != null) ...[
              const SizedBox(height: 6),
              GranularityNotice(
                text: '${S.sharedGridNotePrefix}：${bundle!.sharedGridNote}',
              ),
            ],
            if (caps.modelOverlapNote != null) ...[
              const SizedBox(height: 6),
              GranularityNotice(
                text: caps.modelOverlapNote!,
                icon: Icons.hub_outlined,
              ),
            ],
            const SizedBox(height: 8),
            if (prov != null)
              Text(
                '${S.fetchedAt}：${prov.fetchedAtUtc.toIso8601String().substring(0, 16)} UTC'
                '${prov.modelRunUtc == null ? '' : '\n起报/发布：${prov.modelRunUtc!.toIso8601String().substring(0, 16)} UTC'}'
                '${prov.elevationUsedM == null ? '' : '\n来源使用海拔（模型地形）：${prov.elevationUsedM!.toStringAsFixed(0)} m；轨迹海拔见各节点（两者是不同数据）'}',
                style: const TextStyle(fontSize: 11, height: 1.5),
              ),
            TextButton.icon(
              icon: const Icon(Icons.science_outlined, size: 16),
              label: const Text('查看完整溯源信息', style: TextStyle(fontSize: 12)),
              onPressed: prov == null
                  ? null
                  : () {
                      final map = prov.toDisplayMap();
                      showDialog<void>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text(S.sourceTransparency),
                          content: SizedBox(
                            width: 380,
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final e in map.entries)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      '${e.key}：${e.value}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx),
                              child: const Text(S.close),
                            ),
                          ],
                        ),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }
}
