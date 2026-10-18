import 'package:flutter/material.dart';

import '../../core/units.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/weather_phenomena.dart';
import '../../data/weather/wx_importance.dart';
import '../strings.dart';
import '../tokens.dart';

/// 单个变量的“名称 + 值”行。缺失时如实显示“此来源未提供”。
class WxVarTile extends StatelessWidget {
  const WxVarTile({
    super.key,
    required this.label,
    required this.value,
    required this.formatter,
  });

  final String label;
  final double? value;
  final String Function(double v) formatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        if (value == null)
          const MissingValue()
        else
          Text(
            formatter(value!),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

/// 瞬时值和区间值分开解释；长按可追溯来源原始时次。
class WeatherHourNotice extends StatelessWidget {
  const WeatherHourNotice({super.key, required this.wx});
  final WxHourValue wx;

  @override
  Widget build(BuildContext context) {
    String clock(DateTime t) {
      final l = t.toLocal();
      return '${l.month}/${l.day} ${l.hour.toString().padLeft(2, '0')}:00';
    }

    final labels = wx.intervalVariables.map((v) => v.label).join('、');
    final unknown = wx.unconfirmedIntervalVariables
        .map((v) => v.label)
        .join('、');
    final threeHour = wx.precedingThreeHourVariables
        .map((v) => v.label)
        .join('、');
    if (labels.isEmpty && unknown.isEmpty && threeHour.isEmpty) {
      return const SizedBox.shrink();
    }
    final text = [
      if (labels.isNotEmpty)
        S.wxIntervalNote(
          labels,
          clock(wx.validFromUtc),
          clock(wx.validFromUtc.add(const Duration(hours: 1))),
        ),
      if (threeHour.isNotEmpty)
        S.wxPreviousThreeHourNote(
          threeHour,
          clock(wx.validFromUtc.subtract(const Duration(hours: 3))),
          clock(wx.validFromUtc),
        ),
      if (unknown.isNotEmpty) S.wxUnknownIntervalNote(unknown),
    ].join('\n');
    return Tooltip(
      message: S.wxOriginalTimes(
        wx.sourceTimesUtc.entries
            .where((e) => wx.values[e.key] != null)
            .map((e) => '${e.key.label} ${e.value.toIso8601String()}')
            .join('\n'),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class MissingValue extends StatelessWidget {
  const MissingValue({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      S.notProvided,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

/// 变量格，按层级分组（docs/data-hierarchy.md）：
/// 决策层总是显示（缺失写“此来源未提供”）；准备层中紫外线、湿度、风向总是显示，
/// 其余有值才显示；参考层只在有值时显示，避免一屏“未提供”。
/// [exclude]：上方已经放大显示过的变量（如节点详情的 4 个关键值）。
class WxVarGrid extends StatelessWidget {
  const WxVarGrid({
    super.key,
    required this.wx,
    required this.settings,
    this.exclude = const {},
  });

  final WxHourValue wx;
  final AppSettings settings;
  final Set<WxVar> exclude;

  static const _order = [
    WxVar.temperature,
    WxVar.apparentTemp,
    WxVar.precip,
    WxVar.precipProb,
    WxVar.windGust,
    WxVar.visibility,
    WxVar.uvIndex,
    WxVar.windDir,
    WxVar.humidity,
    WxVar.cloudLow,
    WxVar.freezingLevel,
    WxVar.snowfall,
    WxVar.snowDepth,
    WxVar.windSpeed,
    WxVar.cloudCover,
    WxVar.cloudMid,
    WxVar.cloudHigh,
    WxVar.dewPoint,
    WxVar.pressure,
    WxVar.uvIndexClearSky,
    WxVar.cape,
    WxVar.snowFraction,
  ];

  static const _alwaysPrepare = {WxVar.uvIndex, WxVar.windDir, WxVar.humidity};

  String _fmt(WxVar v, double x) => switch (v) {
    WxVar.temperature ||
    WxVar.apparentTemp ||
    WxVar.dewPoint => Units.temp(x, imperial: settings.imperial),
    WxVar.precip => Units.precipMm(x, imperial: settings.imperial),
    WxVar.windSpeed ||
    WxVar.windGust => Units.windMs(x, unit: settings.windUnit),
    WxVar.windDir => Units.windDirectionLabel(x),
    WxVar.visibility => '${(x / 1000).toStringAsFixed(x < 10000 ? 1 : 0)} km',
    WxVar.pressure => '${x.toStringAsFixed(0)} hPa',
    WxVar.snowfall => '${x.toStringAsFixed(1)} cm/h',
    WxVar.snowDepth => '${(x * 100).round()} cm',
    WxVar.freezingLevel => '${x.toStringAsFixed(0)} m',
    WxVar.uvIndex => '${x.round()} ${uvLevelLabel(uvLevelOf(x))}',
    WxVar.uvIndexClearSky => '${x.round()}',
    WxVar.cape => '${x.round()} J/kg',
    WxVar.precipProb ||
    WxVar.humidity ||
    WxVar.cloudCover ||
    WxVar.cloudLow ||
    WxVar.cloudMid ||
    WxVar.cloudHigh ||
    WxVar.snowFraction => '${x.toStringAsFixed(0)}%',
  };

  bool _show(WxVar v) {
    if (exclude.contains(v)) return false;
    return switch (tierOf(v)) {
      WxTier.decide => true,
      WxTier.prepare => _alwaysPrepare.contains(v) || wx.values[v] != null,
      WxTier.reference => wx.values[v] != null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final phen = phenomenonOf(wx);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final groups = <WxTier, List<WxVar>>{};
    for (final v in _order) {
      if (_show(v)) groups.putIfAbsent(tierOf(v), () => []).add(v);
    }
    Widget grid(List<WxVar> vars) => LayoutBuilder(
      // 自适应列数与自然高度：缺失文案和大字体不能被固定比例格子裁掉。
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = (constraints.maxWidth / (150 * scale)).floor().clamp(
          1,
          4,
        );
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final v in vars)
              SizedBox(
                width: width,
                child: WxVarTile(
                  label: v.label,
                  value: wx.values[v],
                  formatter: (x) => _fmt(v, x),
                ),
              ),
          ],
        );
      },
    );
    Widget header(String text) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(text, style: TextStyle(fontSize: 11, color: muted)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WeatherHourNotice(wx: wx),
        if (phen != null && !exclude.contains(WxVar.precip))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${S.phenomenonLabel}：${phen.label}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        if (groups[WxTier.decide] case final d?) grid(d),
        if (groups[WxTier.prepare] case final p?) ...[
          header(S.tierPrepare),
          grid(p),
        ],
        if (groups[WxTier.reference] case final r?) ...[
          header(S.tierReference),
          grid(r),
        ],
      ],
    );
  }
}

/// 准备层被触发的信号（紫外线很高、高于 0℃ 层、低云……），点按看依据。
class WxSignalChips extends StatelessWidget {
  const WxSignalChips({super.key, required this.signals});

  final List<WxSignal> signals;

  @override
  Widget build(BuildContext context) {
    if (signals.isEmpty) return const SizedBox.shrink();
    Color ink(WxSignalLevel l) => switch (l) {
      WxSignalLevel.warning => SemanticInk.danger(context),
      WxSignalLevel.caution => SemanticInk.caution(context),
      WxSignalLevel.info => SemanticInk.info(context),
    };
    IconData icon(WxSignalKind k) => switch (k) {
      WxSignalKind.uv || WxSignalKind.uvClearSky => Icons.wb_sunny_outlined,
      WxSignalKind.snowGlare => Icons.visibility_outlined,
      WxSignalKind.lowCloud => Icons.cloud_outlined,
      WxSignalKind.aboveFreezing ||
      WxSignalKind.snowfall ||
      WxSignalKind.snowCover => Icons.ac_unit,
      WxSignalKind.dampCold => Icons.water_drop_outlined,
      WxSignalKind.convective => Icons.thunderstorm_outlined,
    };
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in signals)
          Tooltip(
            message: s.basis,
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: ink(s.level).withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon(s.kind), size: 14, color: ink(s.level)),
                  const SizedBox(width: 4),
                  Text(
                    s.label,
                    style: TextStyle(fontSize: 12.5, color: ink(s.level)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 节点/时次一行摘要（列表用）：温度 · 降水 · 风。
class WxBriefLine extends StatelessWidget {
  const WxBriefLine({super.key, required this.wx, required this.settings});

  final WxHourValue? wx;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final v = wx?.values;
    if (v == null) {
      return Text(
        S.cellsNoDataAtHour,
        style: TextStyle(fontSize: 12, color: Theme.of(context).disabledColor),
      );
    }
    final t = v[WxVar.temperature];
    final p = v[WxVar.precip];
    final ws = v[WxVar.windSpeed];
    final parts = <String>[
      t == null ? S.notProvided : Units.temp(t, imperial: settings.imperial),
      p == null
          ? S.cellsPrecipMissing
          : S.cellsPrecip(Units.precipMm(p, imperial: settings.imperial)),
      ws == null
          ? S.cellsWindMissing
          : S.cellsWind(Units.windMs(ws, unit: settings.windUnit)),
    ];
    return Text(parts.join(' · '), style: const TextStyle(fontSize: 12));
  }
}

/// 节点详情的 4 个关键值（放大显示）：气温/体感、阵风、降水、天气现象。
/// 缺失值如实显示“未提供”，持续风速不顶替阵风。
class KeyWeatherValues extends StatelessWidget {
  const KeyWeatherValues({super.key, required this.wx, required this.settings});

  final WxHourValue wx;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final v = wx.values;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    String temp(double? x) =>
        x == null ? '—' : Units.temp(x, imperial: settings.imperial);
    final t = v[WxVar.temperature];
    final a = v[WxVar.apparentTemp];
    final gust = v[WxVar.windGust];
    final wind = v[WxVar.windSpeed];
    final p = v[WxVar.precip];
    final pp = v[WxVar.precipProb];
    final phen = phenomenonOf(wx);
    Widget cell(String label, String value, [String? sub]) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: muted)),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        if (sub != null)
          Text(sub, style: TextStyle(fontSize: 11, color: muted)),
      ],
    );
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      children: [
        cell(
          S.cellsTempFeels,
          t == null && a == null ? S.notProvided : '${temp(t)} / ${temp(a)}',
        ),
        cell(
          WxVar.windGust.label,
          gust == null
              ? S.notProvided
              : Units.windMs(gust, unit: settings.windUnit),
          wind == null
              ? null
              : S.cellsSustained(Units.windMs(wind, unit: settings.windUnit)),
        ),
        cell(
          WxVar.precip.label,
          p == null
              ? S.notProvided
              : Units.precipMm(p, imperial: settings.imperial),
          pp == null
              ? null
              // 概率高而量为 0：两者来自不同模型（Open-Meteo 概率来自集合预报）。
              : (pp >= 50 && (p ?? 0) < 0.1)
              ? S.cellsProbWithNote(pp.toStringAsFixed(0))
              : S.cellsProb(pp.toStringAsFixed(0)),
        ),
        cell(S.phenomenonLabel, phen?.label ?? S.notProvided),
      ],
    );
  }
}
