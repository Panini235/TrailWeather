part of 'route_detail_screen.dart';

// 详情页：结论卡、节点行与数据说明。

class _ConclusionCard extends StatelessWidget {
  const _ConclusionCard({
    required this.summary,
    required this.tripMode,
    required this.dayLine,
    required this.settings,
    required this.hints,
    required this.onShowHints,
    required this.onDepartures,
    required this.modeLabel,
  });

  final RouteWxSummary summary;
  final bool tripMode;

  /// 时间模式一行：固定时刻是“全线同一小时”，行程模式是“几点出发、约几点到”。
  final String modeLabel;

  /// 固定时刻模式的全天降水一行；行程模式为 null。
  final String? dayLine;
  final AppSettings settings;
  final List<WxHint> hints;
  final VoidCallback onShowHints;
  final VoidCallback onDepartures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final sorted = [...hints]
      ..sort((a, b) => b.level.index.compareTo(a.level.index));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.md,
          Space.md,
          Space.md,
          Space.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: modeLabel,
              child: Text(
                S.routeSummary,
                style: theme.textTheme.labelMedium?.copyWith(color: muted),
              ),
            ),
            if (tripMode)
              Text(
                modeLabel,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            const SizedBox(height: Space.xs),
            // 结论先行：最关键的一条提示；未触发时如实说明，不说“适合出发”。
            if (summary.hasAnyData) ...[
              _Headline(hints: sorted, onTap: onShowHints),
              const SizedBox(height: Space.md),
            ],
            if (!summary.hasAnyData)
              Text(
                S.detailSummaryNoData(
                  summary.nodesWithData,
                  summary.totalNodes,
                ),
                style: const TextStyle(fontSize: 12, height: 1.5),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _kv(
                      context,
                      S.detailMinMaxTemp,
                      '${summary.minTempC == null ? S.notProvided : Units.temp(summary.minTempC!, imperial: settings.imperial, digits: 0)} / ${summary.maxTempC == null ? S.notProvided : Units.temp(summary.maxTempC!, imperial: settings.imperial)}',
                      icon: Icons.thermostat_outlined,
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      context,
                      S.detailMaxGust,
                      summary.maxGustMs == null
                          ? S.notProvided
                          : Units.windMs(
                              summary.maxGustMs!,
                              unit: settings.windUnit,
                            ),
                      icon: Icons.air,
                      emphasis: true,
                      tone: sorted
                          .where((h) => h.id == 'gust')
                          .map((h) => _hintInk(context, h))
                          .firstOrNull,
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      context,
                      // 固定时刻只是一个小时的量，标清楚，避免当成全天。
                      tripMode ? S.detailTripPrecip : S.detailHourPrecip,
                      summary.totalPrecipMm == null
                          ? S.notProvided
                          : Units.precipMm(
                              summary.totalPrecipMm!,
                              imperial: settings.imperial,
                            ),
                      icon: Icons.water_drop_outlined,
                      emphasis: true,
                      tone: sorted
                          .where((h) => h.id == 'precip')
                          .map((h) => _hintInk(context, h))
                          .firstOrNull,
                    ),
                  ),
                ],
              ),
            if (dayLine != null) ...[
              const Divider(height: Space.sm),
              Text(dayLine!, style: theme.textTheme.bodySmall),
            ],
            if (sorted.length > 1) ...[
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final h in sorted.skip(1).take(3))
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        hintIcon(h),
                        size: 16,
                        color: _hintInk(context, h),
                      ),
                      label: Text(h.title),
                      onPressed: onShowHints,
                    ),
                  if (sorted.length > 4)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('+${sorted.length - 4}'),
                      onPressed: onShowHints,
                    ),
                ],
              ),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.date_range),
              title: const Text(S.detailCompareDepartures),
              trailing: const Icon(Icons.chevron_right),
              onTap: onDepartures,
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(
    BuildContext context,
    String k,
    String v, {
    required IconData icon,
    bool emphasis = false,
    Color? tone,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 13,
            color: tone ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                fontSize: 11,
                color: tone ?? Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      RollingText(
        v,
        lowPower: settings.lowPower,
        unitStyle: emphasis
            ? TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: tone ?? Theme.of(context).colorScheme.onSurfaceVariant,
              )
            : null,
        style: TextStyle(
          fontSize: emphasis ? 17 : 15,
          fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
          color: tone,
        ),
      ),
    ],
  );
}

Color _hintInk(BuildContext context, WxHint h) => switch (h.level) {
  HintLevel.warning => SemanticInk.danger(context),
  HintLevel.caution => SemanticInk.caution(context),
  HintLevel.info => SemanticInk.info(context),
};

/// 结论句：最关键的一条提示（按级别排序后的第一条），其余以“等 N 项”提示；
/// 没有触发时写明不代表安全。点击查看全部提示与依据。
class _Headline extends StatelessWidget {
  const _Headline({required this.hints, required this.onTap});

