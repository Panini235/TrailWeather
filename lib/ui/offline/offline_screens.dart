import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/app_providers.dart';
import '../../data/offline/offline_providers.dart';
import '../../data/offline/offline_repository.dart';
import '../../data/offline/offline_trip.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/weather_models.dart';
import '../detail/weather_cells.dart';
import '../weather_refresh_clock.dart';
import '../widgets/common.dart';
import 'route_schematic.dart';

String offlineTime(DateTime t) => DateFormat('MM-dd HH:mm').format(t.toLocal());

String _coverageText(OfflineTrip trip) {
  final c = trip.coverage;
  final time = c.complete ? '所选时段均有数据' : '覆盖不全：缺少 ${c.missing} 个节点小时';
  return '$time\n温度、降水量和持续风速均有值：${c.coreVariables}/${c.expected} 个节点小时。'
      '缺失指标仍显示“此来源未提供”。';
}

const _offlineScope =
    '保存线路、航点、行程设置及此来源返回的预报。离线预报不会自动更新。'
    '不含地图底图、节点照片和实时定位导航；官方预警未接入。';

class OfflineDownloadArgs {
  const OfflineDownloadArgs({required this.plan, required this.providerId});
  final OfflineTripPlan plan;
  final String providerId;
}

class OfflineDownloadScreen extends ConsumerStatefulWidget {
  const OfflineDownloadScreen({super.key, required this.args});
  final OfflineDownloadArgs args;
  @override
  ConsumerState<OfflineDownloadScreen> createState() =>
      _OfflineDownloadScreenState();
}

class _OfflineDownloadScreenState extends ConsumerState<OfflineDownloadScreen> {
  int _hours = 72;
  bool _busy = false;
  String? _error;

