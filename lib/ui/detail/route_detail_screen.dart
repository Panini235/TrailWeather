import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';

import '../../data/offline/offline_trip.dart';
import '../offline/offline_screens.dart';
import '../departure/departure_screen.dart';

import '../../core/geo.dart';
import '../../core/units.dart';
import '../../data/app_providers.dart';
import '../../data/map/tianditu.dart';
import '../../data/routes/route_models.dart';
import '../../data/routes/route_sampling.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/photos/route_photos.dart';
import '../../data/weather/eta.dart';
import '../../data/weather/departure_windows.dart';
import '../../data/weather/node_wx_class.dart';
import '../../data/weather/risk_rules.dart';
import '../../data/weather/weather_provider.dart';
import '../../data/weather/weather_repository.dart';
import '../strings.dart';
import '../widgets/common.dart';
import '../map/basemap.dart';
import '../map/map_layers_ui.dart';
import '../map/route_camera.dart';
import '../map/route_marks.dart';
import 'detail_state.dart';
import '../share/share_cards.dart';
import '../share/share_image.dart';
import 'elevation_profile.dart';
import 'node_detail_view.dart';
import 'node_photos.dart';
import 'node_wx_style.dart';
import 'weather_cells.dart';

String _two(int n) => n.toString().padLeft(2, '0');

class RouteDetailArgs {
  const RouteDetailArgs({required this.route});
  final HikingRoute route;
}

/// 详情页天气数据提供者：参数为（节点序列, 查询）。
/// 必须实现 ==：family 依赖键相等判断，避免每帧重建触发重复请求。
class DetailFetchKey {
  DetailFetchKey({required List<RouteNode> nodes, required this.query})
    : nodes = List.unmodifiable(nodes),
      _coordinates = List.unmodifiable(
        nodes.map((n) => (n.pos.latitude, n.pos.longitude, n.elevationM)),
      );

  final List<RouteNode> nodes;
  final RouteWeatherQuery query;
  final List<(double, double, double?)> _coordinates;

  @override
  bool operator ==(Object other) =>
      other is DetailFetchKey &&
      other.query == query &&
      listEquals(other._coordinates, _coordinates);

  @override
  int get hashCode => Object.hash(query, Object.hashAll(_coordinates));
}