  final List<WxHint> hints;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = hints.firstOrNull;
    final color = top == null
        ? theme.colorScheme.onSurfaceVariant
        : _hintInk(context, top);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              top == null ? Icons.info_outline : hintIcon(top),
              size: top == null ? 16 : 22,
              color: color,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: top == null
                  ? Text(
                      S.noHintsTriggered,
                      style: theme.textTheme.bodySmall?.copyWith(color: color),
                    )
                  : Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: top.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                          if (hints.length > 1)
                            TextSpan(
                              text: S.detailMoreHints(hints.length),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    super.key,
    required this.row,
    required this.index,
    required this.tripMode,
    required this.selected,
    required this.settings,
    required this.onTap,
  });

  final NodeWxRow row;
  final int index;
  final bool tripMode;
  final bool selected;
  final AppSettings settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wp = row.node.waypoint;
    final name = row.node.label ?? S.detailNodeFallback(index + 1);
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
      leading: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
      ),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WxBriefLine(wx: row.wx, settings: settings),
          if (row.node.nearbyWaypoints.isNotEmpty)
            Text(
              '${S.nearbyMarksPrefix}：'
              '${row.node.nearbyWaypoints.map((w) => w.name).join('、')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: muted),
            ),
          if (wp?.stopMinutes != null)
            Text(
              S.detailStopMinutes(wp!.stopMinutes!),
              style: TextStyle(fontSize: 11, color: muted),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// 预报与上方节点相同的普通节点：默认收成一行，点开展开为完整节点行。
///
/// 只有同一网格、同一小时的节点才会进到这里（见 [foldTimeline]），折叠不合并不同的数据。
class _FoldedRun extends StatefulWidget {
  const _FoldedRun({
    super.key,
    required this.rows,
    required this.firstIndex,
    required this.tripMode,
    required this.containsSelected,
    required this.lowPower,
    required this.buildTiles,
  });

  final List<NodeWxRow> rows;
  final int firstIndex;
  final bool tripMode;

  /// 其中含有选中节点（地图或剖面上选的）：收起时高亮这一行。
  final bool containsSelected;
  final bool lowPower;
  final List<Widget> Function() buildTiles;

  @override
  State<_FoldedRun> createState() => _FoldedRunState();
}

class _FoldedRunState extends State<_FoldedRun>
    with SingleTickerProviderStateMixin {
  /// 展开状态留在这一行自己身上：点按只重建这一小块，不重建整个详情页。
  bool _expanded = false;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Motion.base)
        ..addStatusListener((s) {
          if (s == AnimationStatus.dismissed && mounted) setState(() {});
        });
  late final Animation<double> _size = CurvedAnimation(
    parent: _c,
    curve: Motion.enter,
    reverseCurve: Motion.exit,
  );

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (Motion.reduced(context, lowPower: widget.lowPower)) {
      _c.value = _expanded ? 1 : 0;
    } else if (_expanded) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _range() {
    final first = widget.rows.first;
    final last = widget.rows.last;
    if (widget.tripMode) {
      String hm(DateTime utc) {
        final t = utc.toLocal();
        return '${_two(t.hour)}:${_two(t.minute)}';
      }

      final a = hm(first.validUtc);
      final b = hm(last.validUtc);
      return a == b ? a : '$a–$b';
    }
    String km(NodeWxRow r) => (r.node.distFromStartM / 1000).toStringAsFixed(1);
    final a = km(first);
    final b = km(last);
    return a == b ? '$a km' : '$a–$b km';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final names = [
      for (final r in widget.rows)
        for (final w in r.node.nearbyWaypoints) w.name,
    ];
    final header = Material(
      color: widget.containsSelected && !_expanded
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : Colors.transparent,
      child: InkWell(
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Icon(Icons.more_vert, size: 16, color: muted),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${S.foldedNodes(widget.rows.length)}'
                      '（${widget.firstIndex + 1}–${widget.firstIndex + widget.rows.length}） · ${_range()}'
                      ' · ${S.foldedSameForecast}',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    if (names.isNotEmpty)
                      Text(
                        '${S.nearbyMarksPrefix}：${names.join('、')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                  ],
                ),
              ),
              RotationTransition(
                turns: Tween(begin: 0.0, end: 0.5).animate(_size),
                child: Icon(Icons.expand_more, size: 20, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(button: true, expanded: _expanded, child: header),
        if (!_c.isDismissed || _expanded)
          SizeTransition(
            sizeFactor: _size,
            alignment: AlignmentDirectional.topStart,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.buildTiles(),
            ),
          ),
      ],
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
                  S.detailNoResolution,
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
                '${prov.modelRunUtc == null ? '' : S.detailModelRunLine(prov.modelRunUtc!.toIso8601String().substring(0, 16))}'
                '${prov.elevationUsedM == null ? '' : S.detailSourceElevLine(prov.elevationUsedM!.toStringAsFixed(0))}',
                style: const TextStyle(fontSize: 11, height: 1.5),
              ),
            TextButton.icon(
              icon: const Icon(Icons.science_outlined, size: 16),
              label: const Text(
                S.detailFullProvenance,
                style: TextStyle(fontSize: 12),
              ),
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
