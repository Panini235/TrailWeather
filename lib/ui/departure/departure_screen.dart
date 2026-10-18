import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_providers.dart';
import '../../data/routes/route_models.dart';
import '../../data/routes/route_sampling.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/departure_provider.dart';
import '../../data/weather/departure_windows.dart';
import '../../data/weather/eta.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/weather_repository.dart';
import '../weather_refresh_clock.dart';
import '../share/share_cards.dart';
import '../share/share_image.dart';
import 'departure_threshold_screen.dart';
import '../strings.dart';
import '../tokens.dart';

class DepartureArgs {
  DepartureArgs({
    required this.route,
    required List<RouteNode> nodes,
    required this.pace,
    required this.providerId,
    required this.initialDate,
    required this.reversed,
  }) : nodes = List.unmodifiable(nodes);
  final HikingRoute route;
  final List<RouteNode> nodes;
  final PaceConfig pace;
  final String providerId;
  final DateTime initialDate;
  final bool reversed;
}

class DepartureSelection {
  const DepartureSelection(this.startUtc, this.providerId);
  final DateTime startUtc;
  final String providerId;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _time(DateTime d) =>
    '${_two(d.toLocal().hour)}:${_two(d.toLocal().minute)}';
String _date(DateTime d) {
  final l = d.toLocal();
  return '${l.year}-${_two(l.month)}-${_two(l.day)}';
}

String _stamp(DateTime d) => '${_date(d)} ${_time(d)}';
String _name(WxVar v) => switch (v) {
  WxVar.temperature => S.departureVarTemp,
  WxVar.windGust => S.departureVarGust,
  WxVar.precip => S.departureVarPrecip,
  _ => v.name,
};
String _value(WxVar v, double? n) => n == null
    ? S.notProvided
    : '${n.toStringAsFixed(1)} ${switch (v) {
        WxVar.temperature => '℃',
        WxVar.windGust => 'm/s',
        _ => 'mm',
      }}';

class DepartureScreen extends ConsumerStatefulWidget {
  const DepartureScreen({super.key, required this.args});
  final DepartureArgs args;
  @override
  ConsumerState<DepartureScreen> createState() => _DepartureScreenState();
}

class _DepartureScreenState extends ConsumerState<DepartureScreen> {
  late DateTime _first;
  int _days = 3;
  TimeOfDay _firstSlot = const TimeOfDay(hour: 7, minute: 0);
  late String _providerId = widget.args.providerId;
  int _refresh = 0;
  DepartureFetchKey? _key;
  late final WeatherRefreshClock _clock;

  @override
  void initState() {
    super.initState();
    final now = ref.read(weatherNowProvider)().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final proposed = widget.args.initialDate.toLocal();
    _first = proposed.isBefore(today)
        ? today
        : DateTime(proposed.year, proposed.month, proposed.day);
    _clock = WeatherRefreshClock(
      initialUtc: now.toUtc(),
      nowUtc: ref.read(weatherNowProvider),
    );
    _clock.addListener(_tick);
  }

  void _tick() {
    if (_key != null) ref.invalidate(departureWeatherProvider(_key!));
    setState(() {});
  }

  @override
  void dispose() {
    _clock.removeListener(_tick);
    _clock.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = ref.read(weatherNowProvider)().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final last = DateTime(today.year, today.month, today.day + 15);
    final picked = await showDatePicker(
      context: context,
      initialDate: _first.isBefore(today)
          ? today
          : (_first.isAfter(last) ? last : _first),
      firstDate: today,
      lastDate: last,
    );
    if (picked != null && mounted) setState(() => _first = picked);
  }