final detailWeatherProvider = StreamProvider.autoDispose
    .family<RouteWeatherBundle, DetailFetchKey>((ref, key) {
      final repo = ref.watch(weatherRepositoryProvider);
      return repo.watchRouteWeatherBundle(
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

  /// 用户标记会更新这条线路（并保存到“我的行程”）；反向行走只是视图状态。
  late HikingRoute _base = widget.args.route;
  bool _reversed = false;

  /// 时间设置默认收起，由顶部时间标签展开（减少首屏控件）。
  bool _timeOpen = false;
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _tileKeys = {};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 选中节点：地图标记、海拔剖面、时间线三处共享同一选中状态。
  void _select(int i, {bool scroll = false}) {
    setState(() => _selectedNode = i);
    if (!scroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tileKeys[i]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          alignment: 0.3,
        );
      }
    });
  }

  void _toggleReverse() {
    setState(() {
      _reversed = !_reversed;
      _selectedNode = null;
    });
  }

  // ---- 标记（营地 / 休息点 …）----

  Future<void> _persist(HikingRoute updated) async {
    final wasSaved = ref.read(favoritesProvider).any((r) => r.id == updated.id);
    setState(() => _base = updated);
    await ref.read(favoritesProvider.notifier).add(updated);
    if (!wasSaved && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.markSavedNew)));
    }
  }

  Future<RouteWaypoint?> _editDialog(RouteWaypoint initial) {
    final nameCtrl = TextEditingController(text: initial.name);
    final stopCtrl = TextEditingController(
      text: initial.stopMinutes?.toString() ?? '',
    );
    var type = initial.type;
    return showDialog<RouteWaypoint>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(initial.name.isEmpty ? S.markAs : S.editMark),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<WaypointType>(
                initialValue: type,
                items: [
                  for (final t in WaypointType.values)
                    DropdownMenuItem(
                      value: t,
                      child: Text(waypointTypeLabel(t)),
                    ),
                ],
                onChanged: (t) => setLocal(() {
                  if (t == null) return;
                  // 名称仍是默认类型名时跟随类型变化
                  if (nameCtrl.text == defaultWaypointName(type)) {
                    nameCtrl.text = defaultWaypointName(t);
                  }
                  type = t;
                }),
              ),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: S.markName),
              ),
              if (type != WaypointType.camp)
                TextField(
                  controller: stopCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: S.markStopMinutes,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(S.cancel),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final stop = int.tryParse(stopCtrl.text.trim());
                Navigator.pop(
                  ctx,
                  RouteWaypoint(
                    name: name.isEmpty ? defaultWaypointName(type) : name,
                    point: initial.point,
                    type: type,
                    desc: initial.desc,
                    elevationM: initial.elevationM,
                    stopMinutes: type == WaypointType.camp || stop == null
                        ? null
                        : stop.clamp(0, 24 * 60),
                  ),
                );
              },
              child: const Text(S.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMark(LatLng at, WaypointType type, {double? ele}) async {
    final created = await _editDialog(
      RouteWaypoint(
        name: defaultWaypointName(type),
        point: at,
        type: type,
        elevationM: ele,
        stopMinutes: type == WaypointType.rest ? 15 : null,
      ),
    );
    if (created == null) return;
    await _persist(_base.copyWith(waypoints: [..._base.waypoints, created]));
  }

  Future<void> _editMark(RouteWaypoint wp) async {
    final edited = await _editDialog(wp);
    if (edited == null) return;
    await _persist(
      _base.copyWith(
        waypoints: [
          for (final w in _base.waypoints) identical(w, wp) ? edited : w,
        ],
      ),
    );
  }

  Future<void> _removeMark(RouteWaypoint wp) async {
    await _persist(
      _base.copyWith(
        waypoints: [
          for (final w in _base.waypoints)
            if (!identical(w, wp)) w,
        ],
      ),
    );
  }

  /// 全屏地图返回：int = 查看该节点详情；LatLng = 在此处添加标记（已吸附检查）。
  Future<void> _openFullMap(
    HikingRoute route,
    List<NodeWxRow> rows,
    AppSettings settings,
  ) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _RouteFullMapPage(
          route: route,
          rows: rows,
          selectedIndex: _selectedNode,
          onSelect: (i) => _select(i),
        ),
      ),
    );
    if (!mounted) return;
    if (result is int) {
      _select(result, scroll: true);
      _showNodeSheet(rows, settings, initialIndex: result);
    } else if (result is LatLng) {
      final path = route.analysisPath.points;
      final snapped = snapWaypoints(path, [
        RouteWaypoint(name: '', point: result, type: WaypointType.poi),
      ]);
      if (snapped.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.markTooFar)));
        return;
      }
      final idx = snapped.keys.first;
      await _addMark(
        path[idx],
        WaypointType.rest,
        ele: route.analysisPath.elevations[idx],
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _providerId = primaryProviderId(
      ref.read(settingsProvider).enabledProviderIds,
      ref.read(weatherProvidersProvider),
    );
  }

  static DateTime _defaultFixedLocal() {
    final now = DateTime.now();
    if (now.hour < 10) return DateTime(now.year, now.month, now.day, 10);
    return DateTime(now.year, now.month, now.day, now.hour + 1); // 23 点会进位到次日
  }

  (DateTime, DateTime) _utcWindow(List<RouteNode> nodes, List<DateTime> etas) {
    if (_mode == TimeMode.fixed) {
      // 固定时刻按“设备时区的整天”取数（多 1 小时容纳 Open-Meteo 24:00 的前一小时累计）：
      // 结论卡可给出全天降水，拖动时刻滑块也不再触发新请求。
      final day = DateTime(_date.year, _date.month, _date.day).toUtc();
      return (day, day.add(const Duration(hours: 25)));
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
    final route = _reversed ? _base.reversed() : _base;
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

    // 结论区需要的提示（含日落）；规则与旧版一致，只是展示位置变了。
    final tripMode = _mode == TimeMode.trip && etas.isNotEmpty;
    final sunset = tripMode && rows.isNotEmpty
        ? departureDaySunset(
            point: rows.last.point,
            longitude: rows.last.node.pos.longitude,
            startUtc: etas.first,
          )
        : null;
    final sunsetWarn = sunset != null
        ? sunsetHint(sunsetUtc: sunset, finishEtaUtc: etas.last)
        : null;
    final hints = <WxHint>[
      ...computeHints(entries: rowsToEntries(rows)),
      ?sunsetWarn,
    ];

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
            tooltip: S.shareImage,
            icon: const Icon(Icons.ios_share),
            onPressed: () => _openShare(
              route: route,
              rows: rows,
              settings: settings,
              hints: hints,
              bundle: bundleAsync.value,
              query: query,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            tooltip: '下载离线行程包',
            onPressed: () => context.push(
              '/offline/new',
              extra: OfflineDownloadArgs(
                providerId: _providerId,
                plan: OfflineTripPlan(
                  route: route,
                  nodes: List.unmodifiable(nodes),
                  nodeTimesUtc: List.unmodifiable(etas),
                  mode: _mode == TimeMode.trip
                      ? OfflineTimeMode.trip
                      : OfflineTimeMode.fixed,
                  reversed: _reversed,
                  selectedTimeUtc: query.fixedUtc,
                  pace: _pace,
                  startUtc: utcHour(startUtc),
                  endUtc: utcHour(startUtc).add(const Duration(hours: 72)),
                ),
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
            onPressed: () => ref.read(favoritesProvider.notifier).toggle(_base),
          ),
        ],
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          // 第一层：控制条（时间 / 来源）+ 结论。
          _ControlBar(
            timeLabel: _timeChipLabel(query.fixedUtc),
            timeOpen: _timeOpen,
            onToggleTime: () => setState(() => _timeOpen = !_timeOpen),
            providerId: _providerId,
            onSelectProvider: (id) => setState(() => _providerId = id),
            onCompare: () => _showNodeSheet(rows, settings),
          ),
          if (_timeOpen)
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
          if (bundleAsync.value != null)
            WeatherCacheNotice(result: bundleAsync.value!.result),
          if (bundleAsync.isLoading && !bundleAsync.hasValue)
            const LinearProgressIndicator(semanticsLabel: '正在获取线路天气')
          else if (!bundleAsync.hasError)
            _ConclusionCard(
              summary: summarizeRows(rows),
              tripMode: _mode == TimeMode.trip,
              dayLine: _mode == TimeMode.fixed && bundleAsync.value != null
                  ? _dayPrecipLine(bundleAsync.value!, settings)
                  : null,
              settings: settings,
              hints: hints,
              onShowHints: () => _showHints(hints),
              onDepartures: () => _openDepartures(route, nodes),
            ),
          const SizedBox(height: 8),
          // 第二层：地图 + 线路要点 + 沿途节点。
          _RouteMiniMap(
            route: route,
            rows: rows,
            selectedIndex: _selectedNode,
            onTapNode: (i) => _select(i, scroll: true),
            onOpenFullscreen: () => _openFullMap(route, rows, settings),
          ),
          _RouteFactsRow(
            route: route,
            reversed: _reversed,
            onToggleReverse: _toggleReverse,
          ),
          ..._weatherSection(
            bundleAsync,
            rows,
            settings,
            nodes,
            etas,
            route,
            query,
            sunsetKnown: sunset != null,
          ),
        ],
      ),
    );
  }

  /// 分享图：线路天气卡片（时间、摘要、全天降水、提示、沿途节点、来源与免责声明）。
  void _openShare({
    required HikingRoute route,
    required List<NodeWxRow> rows,
    required AppSettings settings,
    required List<WxHint> hints,
    required RouteWeatherBundle? bundle,
    required RouteWeatherQuery query,
  }) {
    if (bundle == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.shareNeedsData)));
      return;
    }
    final source = ref
        .read(weatherProvidersProvider)
        .where((p) => p.caps.providerId == _providerId)
        .firstOrNull;
    final timeLabel = _timeChipLabel(query.fixedUtc);
    final day = query.fixedUtc.toLocal();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SharePreviewPage(
          title: S.shareImage,
          fileName:
              'shanqing-${day.year}${_two(day.month)}${_two(day.day)}.png',
          shareText: '${route.name} · $timeLabel · 山晴徒步天气',
          card: RouteShareCard(
            route: route,
            timeLabel: timeLabel,
            tripMode: _mode == TimeMode.trip,
            reversed: _reversed,
            summary: summarizeRows(rows),
            dayPrecip: _mode == TimeMode.fixed
                ? summarizeDayPrecip(
                    points: bundle.result.points,
                    dayStartUtc: DateTime(
                      _date.year,
                      _date.month,
                      _date.day,
                    ).toUtc(),
                    precedingHour: bundle.result.providerId.startsWith(
                      'open-meteo:',
                    ),
                  )
                : null,
            hints: hints,
            rows: rows,
            settings: settings,
            sourceName: source?.caps.displayName ?? _providerId,
            fetchedAtUtc: bundle.result.fetchedAtUtc,
          ),
        ),
      ),
    );
  }

  /// 固定时刻模式的“全天”一行，避免把某一小时的 0.0 mm 读成全天无雨。
  String _dayPrecipLine(RouteWeatherBundle bundle, AppSettings settings) {
    final day = DateTime(_date.year, _date.month, _date.day);
    final d = summarizeDayPrecip(
      points: bundle.result.points,
      dayStartUtc: day.toUtc(),
      precedingHour: bundle.result.providerId.startsWith('open-meteo:'),
    );
    final head = '${day.month}月${day.day}日全天';
    if (d.maxDayMm == null) return '$head：此来源未提供降水量。';
    final partial = d.minHoursCovered < 24
        ? '（来源仅覆盖 ${d.minHoursCovered} 小时）'
        : '';
    final prob = d.maxProb == null
        ? ''
        : '，最大概率 ${d.maxProb!.toStringAsFixed(0)}%';
    if (d.firstWetUtc == null) {
      return '$head：沿途预报无明显降水（每小时 <0.1 mm）$prob$partial';
    }
    final a = d.firstWetUtc!.toLocal();
    final b = d.lastWetUtc!.toLocal().add(const Duration(hours: 1));
    return '$head：沿途降水最多约 '
        '${Units.precipMm(d.maxDayMm!, imperial: settings.imperial)}，'
        '主要在 ${_two(a.hour)}–${_two(b.hour == 0 ? 24 : b.hour)} 时$prob$partial';
  }

  /// 顶部时间标签：固定时刻显示“固定 M/d HH:00”，行程模式显示“出发 M/d HH:mm”（设备时区）。
  String _timeChipLabel(DateTime utc) {
    final l = utc.toLocal();
    final t = '${l.month}/${l.day} ${_two(l.hour)}:${_two(l.minute)}';
    return _mode == TimeMode.trip ? '出发 $t' : '固定 $t';
  }

  Future<void> _openDepartures(HikingRoute route, List<RouteNode> nodes) async {
    final selected = await context.push<DepartureSelection>(
      '/departures',
      extra: DepartureArgs(
        route: route,
        nodes: nodes,
        pace: _pace,
        providerId: _providerId,
        initialDate: _date,
        reversed: _reversed,
      ),
    );
    if (selected != null && mounted) {
      final local = selected.startUtc.toLocal();
      setState(() {
        _mode = TimeMode.trip;
        _date = DateTime(local.year, local.month, local.day);
        _startTime = TimeOfDay.fromDateTime(local);
        _providerId = selected.providerId;
        _selectedNode = null;
      });
    }
  }

  void _showHints(List<WxHint> hints) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(S.riskHints, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (hints.isEmpty) const Text(S.noHintsTriggered),
            for (final h in hints) ...[
              Text(
                '${h.title}：${h.detail}',
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              Text(
                '依据：${h.basis}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
            ],
            const Divider(),
            const Text(
              officialAlertsNotAvailable,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
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
    RouteWeatherQuery query, {
    required bool sunsetKnown,
  }) {
    final provider = ref
        .read(weatherProvidersProvider)
        .where((p) => p.caps.providerId == _providerId)
        .first;
    if (bundleAsync.isLoading && !bundleAsync.hasValue) {
      return const [];
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
    final tripMode = _mode == TimeMode.trip && etas.isNotEmpty;
    // 说明类文字统一收进底部“数据说明与来源”，不再逐条铺在沿途内容之间。
    final notes = <String>[
      if (!route.analysisPath.coversAllSegments) S.multiSegmentNote,
      if (_reversed) S.reversedNote,
      if (route.origin == RouteOrigin.planet) S.planetElevationNote,
      if (tripMode &&
          etas.length > 1 &&
          etas.last.difference(etas.first) > const Duration(hours: 12))
        S.longTripNote,
      if (route.totalAscentM == null) S.noElevation,
      if (tripMode)
        sunsetKnown
            ? '日落按终点经度近似归属出发日期；未计山体遮挡，日出未接入。'
            : '日落：此来源未提供出发日终点日落。日出未接入。',
      '时间按设备时区显示。',
    ];

    return [
      const SizedBox(height: 4),
      Text(S.weatherAlongRoute, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      if (route.totalAscentM != null)
        ElevationProfile(
          distancesM: [for (final r in rows) r.node.distFromStartM],
          elevationsM: [for (final r in rows) r.node.elevationM],
          selectedIndex: _selectedNode ?? -1,
          onTapNode: (i) => _select(i, scroll: true),
        ),
      for (var i = 0; i < rows.length; i++)
        _NodeTile(
          key: _tileKeys.putIfAbsent(i, GlobalKey.new),
          row: rows[i],
          index: i,
          isLast: i == rows.length - 1,
          tripMode: tripMode,
          selected: _selectedNode == i,
          settings: settings,
          // 第一次点选中（地图/剖面同步高亮），再点打开详情。
          onTap: () => _selectedNode == i
              ? _showNodeSheet(rows, settings, initialIndex: i)
              : _select(i),
          onDetail: () {
            _select(i);
            _showNodeSheet(rows, settings, initialIndex: i);
          },
        ),
      const SizedBox(height: 8),
      // 第三层：默认收起。
      ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: const Text(S.dataNotesTitle),
        subtitle: Text(
          S.dataNotesSubtitle,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GranularityNotice(text: n),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '${S.officialAlerts}：$officialAlertsNotAvailable',
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
          RouteSourceLine(route: route),
          const SizedBox(height: 6),
          _TransparencyCard(provider: provider, bundle: bundle),
        ],
      ),
    ];
  }

  void _showNodeSheet(
    List<NodeWxRow> rows,
    AppSettings settings, {
    int? initialIndex,
  }) {
    if (rows.isEmpty) return;
    final idx =
        initialIndex ??
        (_selectedNode != null && _selectedNode! < rows.length
            ? _selectedNode!
            : 0);
    // 标记操作先关闭面板再弹编辑框；线路更新后节点会重新计算。
    void closeThen(Future<void> Function() action) {
      Navigator.of(context).pop();
      action();
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            NodeDetailView(
              rows: rows,
              initialIndex: idx,
              tripMode: _mode == TimeMode.trip,
              fixedUtc: _fixedUtc(),
              settings: settings,
              onIndexChanged: (i) => _select(i, scroll: true),
              onMark: (n, type) => closeThen(
                () => _addMark(
                  rows[n.index].node.pos,
                  type,
                  ele: rows[n.index].node.elevationM,
                ),
              ),
              onEditMark: (wp) => closeThen(() => _editMark(wp)),
              onRemoveMark: (wp) => closeThen(() => _removeMark(wp)),
              routeId: _base.id,
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteMiniMap extends ConsumerWidget {
  const _RouteMiniMap({
    required this.route,
    required this.rows,
    required this.selectedIndex,
    required this.onTapNode,
    required this.onOpenFullscreen,
  });

  final HikingRoute route;
  final List<NodeWxRow> rows;
  final int? selectedIndex;
  final ValueChanged<int> onTapNode;
  final VoidCallback onOpenFullscreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basemap = Basemap.fromSettings(
      ref.watch(settingsProvider),
      tiandituClient: ref.watch(tiandituTileClientProvider),
    );
    final fit = routeCameraFit(route, basemap);
    final photos = ref
        .watch(routePhotosProvider)
        .where((p) => p.routeId == route.id)
        .toList();
    // 小地图不响应拖动/缩放，避免与外层 ListView 滚动手势冲突；
    // 点节点标记选中节点，点空白处或全屏按钮进入可交互大图。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                FlutterMap(
                  // 反向行走时几何不变但起终点互换，key 带上方向让相机与标记重建。
                  key: ValueKey(
                    'mini-${route.id}-${basemap.signature}-${route.flatPoints.first}',
                  ),
                  options: MapOptions(
                    initialCameraFit: fit,
                    // 无几何时的兜底；有 fit 时 initialCameraFit 优先。
                    initialCenter: const LatLng(39.99, 116.17),
                    initialZoom: 12,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                    onTap: (_, _) => onOpenFullscreen(),
                  ),
                  children: _routeMapLayers(
                    basemap: basemap,
                    route: route,
                    rows: rows,
                    selectedIndex: selectedIndex,
                    onTapNode: onTapNode,
                    photos: photos,
                    onTapPhoto: (p) => showRoutePhotoViewer(context, p),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface
                        .withValues(alpha: 0.9),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: S.routeMapFullscreen,
                      icon: const Icon(Icons.fullscreen),
                      onPressed: onOpenFullscreen,
                    ),
                  ),
                ),
                const Positioned(
                  top: 6,
                  left: 6,
                  right: 58,
                  child: TiandituErrorBanner(compact: true),
                ),
              ],
            ),
          ),
        ),
        NodeWxLegend(
          classes: [
            for (final r in rows)
              if (r.node.waypoint == null) classifyNodeWx(r.wx),
          ],
        ),
      ],
    );
  }
}

