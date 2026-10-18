import 'dart:async' show Timer;

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
import '../../data/map/tile_sources.dart';
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
import '../widgets/rolling_text.dart';
import '../map/basemap.dart';
import '../map/map_layers_ui.dart';
import '../map/route_camera.dart';
import '../map/route_marks.dart';
import '../map/terrain_layer.dart';
import '../motion.dart';
import 'detail_state.dart';
import 'route_3d_page.dart';
import 'layering_card.dart';
import '../share/share_cards.dart';
import '../share/share_graphics.dart' show hintIcon;
import '../share/share_image.dart';
import 'node_detail_view.dart';
import 'node_photos.dart';
import 'node_wx_style.dart';
import 'ridge_band.dart';
import 'weather_cells.dart';
import '../tokens.dart';

part 'detail_controls.dart';
part 'detail_map.dart';
part 'detail_sections.dart';

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

  /// 时间线折叠：上次构建的条目与折叠行的 key（按条目首节点下标）。
  List<TimelineEntry> _timeline = const [];
  final Map<int, GlobalKey> _foldKeys = {};

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
      // 节点被折叠时滚到它所在的折叠行（不自动展开，避免拖动剖面时列表跳动）。
      final fold = _timeline.where((e) => e.folded.contains(i)).firstOrNull;
      final ctx =
          _tileKeys[i]?.currentContext ??
          (fold == null ? null : _foldKeys[fold.index]?.currentContext);
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
      _foldKeys.clear(); // 新 key：折叠行回到收起状态
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
    // 山脊天气带：行程模式标出预计到达时刻与日落后的路段。
    final nightFrom = sunset == null
        ? null
        : etas.indexWhere((e) => e.isAfter(sunset));

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
              sunriseUtc: tripMode
                  ? rows.firstOrNull?.point?.sunriseNear(etas.first)
                  : null,
              sunsetUtc: sunset,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            tooltip: S.detailDownloadOffline,
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
          if (rows.firstOrNull?.wx case final wx?) WeatherHourNotice(wx: wx),
          if (bundleAsync.isLoading && !bundleAsync.hasValue)
            const LinearProgressIndicator(
              semanticsLabel: S.detailLoadingWeather,
            )
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
              modeLabel: tripMode
                  ? S.detailModeTrip(_clock(etas.first), _clock(etas.last))
                  : S.detailModeFixed(_clock(query.fixedUtc)),
              onSwitchToTrip: _mode == TimeMode.fixed ? _switchToTrip : null,
            ),
          if (!bundleAsync.hasError && rows.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            RidgeWeatherBand(
              route: route,
              rows: rows,
              selectedIndex: _selectedNode,
              onTapNode: _select,
              etaLabels: tripMode
                  ? [
                      for (final e in etas)
                        '${_two(e.toLocal().hour)}:${_two(e.toLocal().minute)}',
                    ]
                  : null,
              nightFromIndex: nightFrom == null || nightFrom < 0
                  ? null
                  : nightFrom,
            ),
            const SizedBox(height: Space.sm),
            // 准备层：穿什么、带什么（决策层之后、地图之前）。
            LayeringCard(
              rows: rows,
              sunriseUtc: tripMode
                  ? rows.first.point?.sunriseNear(etas.first)
                  : null,
              sunsetUtc: sunset,
            ),
          ],
          const SizedBox(height: 8),
          // 第二层：地图 + 线路要点 + 沿途节点。
          _RouteMiniMap(
            route: route,
            rows: rows,
            selectedIndex: _selectedNode,
            // 与节点列表一致：第一次点选中，再点打开节点详情；不滚走页面。
            onTapNode: (i) => _selectedNode == i
                ? _showNodeSheet(rows, settings, initialIndex: i)
                : _select(i),
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
    DateTime? sunriseUtc,
    DateTime? sunsetUtc,
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
    Widget card(ShareLayout layout) => RouteShareCard(
      layout: layout,
      route: route,
      tripMode: _mode == TimeMode.trip,
      reversed: _reversed,
      summary: summarizeRows(rows),
      dayPrecip: _mode == TimeMode.fixed
          ? summarizeDayPrecip(
              points: bundle.result.points,
              dayStartUtc: DateTime(_date.year, _date.month, _date.day).toUtc(),
            )
          : null,
      hints: hints,
      rows: rows,
      settings: settings,
      sourceName: source?.caps.displayName ?? _providerId,
      fetchedAtUtc: bundle.result.fetchedAtUtc,
      sunriseUtc: sunriseUtc,
      sunsetUtc: sunsetUtc,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SharePreviewPage(
          title: S.shareImage,
          fileName:
              'shanqing-${day.year}${_two(day.month)}${_two(day.day)}.png',
          shareText: S.detailShareText(route.name, timeLabel),
          card: card(ShareLayout.full),
          // 固定时刻是“全线同一小时”的快照：分享前提醒一次，并给出改按行程看的入口。
          notice: _mode == TimeMode.fixed
              ? ShareModeNotice(
                  text: S.shareFixedModeNotice(_clock(query.fixedUtc)),
                  actionLabel: S.detailSwitchToTrip,
                  onAction: () {
                    Navigator.of(context).pop();
                    _switchToTrip();
                  },
                )
              : null,
          variants: [
            for (final l in ShareLayout.values)
              ShareVariant(
                label: l.label,
                icon: l.icon,
                card: card(l),
                fileSuffix: l.name,
              ),
          ],
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
    );
    final head = S.detailDayHead(day.month, day.day);
    if (d.maxDayMm == null) return S.detailDayNoPrecip(head);
    final partial = d.minHoursCovered < 24
        ? S.detailDayPartial(d.minHoursCovered)
        : '';
    final prob = d.maxProb == null
        ? ''
        : S.detailDayMaxProb(d.maxProb!.toStringAsFixed(0));
    if (d.firstWetUtc == null) {
      return S.detailDayDry(head, prob, partial);
    }
    final a = d.firstWetUtc!.toLocal();
    final b = d.lastWetUtc!.toLocal().add(const Duration(hours: 1));
    return S.detailDayWet(
      head: head,
      amount: Units.precipMm(d.maxDayMm!, imperial: settings.imperial),
      from: _two(a.hour),
      to: _two(b.hour == 0 ? 24 : b.hour),
      prob: prob,
      partial: partial,
    );
  }

  /// 本地 HH:mm。
  String _clock(DateTime utc) {
    final l = utc.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}';
  }

  /// 从固定时刻切到行程模式（同一天，默认出发时刻），并展开时间设置方便改出发时间。
  void _switchToTrip() => setState(() {
    _mode = TimeMode.trip;
    _timeOpen = true;
    _selectedNode = null;
  });

  /// 顶部时间标签：固定时刻显示“固定 M/d HH:00”，行程模式显示“出发 M/d HH:mm”（设备时区）。
  String _timeChipLabel(DateTime utc) {
    final l = utc.toLocal();
    final t = '${l.month}/${l.day} ${_two(l.hour)}:${_two(l.minute)}';
    return _mode == TimeMode.trip ? S.detailChipTrip(t) : S.detailChipFixed(t);
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
                S.detailHintBasis(h.basis),
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
          title: S.detailSourceFailed(provider.caps.displayName),
          detail: S.detailSourceFailedDetail(err.toString()),
          onRetry: () => ref.invalidate(
            detailWeatherProvider(DetailFetchKey(nodes: nodes, query: query)),
          ),
        ),
      ];
    }

    final bundle = bundleAsync.value;
    final tripMode = _mode == TimeMode.trip && etas.isNotEmpty;
    final timeline = _timeline = foldTimeline(rows);
    // 说明类文字统一收进底部“数据说明与来源”，不再逐条铺在沿途内容之间。
    final notes = <String>[
      if (timeline.any((e) => e.folded.isNotEmpty)) S.foldedNote,
      if (rows.any((r) => r.node.nearbyWaypoints.isNotEmpty)) S.nearbyMarksNote,
      if (!route.analysisPath.coversAllSegments) S.multiSegmentNote,
      if (_reversed) S.reversedNote,
      if (route.origin == RouteOrigin.planet) S.planetElevationNote,
      if (tripMode &&
          etas.length > 1 &&
          etas.last.difference(etas.first) > const Duration(hours: 12))
        S.longTripNote,
      if (route.totalAscentM == null) S.noElevation,
      if (tripMode) sunsetKnown ? S.detailSunsetNote : S.detailSunsetMissing,
      S.detailTimeZoneNote,
    ];

    Widget tile(int i) => _NodeTile(
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
    );

    return [
      const SizedBox(height: 4),
      Text(S.weatherAlongRoute, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      for (final e in timeline) ...[
        tile(e.index),
        if (e.folded.isNotEmpty)
          _FoldedRun(
            key: _foldKeys.putIfAbsent(e.index, GlobalKey.new),
            rows: [for (final i in e.folded) rows[i]],
            tripMode: tripMode,
            containsSelected: e.folded.contains(_selectedNode),
            lowPower: settings.lowPower,
            buildTiles: () => [for (final i in e.folded) tile(i)],
          ),
      ],
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
