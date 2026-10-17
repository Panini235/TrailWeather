part of 'route_detail_screen.dart';

// 详情页：结论卡、节点行与数据说明。

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
            Text(
              S.routeSummary,
              style: theme.textTheme.labelMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: Space.xs),
            // 结论先行：最关键的一条提示；未触发时如实说明，不说“适合出发”。
            if (summary.hasAnyData) ...[
              _Headline(hints: sorted, onTap: onShowHints),
              const SizedBox(height: Space.md),
            ],
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
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(dayLine!, style: const TextStyle(fontSize: 13)),
              ),
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
      RollingText(
        v,
        lowPower: settings.lowPower,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
        ? SemanticInk.go(context)
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
              top == null ? Icons.check_circle_outline : hintIcon(top),
              size: 22,
              color: color,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: top == null
                  ? Text(S.noHintsTriggered, style: theme.textTheme.bodyMedium)
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
                              text: '  等 ${hints.length} 项提示',
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
      leading = const Icon(Icons.flag, size: 18, color: Semantic.go);
    } else if (isLast) {
      leading = const Icon(
        Icons.sports_score,
        size: 18,
        color: Semantic.danger,
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