/// 线路地图图层：线路、方向箭头、节点（可点选）、航点、起终点、选中高亮。
List<Widget> _routeMapLayers({
  required Basemap basemap,
  required HikingRoute route,
  required List<NodeWxRow> rows,
  required int? selectedIndex,
  ValueChanged<int>? onTapNode,
  List<RoutePhoto> photos = const [],
  ValueChanged<RoutePhoto>? onTapPhoto,
  bool attribution = false,
}) {
  final onRoute = {
    for (final r in rows)
      if (r.node.waypoint != null) r.node.waypoint!,
  };
  final sel = selectedIndex != null && selectedIndex < rows.length
      ? selectedIndex
      : null;
  return [
    ...basemap.tileLayers(),
    PolylineLayer(
      polylines: [
        for (final seg in route.segments)
          Polyline(
            points: [
              for (final pt in Geo.simplify(seg, 15)) basemap.toDisplay(pt),
            ],
            strokeWidth: 4,
            color: const Color(0xFF1565C0),
          ),
      ],
    ),
    routeDirectionLayer(route, basemap),
    MarkerLayer(
      markers: [
        // 偏离线路、未进入时间线的航点：半透明显示，不可选。
        for (final wp in route.waypoints)
          if (!onRoute.contains(wp))
            Marker(
              point: basemap.toDisplay(wp.point),
              width: 22,
              height: 22,
              child: Tooltip(
                message: '${wp.name}（${S.offRouteWaypoint}）',
                child: Opacity(
                  opacity: 0.55,
                  child: WaypointMarker(type: wp.type, size: 14),
                ),
              ),
            ),
        for (var i = 0; i < rows.length; i++)
          Marker(
            point: basemap.toDisplay(rows[i].node.pos),
            width: 30,
            height: 30,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapNode == null ? null : () => onTapNode(i),
              child: Center(
                child: rows[i].node.waypoint != null
                    ? WaypointMarker(
                        type: rows[i].node.waypoint!.type,
                        size: sel == i ? 22 : 16,
                      )
                    : NodeWxMarker(
                        cls: classifyNodeWx(rows[i].wx),
                        selected: sel == i,
                      ),
              ),
            ),
          ),
      ],
    ),
    routeEndpointLayer(route, basemap),
    if (photos.isNotEmpty)
      MarkerLayer(
        markers: [
          for (final p in photos)
            Marker(
              point: basemap.toDisplay(p.pos),
              width: 24,
              height: 24,
              alignment: Alignment.topRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTapPhoto == null ? null : () => onTapPhoto(p),
                child: const PhotoMapMarker(),
              ),
            ),
        ],
      ),
    if (sel != null)
      MarkerLayer(
        markers: [
          Marker(
            point: basemap.toDisplay(rows[sel].node.pos),
            width: 38,
            height: 38,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red, width: 3),
                ),
              ),
            ),
          ),
        ],
      ),
    if (attribution) basemap.attributionWidget(),
  ];
}

