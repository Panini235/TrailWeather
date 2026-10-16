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
import 'departure_threshold_screen.dart';

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
  WxVar.temperature => '气温',
  WxVar.windGust => '阵风',
  WxVar.precip => '小时降水',
  _ => v.name,
};
String _value(WxVar v, double? n) => n == null
    ? '此来源未提供'
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
            .showSnackBar(const SnackBar(content: Text('该出发时刻已过去，请重新选择')));
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
      '比较日期 × 出发时刻的沿途天气。所有时间按设备时区显示，跨时区出行请核对。',
      '每隔 2 小时比较一次，最多 5 个出发时刻；可左右滑动表格。',
      '颜色只表示阈值结果，不代表安全等级。灰色为信息不足；红/黄也可能同时缺数据。官方预警未接入；日出未接入，未核验全程是否处于白昼。',
      '按阈值：阵风 ≥${t.gustYellow}/${t.gustRed} m/s（黄/红）；小时降水 ≥${t.precipYellow} mm（黄）；气温 ≤${t.coldRed}℃（红）；预计到达晚于日落（黄）。',
      '计算方法：按配速、爬升/下降、休息与航点停留估算 ETA；逐段检查经过小时的两个采样端点，属于保守的时空近似，不是实时实测。点开格子可查看原因、缺口和各节点时次。',
      if (source != null)
        '单一来源 · ${source.caps.modelOrNetwork} · 最远约 ${source.caps.forecastHorizonDays} 天，以实际返回覆盖为准。',
      ?source?.caps.modelOverlapNote,
      ?bundle?.sharedGridNote,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('出发窗口'),
        actions: [
          IconButton(
            tooltip: '规则与数据说明',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showExplain(explain),
          ),
          IconButton(
            tooltip: '刷新出发窗口',
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
            '${args.route.isDemo ? '演示 · ' : ''}${args.route.name}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${args.reversed ? '反向行走' : '正向行走'} · 全程约 ${(duration.inMinutes / 60).toStringAsFixed(1)} 小时（估算）',
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
                label: Text('从 ${_date(_first)} 起'),
              ),
              DropdownButton<int>(
                value: _days,
                items: [
                  for (final n in [1, 3, 5])
                    DropdownMenuItem(value: n, child: Text('$n 天')),
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
                  '首个时刻 ${_two(_firstSlot.hour)}:${_two(_firstSlot.minute)}',
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
              child: Text('当前线路缺少节点或预计连续行走超过 24 小时。请先导入单日线路；多日拆分尚未完成。'),
            ),
          if (source == null) const Text('没有可用于比较的来源。请在设置中启用可自动查询的天气来源。'),
          if (async?.isLoading == true || bundle?.result.refreshing == true)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(semanticsLabel: '正在获取出发窗口天气'),
            ),
          if (async?.hasError == true) ...[
            const Text('天气请求失败或超出来源预报范围。请调整日期或来源后重试。'),
            TextButton(
              onPressed: () => setState(() => _refresh++),
              child: const Text('重试出发窗口'),
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
              '✓ 未触发　风 阵风　雨 降水　冷 低温　晚 晚于日落　缺 信息不足　点格子看依据',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
          if (bundle != null) ...[
            const SizedBox(height: 8),
            Text(
              '${bundle.result.stale
                  ? '旧缓存'
                  : bundle.result.fromCache
                  ? '已缓存预报'
                  : '已获取预报'} · 获取于 ${_stamp(bundle.result.fetchedAtUtc)}',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            if (bundle.result.refreshFailed) const Text('刷新失败，保留上次数据及其真实获取时间。'),
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
              label: const Text('调整出发阈值'),
            ),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('规则与数据说明'),
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
              const Text(
                '· 日落采用来源提供的终点日落，按终点经度近似归属出发日期；不使用手机所在日期推算线路日落。未考虑山体遮挡，未核验日出和极昼/极夜。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ],
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
            Text('规则与数据说明', style: Theme.of(ctx).textTheme.titleMedium),
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
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    final head = switch (diff) {
      0 => '今天',
      1 => '明天',
      _ => '周${week[d.weekday - 1]}',
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
        '过',
        colors.surfaceContainerHighest.withValues(alpha: 0.5),
        colors.onSurfaceVariant,
        tip: '已过去',
      );
    }
    if (bundle == null || providerId == null) {
      return box(
        '缺',
        colors.surfaceContainerHighest,
        colors.onSurface,
        tip: '信息不足',
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
        dark ? const Color(0xFF4D3800) : const Color(0xFFFFE7A0),
        dark ? const Color(0xFFFFE7A0) : const Color(0xFF493400),
      ),
      DepartureLevel.none =>
        a.insufficient
            ? (colors.surfaceContainerHighest, colors.onSurface)
            : (colors.primaryContainer, colors.onPrimaryContainer),
    };
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        label: '${_stamp(start)} 出发，${a.label}，预计 ${_stamp(a.finishUtc)} 到达',
        child: Tooltip(
          message: '${a.label} · 约 ${_time(a.finishUtc)} 到达',
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
      WxVar.windGust => '风',
      WxVar.precip => '雨',
      WxVar.temperature => '冷',
      _ => f.sunsetUtc != null ? '晚' : '!',
    };
    if (!glyphs.contains(g)) glyphs.add(g);
  }
  final shown = glyphs.take(2).toList();
  if (a.insufficient) shown.add('缺');
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
      appBar: AppBar(title: const Text('出发依据')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(a.label, style: Theme.of(context).textTheme.headlineSmall),
          Text(
            '出发 ${_stamp(a.startUtc)}\n预计到达 ${_stamp(a.finishUtc)}（估算；设备时区）',
          ),
          Text(
            '来源 ${a.bundle.result.providerId} · 获取 ${_stamp(a.bundle.result.fetchedAtUtc)}',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: past ? null : () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.schedule),
            label: Text(past ? '该出发时刻已过去' : '用这个时间查看行程'),
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
                        '${args.nodes[finding.sample!.nodeIndex].describe()}\n经过小时 ${_stamp(finding.sample!.hourUtc)}',
                      ),
                      Text(
                        '原始有效时次 ${_stamp(finding.sample!.sourceTimesUtc[finding.variable]!)}',
                      ),
                      Text(
                        '模型 ${finding.sample!.point!.provenance.modelKnown ? finding.sample!.point!.provenance.modelOrNetwork : '未知（${finding.sample!.point!.provenance.modelOrNetwork}）'}',
                      ),
                    ],
                    if (finding.sunsetUtc != null)
                      Text('终点日落 ${_stamp(finding.sunsetUtc!)}（日期归属近似）'),
                  ],
                ),
              ),
            ),
          if (a.findings.isEmpty) const Text('已提供的数据没有触发当前阈值；这不是安全保证。'),
          for (final gap in a.gaps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('信息不足 · $gap'),
            ),
          for (final e in a.missingValues.entries)
            if (e.value > 0) Text('${_name(e.key)}：${e.value} 个节点小时缺失，此来源未提供'),
          Text(
            '完整天气采样 ${a.samples.where((s) => s.complete).length}/${a.samples.length} 个采样（逐小时气温/阵风/降水，整点抵达另核对气温）；共享查询点不算独立证据。',
          ),
          if (a.bundle.sharedGridNote != null) Text(a.bundle.sharedGridNote!),
          const SizedBox(height: 12),
          const Text('各节点与原始时次', style: TextStyle(fontWeight: FontWeight.bold)),
          if (a.bundle.result.providerId.startsWith('open-meteo:'))
            const Text(
              'Open-Meteo：小时降水和阵风使用该小时结束时的记录；气温使用小时起点的瞬时值。下面保留每项原始有效时次。',
            ),
          for (var i = 0; i < args.nodes.length; i++)
            ExpansionTile(
              key: ValueKey('departure-node-$i'),
              title: Text(args.nodes[i].describe()),
              subtitle: Text('预计到达 ${_stamp(a.etasUtc[i])}（估算）'),
              children: [
                if (departurePoint(a.bundle, i) case final p?)
                  _provenance(p.provenance),
                for (final s in a.samples.where((s) => s.nodeIndex == i))
                  ListTile(
                    title: Text(
                      '${s.instantOnly ? '抵达整点' : '经过小时'} ${_stamp(s.hourUtc)}',
                    ),
                    subtitle: Text(
                      [
                        for (final v in s.sourceTimesUtc.keys)
                          '${_name(v)}：${_value(v, s.values[v])} · 原始时次 ${_stamp(s.sourceTimesUtc[v]!)}',
                      ].join('\n'),
                    ),
                  ),
              ],
            ),
          const Text('预报不是实测；采样、ETA 与日期归属均有近似。日出和官方预警未接入，仍需核对现场与官方信息。'),
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