  OfflineTripPlan get _plan {
    final p = widget.args.plan;
    return OfflineTripPlan(
      route: p.route,
      nodes: p.nodes,
      nodeTimesUtc: p.nodeTimesUtc,
      mode: p.mode,
      reversed: p.reversed,
      selectedTimeUtc: p.selectedTimeUtc,
      pace: p.pace,
      startUtc: p.startUtc,
      endUtc: p.startUtc.add(Duration(hours: _hours)),
    );
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final trip = await ref
          .read(offlineRepositoryProvider)
          .download(plan: _plan, providerId: widget.args.providerId);
      if (!mounted) return;
      ref.invalidate(offlineEntriesProvider);
      context.replace('/offline/${trip.id}');
    } catch (e) {
      if (mounted) setState(() => _error = _downloadError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(weatherProvidersProvider);
    final source = sources
        .where((s) => s.caps.providerId == widget.args.providerId)
        .firstOrNull;
    final supported =
        source != null && OfflineTripRepository.supportsSource(source);
    final plan = _plan;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('下载离线行程包')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              plan.route.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (plan.route.isDemo)
              const Align(alignment: Alignment.centerLeft, child: DemoBadge()),
            const SizedBox(height: 12),
            Text('天气来源：${source?.caps.displayName ?? widget.args.providerId}'),
            Text(
              '行走方向：${plan.reversed ? '反向' : '原方向'} · ${plan.nodes.length} 个采样节点',
            ),
            const SizedBox(height: 12),
            const Text('请求预报时段（设备时区）'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final h in [24, 48, 72])
                  ChoiceChip(
                    label: Text('$h 小时'),
                    selected: _hours == h,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _hours = h),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${offlineTime(plan.startUtc)} 至 ${offlineTime(plan.endUtc)}（不含结束时刻）',
            ),
            const Text('实际覆盖取决于来源；会保留来源返回的全部时次，并核对所选时段。'),
            if (plan.outsidePlanCount > 0)
              GranularityNotice(
                text: '${plan.outsidePlanCount} 个计划到达时刻超出所选时段，请增加时长或调整行程。',
              ),
            const SizedBox(height: 16),
            const GranularityNotice(text: _offlineScope),
            if (kIsWeb)
              const GranularityNotice(
                text: 'Web 仅供工程验证：受浏览器配额限制，清除站点数据会删除离线包；此功能不保证网页断网冷启动。',
              ),
            if (!supported)
              const GranularityNotice(
                text: '此来源暂未开放离线下载。请返回选择 Open-Meteo 或 MET Norway；按次计费来源不批量请求。',
              ),
            if (_error != null) _ErrorNotice(message: _error!),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || !supported ? null : _download,
              icon: Icon(
                _busy
                    ? Icons.hourglass_top
                    : Icons.download_for_offline_outlined,
              ),
              label: Text(
                _busy
                    ? '正在获取、校验并保存…'
                    : _error == null
                    ? '下载并校验'
                    : '重新下载',
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

class OfflineTripsScreen extends ConsumerWidget {
  const OfflineTripsScreen({super.key});

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    OfflineEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除离线包？'),
        content: Text(
          '将删除“${entry.trip?.plan.route.name ?? '无法读取的离线包'}”的离线副本。收藏和导入线路仍保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(offlineRepositoryProvider).delete(entry.id);
      ref.invalidate(offlineEntriesProvider);
      ref.invalidate(offlineTripProvider(entry.id));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(offlineEntriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('离线行程包')),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(offlineEntriesProvider),
            child: const Text('无法读取本机离线包，点击重试'),
          ),
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const GranularityNotice(
              text: '从本机读取，不请求天气或地图。出发前请联网更新，再关闭网络检查所需时段。卸载 App 会删除本机副本。',
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('还没有离线包。打开任意线路，点击右上角的离线下载按钮。'),
              ),
            for (final item in items)
              Card(
                child: ListTile(
                  leading: Icon(
                    item.trip == null
                        ? Icons.error_outline
                        : Icons.offline_pin_outlined,
                  ),
                  title: Text(item.trip?.plan.route.name ?? '离线包无法读取'),
                  subtitle: Text(
                    item.trip == null
                        ? item.error!
                        : '${item.trip!.plan.route.isDemo ? '演示线路 · ' : ''}${item.trip!.sourceName}\n'
                              '请求 ${item.trip!.plan.hourCount} 小时 · ${item.trip!.coverage.complete ? '时段均有数据' : '覆盖不全'}\n'
                              '获取于 ${offlineTime(item.trip!.oldestFetchedAtUtc)}',
                  ),
                  isThreeLine: true,
                  onTap: item.trip == null
                      ? null
                      : () => context.push('/offline/${item.id}'),
                  trailing: IconButton(
                    tooltip: '删除离线包',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(context, ref, item),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class OfflineTripScreen extends ConsumerStatefulWidget {
  const OfflineTripScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<OfflineTripScreen> createState() => _OfflineTripScreenState();
}

class _OfflineTripScreenState extends ConsumerState<OfflineTripScreen> {
  late final WeatherRefreshClock _clock;
  int? _hour;
  bool _usePlan = false;
  bool _updating = false;
  String? _updateMessage;

  @override
  void initState() {
    super.initState();
    final now = ref.read(weatherNowProvider);
    _clock = WeatherRefreshClock(initialUtc: now(), nowUtc: now);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  Future<void> _update(OfflineTrip trip) async {
    setState(() {
      _updating = true;
      _updateMessage = null;
    });
    try {
      await ref
          .read(offlineRepositoryProvider)
          .download(
            plan: trip.plan,
            providerId: trip.bundle.result.providerId,
            replacingId: trip.id,
          );
      if (!mounted) return;
      ref.invalidate(offlineTripProvider(widget.id));
      ref.invalidate(offlineEntriesProvider);
      setState(() => _updateMessage = '新预报已校验并保存，请检查覆盖情况。');
    } catch (e) {
      if (mounted) {
        setState(() => _updateMessage = '${_downloadError(e)}\n原有离线包仍可查看。');
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripAsync = ref.watch(offlineTripProvider(widget.id));
    return Scaffold(
      appBar: AppBar(title: const Text('离线查看')),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('离线包校验失败或无法读取。请返回列表检查存储空间，并从原线路重新下载。'),
          ),
        ),
        data: (trip) => trip == null
            ? const Center(child: Text('离线包不存在，请返回列表重新选择。'))
            : ValueListenableBuilder<DateTime>(
                valueListenable: _clock,
                builder: (context, now, _) => _content(trip, now),
              ),
      ),
    );
  }

  Widget _content(OfflineTrip trip, DateTime now) {
    final plan = trip.plan;
    final settings = ref.watch(settingsProvider);
    final suggested = now.isBefore(plan.startUtc) || !now.isBefore(plan.endUtc)
        ? plan.selectedTimeUtc
        : now;
    final selectedHour = (_hour ?? suggested.difference(plan.startUtc).inHours)
        .clamp(0, plan.hourCount - 1);
    final selected = plan.startUtc.add(Duration(hours: selectedHour));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(plan.route.name, style: Theme.of(context).textTheme.titleLarge),
        if (plan.route.isDemo)
          const Align(alignment: Alignment.centerLeft, child: DemoBadge()),
        const SizedBox(height: 8),
        const GranularityNotice(
          text: '正在读取本机保存的预报，不代表实时观测；仅点击“联网更新”才请求新预报。',
          icon: Icons.offline_pin_outlined,
        ),
        if (trip.windowEnded(now))
          const _ErrorNotice(message: '所选行程时段已结束。此包仅供回看，请为下一次行程重新下载。')
        else if (trip.needsUpdate(now))
          const _ErrorNotice(message: '旧预报：已超过来源建议的更新间隔，联网后请更新。断网时无法得知后续天气变化。'),
        Text(
          '来源：${trip.sourceName}\n预报获取于 ${offlineTime(trip.oldestFetchedAtUtc)}\n离线包保存于 ${offlineTime(trip.savedAtUtc)}',
        ),
        Text(_coverageText(trip)),
        if (plan.outsidePlanCount > 0)
          Text('${plan.outsidePlanCount} 个计划到达时刻超出请求时段；是否有数据以每个节点为准。'),
        if (trip.bundle.sharedGridNote != null)
          GranularityNotice(text: trip.bundle.sharedGridNote!),
        if (trip.modelOverlapNote != null) Text(trip.modelOverlapNote!),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _updating || trip.windowEnded(now)
              ? null
              : () => _update(trip),
          icon: const Icon(Icons.refresh),
          label: Text(_updating ? '正在更新，旧包仍可查看…' : '联网更新此包'),
        ),
        if (_updating) const LinearProgressIndicator(),
        if (_updateMessage != null) Text(_updateMessage!),
        const SizedBox(height: 12),
        Text('查看天气时刻（设备时区）', style: Theme.of(context).textTheme.titleMedium),
        if (plan.mode == OfflineTimeMode.trip)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('按计划的预计到达时刻查看'),
            subtitle: const Text('到达时间为下载时的估算，未跟随实时位置变化'),
            value: _usePlan,
            onChanged: (v) => setState(() => _usePlan = v),
          ),
        if (!_usePlan)
          Row(
            children: [
              IconButton(
                tooltip: '前一小时',
                onPressed: selectedHour == 0
                    ? null
                    : () => setState(() => _hour = selectedHour - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: selectedHour,
                  items: [
                    for (var h = 0; h < plan.hourCount; h++)
                      DropdownMenuItem(
                        value: h,
                        child: Text(
                          offlineTime(plan.startUtc.add(Duration(hours: h))),
                        ),
                      ),
                  ],
                  onChanged: (h) => setState(() => _hour = h),
                ),
              ),
              IconButton(
                tooltip: '后一小时',
                onPressed: selectedHour == plan.hourCount - 1
                    ? null
                    : () => setState(() => _hour = selectedHour + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        for (var i = 0; i < plan.nodes.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ${plan.nodes[i].describe()}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '${_usePlan ? '预计到达（估算）' : '数据有效时刻'}：${offlineTime(_usePlan ? plan.nodeTimesUtc[i] : selected)}',
                  ),
                  const SizedBox(height: 8),
                  if (trip.hourFor(
                        i,
                        _usePlan ? plan.nodeTimesUtc[i] : selected,
                      )
                      case final wx?)
                    WxVarGrid(wx: wx, settings: settings)
                  else
                    const Text('此来源未提供该时次预报，不能判断天气。'),
                  if (trip.pointFor(i) case final point?)
                    TextButton(
                      onPressed: () =>
                          _showProvenance(context, point.provenance),
                      child: const Text('查看此节点的数据来源'),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text('已保存的线路与行程设置'),
          children: [
            RouteSchematic(route: plan.route),
            Text(
              '行走方向：${plan.reversed ? '反向' : '原方向'}\n'
              '${plan.mode == OfflineTimeMode.trip ? '计划出发' : '选定时刻'}：${offlineTime(plan.selectedTimeUtc)}',
            ),
            if (plan.mode == OfflineTimeMode.trip)
              Text(plan.pace.assumptionNotes().join('\n')),
            if (!plan.route.analysisPath.coversAllSegments)
              const Text('天气节点与预计到达仅覆盖最长连续路径；其余轨迹段已保存。'),
            for (final wp in plan.route.waypoints)
              ListTile(
                title: Text(wp.name),
                subtitle: Text(
                  '${wp.point.latitude.toStringAsFixed(5)}, ${wp.point.longitude.toStringAsFixed(5)}'
                  '${wp.stopMinutes == null ? '' : ' · 停留 ${wp.stopMinutes} 分钟'}',
                ),
              ),
            Text(
              '线路来源：${plan.route.sourceName}\n授权说明：${plan.route.sourceLicense ?? '未提供'}',
            ),
          ],
        ),
        const GranularityNotice(text: _offlineScope),
      ],
    );
  }
}

void _showProvenance(BuildContext context, WxProvenance provenance) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text(provenance.granularityStatement()),
            for (final e in provenance.toDisplayMap().entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('${e.key}：${e.value}'),
              ),
          ],
        ),
      ),
    ),
  );
}

String _downloadError(Object e) => e is StateError
    ? e.message.toString()
    : '下载或保存失败。请检查网络、来源配置和剩余空间，然后重试；未将此次失败标记为离线就绪。';

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );
}