/// 可拖动/缩放的线路大图；打开时自动适配整条线路范围。
/// 点节点选中并显示摘要卡；长按线路附近返回该位置用于添加标记。
class _RouteFullMapPage extends ConsumerStatefulWidget {
  const _RouteFullMapPage({
    required this.route,
    required this.rows,
    required this.selectedIndex,
    required this.onSelect,
  });

  final HikingRoute route;
  final List<NodeWxRow> rows;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  ConsumerState<_RouteFullMapPage> createState() => _RouteFullMapPageState();
}

class _RouteFullMapPageState extends ConsumerState<_RouteFullMapPage> {
  final MapController _controller = MapController();
  late int? _sel = widget.selectedIndex;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final basemap = Basemap.fromSettings(
      settings,
      tiandituClient: ref.watch(tiandituTileClientProvider),
    );
    final fit = routeCameraFit(
      widget.route,
      basemap,
      padding: const EdgeInsets.all(40),
    );
    final sel = _sel != null && _sel! < widget.rows.length ? _sel : null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.route.name)),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MapLayerButton(heroTag: 'detailLayers'),
          if (fit != null) ...[
            const SizedBox(height: 10),
            FloatingActionButton.small(
              heroTag: 'detailFit',
              tooltip: S.routeMapFitAll,
              onPressed: () => _controller.fitCamera(fit),
              child: const Icon(Icons.fit_screen),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCameraFit: fit,
              minZoom: 3,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onLongPress: (_, p) =>
                  Navigator.of(context).pop(basemap.toBusiness(p)),
            ),
            children: _routeMapLayers(
              basemap: basemap,
              route: widget.route,
              rows: widget.rows,
              selectedIndex: sel,
              onTapNode: (i) {
                setState(() => _sel = i);
                widget.onSelect(i);
              },
              photos: ref
                  .watch(routePhotosProvider)
                  .where((p) => p.routeId == widget.route.id)
                  .toList(),
              onTapPhoto: (p) => showRoutePhotoViewer(context, p),
              attribution: true,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Material(
                    color: Theme.of(context).colorScheme.surface
                        .withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        S.longPressToMark,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const TiandituErrorBanner(margin: EdgeInsets.only(top: 6)),
                ],
              ),
            ),
          ),
          if (sel != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Card(
                  margin: const EdgeInsets.fromLTRB(12, 0, 64, 12),
                  child: ListTile(
                    title: Text(
                      '${widget.rows[sel].node.label ?? '节点 ${sel + 1}'} · '
                      '${(widget.rows[sel].node.distFromStartM / 1000).toStringAsFixed(1)} km',
                    ),
                    subtitle: WxBriefLine(
                      wx: widget.rows[sel].wx,
                      settings: settings,
                    ),
                    trailing: TextButton(
                      onPressed: () => Navigator.of(context).pop(sel),
                      child: const Text(S.nodeDetail2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 线路要点一行：里程 · 爬升 · 方向，右侧反向按钮（不再单独一张卡）。
class _RouteFactsRow extends StatelessWidget {
  const _RouteFactsRow({
    required this.route,
    required this.reversed,
    required this.onToggleReverse,
  });

  final HikingRoute route;
  final bool reversed;
  final VoidCallback onToggleReverse;

  @override
  Widget build(BuildContext context) {
    final ascent = route.totalAscentM;
    final facts = [
      '${(route.totalDistanceM / 1000).toStringAsFixed(1)} km',
      if (ascent != null) '↑${ascent.toStringAsFixed(0)} m',
      route.isLoop
          ? S.loopRoute
          : '${S.startPoint}（绿）→ ${S.endPoint}（红）${reversed ? ' · 已反向' : ''}',
    ].join(' · ');
    return Row(
      children: [
        Expanded(child: Text(facts, style: const TextStyle(fontSize: 12))),
        // 环线同样有方向（顺/逆时针到达各点的时间不同），始终可反向。
        TextButton.icon(
          onPressed: onToggleReverse,
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: Text(reversed ? '恢复原方向' : S.reverseRoute),
        ),
      ],
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
}

/// 顶部控制条：时间标签（展开/收起时间设置）+ 来源菜单（含“对比来源”）。
class _ControlBar extends ConsumerWidget {
  const _ControlBar({
    required this.timeLabel,
    required this.timeOpen,
    required this.onToggleTime,
    required this.providerId,
    required this.onSelectProvider,
    required this.onCompare,
  });

  final String timeLabel;
  final bool timeOpen;
  final VoidCallback onToggleTime;
  final String providerId;
  final ValueChanged<String> onSelectProvider;
  final VoidCallback onCompare;

  static const _compare = '__compare__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(weatherProvidersProvider);
    final enabled = ref.watch(settingsProvider).enabledProviderIds;
    final auto = [
      for (final p in providers)
        if (enabled.contains(p.caps.providerId) && !p.caps.onDemandOnly) p,
    ];
    final current = providers
        .where((p) => p.caps.providerId == providerId)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ActionChip(
            avatar: const Icon(Icons.schedule, size: 16),
            label: Text('$timeLabel ${timeOpen ? '▴' : '▾'}'),
            tooltip: '设置时间与配速',
            onPressed: onToggleTime,
          ),
          PopupMenuButton<String>(
            tooltip: S.chooseSource,
            onSelected: (v) =>
                v == _compare ? onCompare() : onSelectProvider(v),
            itemBuilder: (_) => [
              for (final p in auto)
                CheckedPopupMenuItem(
                  value: p.caps.providerId,
                  checked: p.caps.providerId == providerId,
                  child: Text(p.caps.displayName),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _compare,
                child: Text(S.compareSources),
              ),
            ],
            child: Chip(
              avatar: const Icon(Icons.cloud_outlined, size: 16),
              label: Text(
                '${current?.caps.displayName ?? providerId} ▾',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 结论卡：沿途摘要 3 个数 + 最多 3 条提示 + 出发窗口入口。
class _ConclusionCard extends StatelessWidget {
  const _ConclusionCard({
    required this.summary,
    required this.tripMode,
    required this.dayLine,
    required this.settings,
    required this.hints,
    required this.onShowHints,
    required this.onDepartures,
  });

  final RouteWxSummary summary;
  final bool tripMode;

  /// 固定时刻模式的全天降水一行；行程模式为 null。
  final String? dayLine;
  final AppSettings settings;
  final List<WxHint> hints;
  final VoidCallback onShowHints;
  final VoidCallback onDepartures;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final sorted = [...hints]
      ..sort((a, b) => b.level.index.compareTo(a.level.index));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.routeSummary, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (!summary.hasAnyData)
              Text(
                '当前选定时间与来源没有可用数据（${summary.nodesWithData}/${summary.totalNodes} 节点有数据）。信息不足时无法给出摘要。',
                style: const TextStyle(fontSize: 12, height: 1.5),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _kv(
                      context,
                      '最低/最高温',
                      '${summary.minTempC == null ? S.notProvided : Units.temp(summary.minTempC!, imperial: settings.imperial, digits: 0)} / ${summary.maxTempC == null ? S.notProvided : Units.temp(summary.maxTempC!, imperial: settings.imperial)}',
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      context,
                      '最大阵风',
                      summary.maxGustMs == null
                          ? S.notProvided
                          : Units.windMs(
                              summary.maxGustMs!,
                              unit: settings.windUnit,
                            ),
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      context,
                      // 固定时刻只是一个小时的量，标清楚，避免当成全天。
                      tripMode ? '行程降水' : '该时次降水',
                      summary.totalPrecipMm == null
                          ? S.notProvided
                          : Units.precipMm(
                              summary.totalPrecipMm!,
                              imperial: settings.imperial,
                            ),
                    ),
                  ),
                ],
              ),
            if (dayLine != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(dayLine!, style: const TextStyle(fontSize: 13)),
              ),
            const SizedBox(height: 8),
            if (sorted.isEmpty)
              InkWell(
                onTap: onShowHints,
                child: Text(
                  S.noHintsTriggered,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final h in sorted.take(3))
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        h.level == HintLevel.warning
                            ? Icons.warning_amber_rounded
                            : Icons.info_outline,
                        size: 16,
                        color: h.level == HintLevel.warning
                            ? Colors.red
                            : h.level == HintLevel.caution
                            ? Colors.orange
                            : muted,
                      ),
                      label: Text(h.title),
                      onPressed: onShowHints,
                    ),
                  if (sorted.length > 3)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('+${sorted.length - 3}'),
                      onPressed: onShowHints,
                    ),
                ],
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.date_range),
              title: const Text('比较出发窗口'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onDepartures,
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        k,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      Text(
        v,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    super.key,
    required this.row,
    required this.index,
    required this.isLast,
    required this.tripMode,
    required this.selected,
    required this.settings,
    required this.onTap,
    required this.onDetail,
  });

  final NodeWxRow row;
  final int index;
  final bool isLast;
  final bool tripMode;
  final bool selected;
  final AppSettings settings;
  final VoidCallback onTap;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    final wp = row.node.waypoint;
    final Widget leading;
    if (wp != null) {
      leading = WaypointMarker(type: wp.type, size: 16);
    } else if (index == 0) {
      leading = const Icon(Icons.flag, size: 18, color: Color(0xFF2E7D32));
    } else if (isLast) {
      leading = const Icon(
        Icons.sports_score,
        size: 18,
        color: Color(0xFFC62828),
      );
    } else if (row.node.label == '高点') {
      leading = const Icon(Icons.terrain_outlined, size: 18);
    } else {
      leading = const Icon(Icons.circle, size: 10);
    }
    final name = row.node.label ?? '节点 ${index + 1}';
    final ele = row.node.elevationM == null
        ? ''
        : ' · ${row.node.elevationM!.toStringAsFixed(0)} m';
    final local = row.validUtc.toLocal();
    // 行程模式各节点时刻不同，时刻放最前；固定时刻全线相同，只在顶部显示一次。
    final title = tripMode
        ? '${_two(local.hour)}:${_two(local.minute)} · $name$ele'
        : '$name · ${(row.node.distFromStartM / 1000).toStringAsFixed(1)} km$ele';
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer
          .withValues(alpha: 0.3),
      leading: SizedBox(width: 24, child: Center(child: leading)),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WxBriefLine(wx: row.wx, settings: settings),
          if (wp?.stopMinutes != null)
            Text(
              '停留 ${wp!.stopMinutes} 分钟',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          if (selected)
            Text(
              S.tapAgainForDetail,
              style: TextStyle(fontSize: 11, color: muted),
            ),
        ],
      ),
      trailing: IconButton(
        tooltip: S.nodeDetail2,
        icon: const Icon(Icons.info_outline, size: 20),
        onPressed: onDetail,
      ),
      onTap: onTap,
    );
  }
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
