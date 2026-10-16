import 'package:flutter/material.dart';

import '../../core/units.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/weather_phenomena.dart';
import '../strings.dart';

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

/// 一组常用变量格（按设置换算单位）。
class WxVarGrid extends StatelessWidget {
  const WxVarGrid({super.key, required this.wx, required this.settings});

  final WxHourValue wx;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final v = wx.values;
    final phen = phenomenonOf(wx);
    final tiles = <Widget>[
      WxVarTile(
        label: WxVar.temperature.label,
        value: v[WxVar.temperature],
        formatter: (x) => Units.temp(x, imperial: settings.imperial),
      ),
      WxVarTile(
        label: WxVar.apparentTemp.label,
        value: v[WxVar.apparentTemp],
        formatter: (x) => Units.temp(x, imperial: settings.imperial),
      ),
      WxVarTile(
        label: WxVar.precip.label,
        value: v[WxVar.precip],
        formatter: (x) => Units.precipMm(x, imperial: settings.imperial),
      ),
      WxVarTile(
        label: WxVar.precipProb.label,
        value: v[WxVar.precipProb],
        formatter: (x) => '${x.toStringAsFixed(0)}%',
      ),
      WxVarTile(
        label: WxVar.windSpeed.label,
        value: v[WxVar.windSpeed],
        formatter: (x) => Units.windMs(x, unit: settings.windUnit),
      ),
      WxVarTile(
        label: WxVar.windGust.label,
        value: v[WxVar.windGust],
        formatter: (x) => Units.windMs(x, unit: settings.windUnit),
      ),
      WxVarTile(
        label: WxVar.windDir.label,
        value: v[WxVar.windDir],
        formatter: (x) => Units.windDirectionLabel(x),
      ),
      WxVarTile(
        label: WxVar.humidity.label,
        value: v[WxVar.humidity],
        formatter: (x) => '${x.toStringAsFixed(0)}%',
      ),
      WxVarTile(
        label: WxVar.cloudCover.label,
        value: v[WxVar.cloudCover],
        formatter: (x) => '${x.toStringAsFixed(0)}%',
      ),
      WxVarTile(
        label: WxVar.visibility.label,
        value: v[WxVar.visibility],
        formatter: (x) => '${(x / 1000).toStringAsFixed(x < 10000 ? 1 : 0)} km',
      ),
      WxVarTile(
        label: WxVar.pressure.label,
        value: v[WxVar.pressure],
        formatter: (x) => '${x.toStringAsFixed(0)} hPa',
      ),
      // 只有提供该变量的来源才显示（目前为 meteoblue），避免每个来源都多一格“未提供”。
      if (v[WxVar.snowfall] != null)
        WxVarTile(
          label: WxVar.snowfall.label,
          value: v[WxVar.snowfall],
          formatter: (x) => '${x.toStringAsFixed(1)} cm/h',
        ),
      if (v[WxVar.freezingLevel] != null)
        WxVarTile(
          label: WxVar.freezingLevel.label,
          value: v[WxVar.freezingLevel],
          formatter: (x) => '${x.toStringAsFixed(0)} m',
        ),
      if (v[WxVar.snowFraction] != null)
        WxVarTile(
          label: WxVar.snowFraction.label,
          value: v[WxVar.snowFraction],
          formatter: (x) => '${x.toStringAsFixed(0)}%',
        ),
    ];
    // 自适应列数与自然高度：缺失文案和大字体不能被固定比例格子裁掉。
    final grid = LayoutBuilder(
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
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
    if (phen == null) return grid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '${S.phenomenonLabel}：${phen.label}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        grid,
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
        '该时次无数据（超出来源范围或未提供）',
        style: TextStyle(fontSize: 12, color: Theme.of(context).disabledColor),
      );
    }
    final t = v[WxVar.temperature];
    final p = v[WxVar.precip];
    final ws = v[WxVar.windSpeed];
    final parts = <String>[
      t == null ? S.notProvided : Units.temp(t, imperial: settings.imperial),
      p == null
          ? '降水：未提供'
          : '降水 ${Units.precipMm(p, imperial: settings.imperial)}',
      ws == null ? '风：未提供' : '风 ${Units.windMs(ws, unit: settings.windUnit)}',
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
          '气温 / 体感',
          t == null && a == null ? S.notProvided : '${temp(t)} / ${temp(a)}',
        ),
        cell(
          WxVar.windGust.label,
          gust == null
              ? S.notProvided
              : Units.windMs(gust, unit: settings.windUnit),
          wind == null
              ? null
              : '持续 ${Units.windMs(wind, unit: settings.windUnit)}',
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
              ? '概率 ${pp.toStringAsFixed(0)}% · ${S.probVsAmountNote}'
              : '概率 ${pp.toStringAsFixed(0)}%',
        ),
        cell(S.phenomenonLabel, phen?.label ?? S.notProvided),
      ],
    );
  }
}