  Future<void> _inspect(
    DepartureAssessment assessment,
    String providerId,
  ) async {
    final applied = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            _DepartureEvidence(args: widget.args, assessment: assessment),
      ),
    );
    if (applied == true && mounted) {
      // 详情可能停留很久，返回时再次检查日期，避免应用已过时出发。
      if (assessment.startUtc.isBefore(ref.read(weatherNowProvider)())) {
        setState(() {});
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.departurePastSnack)));
      } else {
        context.pop(DepartureSelection(assessment.startUtc, providerId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final settings = ref.watch(settingsProvider);
    final sources = ref
        .watch(weatherProvidersProvider)
        .where(
          (p) =>
              !p.caps.onDemandOnly &&
              (settings.enabledProviderIds.contains(p.caps.providerId) ||
                  p.caps.providerId == args.providerId),
        )
        .toList();
    final source =
        sources.where((p) => p.caps.providerId == _providerId).firstOrNull ??
        sources.firstOrNull;
    final now = ref.read(weatherNowProvider)().toUtc();
    final slots = [
      for (var i = 0; i < 5; i++)
        if (_firstSlot.hour + i * 2 < 24)
          TimeOfDay(hour: _firstSlot.hour + i * 2, minute: _firstSlot.minute),
    ];
    final dates = [
      for (var i = 0; i < _days; i++)
        DateTime(_first.year, _first.month, _first.day + i),
    ];
    DateTime departure(DateTime d, TimeOfDay t) =>
        DateTime(d.year, d.month, d.day, t.hour, t.minute).toUtc();
    final starts = [
      for (final d in dates)
        for (final t in slots) departure(d, t),
    ];
    final future = starts.where((s) => !s.isBefore(now)).toList();
    final base = DateTime.utc(2026);
    final offsets = computeEtas(
      nodes: args.nodes,
      startUtc: base,
      pace: args.pace,
    );
    final duration = offsets.isEmpty
        ? Duration.zero
        : offsets.last.difference(base);
    final supported =
        args.nodes.isNotEmpty && duration <= const Duration(hours: 24);
    final key = source == null || future.isEmpty || !supported
        ? null
        : DepartureFetchKey(
            nodes: args.nodes,
            providerId: source.caps.providerId,
            startUtc: departureHour(future.first),
            // 多取末尾一小时，保留 Open-Meteo 上一小时累计/最大值的原始时次。
            endUtc: departureHour(future.last.add(duration))
                .add(const Duration(hours: 2)),
            refresh: _refresh,
          );
    _key = key;
    final async = key == null ? null : ref.watch(departureWeatherProvider(key));
    final bundle = async?.value;
    final t = settings.departureThresholds;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final explain = <String>[
      S.departureExplainCompare,
      S.departureExplainSlots,
      S.departureExplainColors,
      S.departureExplainThresholds(
        t.gustYellow,
        t.gustRed,
        t.precipYellow,
        t.coldRed,
      ),
      S.departureExplainMethod,
      if (source != null)
        S.departureSingleSource(
          source.caps.modelOrNetwork,
          source.caps.forecastHorizonDays,
        ),
      ?source?.caps.modelOverlapNote,
      ?bundle?.sharedGridNote,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.departureTitle),
        actions: [
          IconButton(
            tooltip: S.shareImage,
            icon: const Icon(Icons.ios_share),
            onPressed: bundle == null || source == null || !supported
                ? null
                : () => _openShare(
                    dates: dates,
                    slots: slots,
                    now: now,
                    bundle: bundle,
                    thresholds: t,
                    sourceName: source.caps.displayName,
                    durationHours: duration.inMinutes / 60,
                    departure: departure,
                  ),
          ),
          IconButton(
            tooltip: S.departureRulesTitle,
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showExplain(explain),
          ),
          IconButton(
            tooltip: S.departureRefreshTooltip,
            onPressed:
                key == null ||
                    async?.isLoading == true ||
                    bundle?.result.refreshing == true
                ? null
                : () => setState(() => _refresh++),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            '${args.route.isDemo ? S.departureDemoPrefix : ''}${args.route.name}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            S.departureDirectionDuration(
              args.reversed ? S.reverseRoute : S.departureForward,
              (duration.inMinutes / 60).toStringAsFixed(1),
            ),
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 8),
          // 控件一行：起始日期 / 天数 / 首个时刻 / 来源。
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(S.departureFromDate(_date(_first))),
              ),
              DropdownButton<int>(
                value: _days,
                items: [
                  for (final n in [1, 3, 5])
                    DropdownMenuItem(value: n, child: Text(S.departureDays(n))),
                ],
                onChanged: (n) {
                  if (n != null) setState(() => _days = n);
                },
              ),
              OutlinedButton(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _firstSlot,
                  );
                  if (picked != null && mounted) {
                    setState(() => _firstSlot = picked);
                  }
                },
                child: Text(
                  S.departureFirstSlot(
                    '${_two(_firstSlot.hour)}:${_two(_firstSlot.minute)}',
                  ),
                ),
              ),
            ],
          ),
          if (source != null && sources.length > 1)
            DropdownButton<String>(
              isExpanded: true,
              value: source.caps.providerId,
              items: [
                for (final p in sources)
                  DropdownMenuItem(
                    value: p.caps.providerId,
                    child: Text(
                      p.caps.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) {
                if (id != null) setState(() => _providerId = id);
              },
            ),
          if (!supported)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(S.departureUnsupported),
            ),
          if (source == null) const Text(S.departureNoSource),
          if (async?.isLoading == true || bundle?.result.refreshing == true)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(
                semanticsLabel: S.departureLoadingSemantics,
              ),
            ),
          if (async?.hasError == true) ...[
            const Text(S.departureFetchError),
            TextButton(
              onPressed: () => setState(() => _refresh++),
              child: const Text(S.departureRetry),
            ),
          ],
          if (supported && (bundle != null || future.isEmpty)) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: FixedColumnWidth(
                  60 * MediaQuery.textScalerOf(context).scale(1),
                ),
                columnWidths: {
                  0: FixedColumnWidth(
                    64 * MediaQuery.textScalerOf(context).scale(1),
                  ),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    children: [
                      const SizedBox.shrink(),
                      for (final slot in slots)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${_two(slot.hour)}:${_two(slot.minute)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                    ],
                  ),
                  for (final day in dates)
                    TableRow(
                      children: [
                        Text(
                          _dayLabel(day),
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                        for (final slot in slots)
                          _cell(
                            departure(day, slot),
                            now,
                            bundle,
                            settings.departureThresholds,
                            source?.caps.providerId,
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              S.departureLegend,
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
          if (bundle != null) ...[
            const SizedBox(height: 8),
            Text(
              S.departureFetchedAt(
                bundle.result.stale
                    ? S.departureStale
                    : bundle.result.fromCache
                    ? S.departureCached
                    : S.departureFetched,
                _stamp(bundle.result.fetchedAtUtc),
              ),
              style: TextStyle(fontSize: 12, color: muted),
            ),
            if (bundle.result.refreshFailed)
              const Text(S.departureRefreshFailed),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DepartureThresholdScreen(),
                ),
              ),
              icon: const Icon(Icons.tune),
              label: const Text(S.departureAdjustThresholds),
            ),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(S.departureRulesTitle),
            children: [
              for (final e in explain)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    e,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              for (final note in args.pace.assumptionNotes())
                Text('· $note', style: const TextStyle(fontSize: 12)),
              const Text(S.departureSunsetNote, style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  /// 分享图：多日出发窗口对比卡（格子判定与屏幕相同，来源与阈值写在页脚）。
  void _openShare({
    required List<DateTime> dates,
    required List<TimeOfDay> slots,
    required DateTime now,
    required RouteWeatherBundle bundle,
    required DepartureThresholds thresholds,
    required String sourceName,
    required double durationHours,
    required DateTime Function(DateTime, TimeOfDay) departure,
  }) {
    final args = widget.args;
    final starts = [
      for (final d in dates) [for (final s in slots) departure(d, s)],
    ];
    final cells = [
      for (final row in starts)
        [
          for (final st in row)
            if (st.isBefore(now))
              const DepartureShareCell.past()
            else
              () {
                final a = assessDeparture(
                  nodes: args.nodes,
                  startUtc: st,
                  pace: args.pace,
                  bundle: bundle,
                  thresholds: thresholds,
                );
                return DepartureShareCell(
                  departureGlyphs(a),
                  a.level,
                  a.insufficient,
                );
              }(),
        ],
    ];
    final t = thresholds;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SharePreviewPage(
          title: S.departureShareTitle,
          fileName: 'shanqing-departures-${_date(dates.first)}.png',
          shareText: S.departureShareText(args.route.name),
          card: DepartureShareCard(
            routeName: args.route.name,
            isDemo: args.route.isDemo,
            reversed: args.reversed,
            durationHours: durationHours,
            dayLabels: [
              for (final d in dates) _dayLabel(d).replaceAll('\n', ' '),
            ],
            dates: dates,
            slotLabels: [
              for (final s in slots) '${_two(s.hour)}:${_two(s.minute)}',
            ],
            cells: cells,
            startsUtc: starts,
            sourceName: sourceName,
            fetchedAtUtc: bundle.result.fetchedAtUtc,
            thresholdText: S.departureShareThresholds(
              t.gustYellow,
              t.gustRed,
              t.precipYellow,
              t.coldRed,
            ),
          ),
        ),
      ),
    );
  }

  void _showExplain(List<String> lines) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              S.departureRulesTitle,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final e in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  e,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 行标签：今天 / 明天 / 周几 + 月日，比完整日期更易扫读。
  String _dayLabel(DateTime day) {
    final now = ref.read(weatherNowProvider)().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(day.year, day.month, day.day);
    final diff = d.difference(today).inDays;
    final head = switch (diff) {
      0 => S.today,
      1 => S.tomorrow,
      _ => S.departureWeekday(d.weekday),
    };
    return '$head\n${d.month}/${d.day}';
  }

  Widget _cell(
    DateTime start,
    DateTime now,
    RouteWeatherBundle? bundle,
    DepartureThresholds thresholds,
    String? providerId,
  ) {
    final colors = Theme.of(context).colorScheme;
    Widget box(String text, Color bg, Color fg, {String? tip}) => Padding(
      padding: const EdgeInsets.all(2),
      child: Tooltip(
        message: tip ?? text,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(text, style: TextStyle(color: fg, fontSize: 13)),
        ),
      ),
    );
    if (start.isBefore(now)) {
      return box(
        S.departureGlyphPast,
        colors.surfaceContainerHighest.withValues(alpha: 0.5),
        colors.onSurfaceVariant,
        tip: S.departureTipPast,
      );
    }
    if (bundle == null || providerId == null) {
      return box(
        S.departureGlyphMissing,
        colors.surfaceContainerHighest,
        colors.onSurface,
        tip: S.departureTipInsufficient,
      );
    }
    final a = assessDeparture(
      nodes: widget.args.nodes,
      startUtc: start,
      pace: widget.args.pace,
      bundle: bundle,
      thresholds: thresholds,
    );
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (background, foreground) = switch (a.level) {
      DepartureLevel.red => (colors.errorContainer, colors.onErrorContainer),
      DepartureLevel.yellow => (
        dark ? Semantic.cautionContainerDark : Semantic.cautionContainerLight,
        SemanticInk.caution(context),
      ),
      DepartureLevel.none =>
        a.insufficient
            ? (colors.surfaceContainerHighest, colors.onSurface)
            : (colors.primaryContainer, colors.onPrimaryContainer),
    };
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        label: S.departureCellSemantics(
          _stamp(start),
          a.label,
          _stamp(a.finishUtc),
        ),
        child: Tooltip(
          message: S.departureCellTooltip(a.label, _time(a.finishUtc)),
          child: TextButton(
            key: ValueKey('departure-${start.toIso8601String()}'),
            style: TextButton.styleFrom(
              backgroundColor: background,
              foregroundColor: foreground,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () => _inspect(a, providerId),
            child: Text(
              departureGlyphs(a),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

/// 格子里的原因字：风 / 雨 / 冷 / 晚（日落），信息不足加“缺”，都未触发为“✓”。
/// 最多显示 2 个原因字，完整原因在依据页。
String departureGlyphs(DepartureAssessment a) {
  final glyphs = <String>[];
  for (final f in a.findings) {
    final g = switch (f.variable) {
      WxVar.windGust => S.departureGlyphWind,
      WxVar.precip => S.departureGlyphRain,
      WxVar.temperature => S.departureGlyphCold,
      _ => f.sunsetUtc != null ? S.departureGlyphLate : '!',
    };
    if (!glyphs.contains(g)) glyphs.add(g);
  }
  final shown = glyphs.take(2).toList();
  if (a.insufficient) shown.add(S.departureGlyphMissing);
  return shown.isEmpty ? '✓' : shown.join('');
}

class _DepartureEvidence extends ConsumerWidget {
  const _DepartureEvidence({required this.args, required this.assessment});
  final DepartureArgs args;
  final DepartureAssessment assessment;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = assessment;
    final past = a.startUtc.isBefore(ref.read(weatherNowProvider)());
    return Scaffold(
      appBar: AppBar(title: const Text(S.departureEvidenceTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(a.label, style: Theme.of(context).textTheme.headlineSmall),
          Text(
            S.departureEvidenceTimes(_stamp(a.startUtc), _stamp(a.finishUtc)),
          ),
          Text(
            S.departureEvidenceSource(
              a.bundle.result.providerId,
              _stamp(a.bundle.result.fetchedAtUtc),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: past ? null : () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.schedule),
            label: Text(past ? S.departurePast : S.departureUseThis),
          ),
          const SizedBox(height: 12),
          for (final finding in a.findings)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      finding.reason,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (finding.sample != null) ...[
                      Text(
                        S.departureNodePassHour(
                          args.nodes[finding.sample!.nodeIndex].describe(),
                          _stamp(finding.sample!.hourUtc),
                        ),
                      ),
                      Text(
                        S.departureRawValidTime(
                          _stamp(
                            finding.sample!.sourceTimesUtc[finding.variable]!,
                          ),
                        ),
                      ),
                      Text(
                        S.departureModel(
                          finding.sample!.point!.provenance.modelKnown
                              ? finding.sample!.point!.provenance.modelOrNetwork
                              : S.departureModelUnknown(
                                  finding
                                      .sample!
                                      .point!
                                      .provenance
                                      .modelOrNetwork,
                                ),
                        ),
                      ),
                    ],
                    if (finding.sunsetUtc != null)
                      Text(S.departureSunset(_stamp(finding.sunsetUtc!))),
                  ],
                ),
              ),
            ),
          if (a.findings.isEmpty) const Text(S.departureNoFindings),
          for (final gap in a.gaps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(S.departureGap(gap)),
            ),
          for (final e in a.missingValues.entries)
            if (e.value > 0) Text(S.departureMissing(_name(e.key), e.value)),
          Text(
            S.departureSampleSummary(
              a.samples.where((s) => s.complete).length,
              a.samples.length,
            ),
          ),
          if (a.bundle.sharedGridNote != null) Text(a.bundle.sharedGridNote!),
          const SizedBox(height: 12),
          const Text(
            S.departureNodesTitle,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (a.bundle.result.providerId.startsWith('open-meteo:'))
            const Text(S.departureOpenMeteoNote),
          for (var i = 0; i < args.nodes.length; i++)
            ExpansionTile(
              key: ValueKey('departure-node-$i'),
              title: Text(args.nodes[i].describe()),
              subtitle: Text(S.departureNodeEta(_stamp(a.etasUtc[i]))),
              children: [
                if (departurePoint(a.bundle, i) case final p?)
                  _provenance(p.provenance),
                for (final s in a.samples.where((s) => s.nodeIndex == i))
                  ListTile(
                    title: Text(
                      '${s.instantOnly ? S.departureArrivalHour : S.departurePassingHour} ${_stamp(s.hourUtc)}',
                    ),
                    subtitle: Text(
                      [
                        for (final v in s.sourceTimesUtc.keys)
                          S.departureSampleLine(
                            _name(v),
                            _value(v, s.values[v]),
                            _stamp(s.sourceTimesUtc[v]!),
                          ),
                      ].join('\n'),
                    ),
                  ),
              ],
            ),
          const Text(S.departureFootnote),
        ],
      ),
    );
  }

  Widget _provenance(WxProvenance p) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in p.toDisplayMap().entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${e.key}：${e.value}'),
          ),
      ],
    ),
  );
}
