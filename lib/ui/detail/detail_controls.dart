part of 'route_detail_screen.dart';

// 详情页：控制条、时间设置与线路要点。

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
      route.isLoop ? S.loopRoute : S.detailDirection(reversed: reversed),
    ].join(' · ');
    return Row(
      children: [
        Expanded(child: Text(facts, style: const TextStyle(fontSize: 12))),
        // 环线同样有方向（顺/逆时针到达各点的时间不同），始终可反向。
        TextButton.icon(
          onPressed: onToggleReverse,
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: Text(reversed ? S.detailRestoreDirection : S.reverseRoute),
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
                  Text(
                    S.detailHourLabel,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Expanded(
                    child: Slider(
                      value: hour.toDouble(),
                      min: 0,
                      max: 23,
                      divisions: 23,
                      label: S.detailHourSliderLabel(_two(hour)),
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
                  S.detailPaceSummary(
                    pace.speedKmh,
                    pace.ascentMinPer100m,
                    pace.restMinutesTotal,
                  ),
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
              Text(S.detailPaceSpeed(speed.toStringAsFixed(1))),
              Slider(
                value: speed,
                min: 1.5,
                max: 6,
                divisions: 18,
                label: speed.toStringAsFixed(1),
                onChanged: (v) => setSheet(() => speed = v),
              ),
              Text(S.detailPaceAscent(ascent.toStringAsFixed(0))),
              Slider(
                value: ascent,
                min: 4,
                max: 40,
                divisions: 36,
                label: ascent.toStringAsFixed(0),
                onChanged: (v) => setSheet(() => ascent = v),
              ),
              Text(S.detailPaceRest(rest)),
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
    // 两个控件都受可用宽度约束；大字号时省略标签，完整时间保留在提示中。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          Flexible(
            flex: 2,
            child: ActionChip(
              avatar: const Icon(Icons.schedule, size: 16),
              label: Text(
                '$timeLabel ${timeOpen ? '▴' : '▾'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              tooltip: '$timeLabel · ${S.detailTimeAndPace}',
              onPressed: onToggleTime,
            ),
          ),
          const SizedBox(width: Space.sm),
          Flexible(
            child: PopupMenuButton<String>(
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
                  maxLines: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
