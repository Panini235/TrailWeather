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
import '../strings.dart';

String offlineTime(DateTime t) => DateFormat('MM-dd HH:mm').format(t.toLocal());

String _coverageText(OfflineTrip trip) {
  final c = trip.coverage;
  final time = c.complete
      ? S.offlineCoverageComplete
      : S.offlineCoverageMissing(c.missing);
  return S.offlineCoverageText(time, c.coreVariables, c.expected);
}

const _offlineScope = S.offlineScope;

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
        appBar: AppBar(title: const Text(S.offlineDownloadTitle)),
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
            Text(
              S.offlineWeatherSource(
                source?.caps.displayName ?? widget.args.providerId,
              ),
            ),
            Text(S.offlineDirectionNodes(plan.reversed, plan.nodes.length)),
            const SizedBox(height: 12),
            const Text(S.offlineRequestRange),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final h in [24, 48, 72])
                  ChoiceChip(
                    label: Text(S.offlineHours(h)),
                    selected: _hours == h,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _hours = h),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              S.offlineRangeText(
                offlineTime(plan.startUtc),
                offlineTime(plan.endUtc),
              ),
            ),
            const Text(S.offlineCoverageNote),
            if (plan.outsidePlanCount > 0)
              GranularityNotice(
                text: S.offlineOutsideSelected(plan.outsidePlanCount),
              ),
            const SizedBox(height: 16),
            const GranularityNotice(text: _offlineScope),
            if (kIsWeb) const GranularityNotice(text: S.offlineWebNote),
            if (!supported)
              const GranularityNotice(text: S.offlineSourceUnsupported),
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
                    ? S.offlineDownloading
                    : _error == null
                    ? S.offlineDownload
                    : S.offlineRedownload,
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
        title: const Text(S.offlineDeleteTitle),
        content: Text(
          S.offlineDeleteBody(
            entry.trip?.plan.route.name ?? S.offlineUnreadableName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.delete),
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
            .showSnackBar(const SnackBar(content: Text(S.offlineDeleteFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(offlineEntriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.offlineTripsTitle)),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(offlineEntriesProvider),
            child: const Text(S.offlineListLoadFailed),
          ),
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const GranularityNotice(text: S.offlineListNote),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(S.offlineListEmpty),
              ),
            for (final item in items)
              Card(
                child: ListTile(
                  leading: Icon(
                    item.trip == null
                        ? Icons.error_outline
                        : Icons.offline_pin_outlined,
                  ),
                  title: Text(
                    item.trip?.plan.route.name ?? S.offlineEntryUnreadable,
                  ),
                  subtitle: Text(
                    item.trip == null
                        ? item.error!
                        : S.offlineEntrySubtitle(
                            demo: item.trip!.plan.route.isDemo,
                            source: item.trip!.sourceName,
                            hours: item.trip!.plan.hourCount,
                            complete: item.trip!.coverage.complete,
                            fetched: offlineTime(item.trip!.oldestFetchedAtUtc),
                          ),
                  ),
                  isThreeLine: true,
                  onTap: item.trip == null
                      ? null
                      : () => context.push('/offline/${item.id}'),
                  trailing: IconButton(
                    tooltip: S.offlineDeleteTooltip,
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
      setState(() => _updateMessage = S.offlineUpdated);
    } catch (e) {
      if (mounted) {
        setState(
          () => _updateMessage = S.offlineUpdateFailed(_downloadError(e)),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripAsync = ref.watch(offlineTripProvider(widget.id));
    return Scaffold(
      appBar: AppBar(title: const Text(S.offlineViewTitle)),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(S.offlineTripLoadFailed),
          ),
        ),
        data: (trip) => trip == null
            ? const Center(child: Text(S.offlineTripMissing))
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
          text: S.offlineReadingNote,
          icon: Icons.offline_pin_outlined,
        ),
        if (trip.windowEnded(now))
          const _ErrorNotice(message: S.offlineWindowEnded)
        else if (trip.needsUpdate(now))
          const _ErrorNotice(message: S.offlineNeedsUpdate),
        Text(
          S.offlineTripMeta(
            trip.sourceName,
            offlineTime(trip.oldestFetchedAtUtc),
            offlineTime(trip.savedAtUtc),
          ),
        ),
        Text(_coverageText(trip)),
        if (plan.outsidePlanCount > 0)
          Text(S.offlineOutsideRequested(plan.outsidePlanCount)),
        if (trip.bundle.sharedGridNote != null)
          GranularityNotice(text: trip.bundle.sharedGridNote!),
        if (trip.modelOverlapNote != null) Text(trip.modelOverlapNote!),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _updating || trip.windowEnded(now)
              ? null
              : () => _update(trip),
          icon: const Icon(Icons.refresh),
          label: Text(_updating ? S.offlineUpdating : S.offlineUpdate),
        ),
        if (_updating) const LinearProgressIndicator(),
        if (_updateMessage != null) Text(_updateMessage!),
        const SizedBox(height: 12),
        Text(S.offlineViewTime, style: Theme.of(context).textTheme.titleMedium),
        if (plan.mode == OfflineTimeMode.trip)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(S.offlineUsePlan),
            subtitle: const Text(S.offlineUsePlanNote),
            value: _usePlan,
            onChanged: (v) => setState(() => _usePlan = v),
          ),
        if (!_usePlan)
          Row(
            children: [
              IconButton(
                tooltip: S.offlinePrevHour,
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
                tooltip: S.offlineNextHour,
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
                    S.offlineNodeTime(
                      _usePlan,
                      offlineTime(_usePlan ? plan.nodeTimesUtc[i] : selected),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (trip.hourFor(
                        i,
                        _usePlan ? plan.nodeTimesUtc[i] : selected,
                      )
                      case final wx?)
                    WxVarGrid(wx: wx, settings: settings)
                  else
                    const Text(S.offlineHourMissing),
                  if (trip.pointFor(i) case final point?)
                    TextButton(
                      onPressed: () =>
                          _showProvenance(context, point.provenance),
                      child: const Text(S.offlineViewProvenance),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text(S.offlineSavedSettings),
          children: [
            RouteSchematic(route: plan.route),
            Text(
              S.offlineSavedPlan(
                plan.reversed,
                plan.mode == OfflineTimeMode.trip,
                offlineTime(plan.selectedTimeUtc),
              ),
            ),
            if (plan.mode == OfflineTimeMode.trip)
              Text(plan.pace.assumptionNotes().join('\n')),
            if (!plan.route.analysisPath.coversAllSegments)
              const Text(S.offlinePartialPath),
            for (final wp in plan.route.waypoints)
              ListTile(
                title: Text(wp.name),
                subtitle: Text(
                  '${wp.point.latitude.toStringAsFixed(5)}, ${wp.point.longitude.toStringAsFixed(5)}'
                  '${wp.stopMinutes == null ? '' : S.offlineStopMinutes(wp.stopMinutes!)}',
                ),
              ),
            Text(
              S.offlineRouteSource(
                plan.route.sourceName,
                plan.route.sourceLicense,
              ),
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

String _downloadError(Object e) =>
    e is StateError ? e.message.toString() : S.offlineDownloadFailed;

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
