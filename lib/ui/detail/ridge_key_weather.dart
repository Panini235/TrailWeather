import 'package:flutter/material.dart';

import '../../core/units.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/weather_models.dart';
import '../strings.dart';
import 'detail_state.dart';

/// 仅比较当前各节点的所选时段，不求和，也不将其他变量代替缺失值。
class RidgePeak {
  const RidgePeak(this.value, this.indices, this.provided, this.total);

  final double? value;
  final List<int> indices;
  final int provided, total;

  /// 零值或沿途全部同值不指定一个虚假的特殊位置。
  int? get target => value == null || value! <= 0 || indices.length == total
      ? null
      : indices.first;
}

RidgePeak ridgePeak(List<NodeWxRow> rows, WxVar variable) {
  double? max;
  var provided = 0;
  final indices = <int>[];
  for (var i = 0; i < rows.length; i++) {
    final v = rows[i].wx?.values[variable];
    if (v == null || !v.isFinite) continue;
    provided++;
    if (max == null || v > max) {
      max = v;
      indices
        ..clear()
        ..add(i);
    } else if (v == max) {
      indices.add(i);
    }
  }
  return RidgePeak(max, indices, provided, rows.length);
}

/// 两项数值强调，不等同于风险评级；风险提示仍由既有规则生成。
class RidgeKeyWeather extends StatelessWidget {
  const RidgeKeyWeather({
    super.key,
    required this.rows,
    required this.settings,
    required this.onSelect,
  });

  final List<NodeWxRow> rows;
  final AppSettings settings;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final stacked = MediaQuery.textScalerOf(context).scale(14) > 20;
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final variable in [WxVar.precip, WxVar.windGust])
              SizedBox(
                width: stacked ? width : (width - 8) / 2,
                child: _metric(context, variable),
              ),
          ],
        );
      },
    );
  }

  Widget _metric(BuildContext context, WxVar variable) {
    final rain = variable == WxVar.precip;
    final peak = ridgePeak(rows, variable);
    final target = peak.target;
    final scheme = Theme.of(context).colorScheme;
    final value = peak.value == null
        ? S.notProvided
        : rain
        ? Units.precipMm(peak.value!, imperial: settings.imperial)
        : Units.windMs(peak.value!, unit: settings.windUnit);
    final location = target == null
        ? null
        : '${S.ridgeNodeN(target + 1)}'
              '${peak.indices.length > 1 ? '等 ${peak.indices.length} 处' : ''}'
              ' · ${(rows[target].node.distFromStartM / 1000).toStringAsFixed(1)} km';
    final title = rain ? S.ridgePeakPrecip : S.ridgePeakGust;
    return Tooltip(
      message: S.ridgePeakScope,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: target == null ? null : () => onSelect(target),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: target == null ? 30 : 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        rain ? Icons.water_drop_outlined : Icons.air,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      Text(
                        value,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (target != null)
                        Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                  if (location != null)
                    Text(
                      location,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (peak.provided > 0 && peak.provided < peak.total)
                    Text(
                      S.ridgePeakPartial,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
