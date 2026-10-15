import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/units.dart';
import '../../data/app_providers.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/air_quality.dart';
import '../../data/weather/altitude_profile.dart';
import '../strings.dart';

/// “同一地点不同海拔”卡片：Open-Meteo 按海拔统计降尺度的垂直剖面（模型估算，非实测）。
///
/// [nodeElevationM] 有值时为节点场景：取线路最低 / 节点 / 线路最高；
/// 否则按地面海拔（Elevation API）取 地面、+500、+1000、+1500 m。
class AltitudeWeatherCard extends ConsumerStatefulWidget {
  const AltitudeWeatherCard({
    super.key,
    required this.point,
    required this.atUtc,
    this.nodeElevationM,
    this.routeMinM,
    this.routeMaxM,
  });

  final LatLng point;
  final DateTime atUtc;
  final double? nodeElevationM;
  final double? routeMinM;
  final double? routeMaxM;

  @override
  ConsumerState<AltitudeWeatherCard> createState() =>
      _AltitudeWeatherCardState();
}

class _AltitudeWeatherCardState extends ConsumerState<AltitudeWeatherCard> {
  late Future<(double, List<AltitudeSample>)> _future = _load();

  @override
  void didUpdateWidget(covariant AltitudeWeatherCard old) {
    super.didUpdateWidget(old);
    if (old.point != widget.point ||
        old.atUtc != widget.atUtc ||
        old.nodeElevationM != widget.nodeElevationM) {
      _future = _load();
    }
  }

  Future<(double, List<AltitudeSample>)> _load() async {
    final svc = ref.read(altitudeProfileServiceProvider);
    final base =
        widget.nodeElevationM ?? await svc.groundElevation(widget.point);
    if (base == null) throw const FormatException('无法取得该点地面海拔');
    final levels = altitudeLevels(
      base: base,
      routeMin: widget.routeMinM,
      routeMax: widget.routeMaxM,
    );
    return (base, await svc.profile(widget.point, levels, widget.atUtc));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: FutureBuilder<(double, List<AltitudeSample>)>(
          future: _future,
          builder: (context, snap) {
            final header = Text(
              S.altitudeCardTitle,
              style: Theme.of(context).textTheme.titleSmall,
            );
            if (snap.connectionState == ConnectionState.waiting) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                ],
              );
            }
            if (snap.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  Text(
                    '暂时无法获取：${snap.error}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              );
            }
            final (base, samples) = snap.data!;
            final fz = samples
                .map((s) => s.freezingLevelM)
                .whereType<double>()
                .firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 4),
                for (final s in samples.reversed)
                  _AltitudeRow(
                    sample: s,
                    highlight: (s.elevationM - base).abs() < 10,
                    settings: settings,
                  ),
                const SizedBox(height: 4),
                Text(
                  '${fz == null ? '' : '0℃ 层约 ${fz.toStringAsFixed(0)} m。'}${S.altitudeCardNote}',
                  style: TextStyle(fontSize: 11, height: 1.4, color: muted),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AltitudeRow extends StatelessWidget {
  const _AltitudeRow({
    required this.sample,
    required this.highlight,
    required this.settings,
  });

  final AltitudeSample sample;
  final bool highlight;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final t = sample.tempC;
    final g = sample.gustMs;
    final style = TextStyle(
      fontSize: 13,
      fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              '${highlight ? '▶ ' : ''}${sample.elevationM.toStringAsFixed(0)} m',
              style: style,
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              t == null ? '—' : Units.temp(t, imperial: settings.imperial),
              style: style,
            ),
          ),
          SizedBox(
            width: 84,
            child: Text(
              g == null
                  ? '—'
                  : '阵风 ${Units.windMs(g, unit: settings.windUnit)}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              sample.phenomenon?.label ?? '',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// 空气质量卡片（PM2.5 / PM10 / 美国 AQI），区域级数值并署名 CAMS。
class AirQualityCard extends ConsumerStatefulWidget {
  const AirQualityCard({super.key, required this.point, required this.atUtc});

  final LatLng point;
  final DateTime atUtc;

  @override
  ConsumerState<AirQualityCard> createState() => _AirQualityCardState();
}

class _AirQualityCardState extends ConsumerState<AirQualityCard> {
  late Future<AirQualitySeries> _future = ref
      .read(airQualityServiceProvider)
      .fetch(widget.point);

  @override
  void didUpdateWidget(covariant AirQualityCard old) {
    super.didUpdateWidget(old);
    if (old.point != widget.point) {
      _future = ref.read(airQualityServiceProvider).fetch(widget.point);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: FutureBuilder<AirQualitySeries>(
          future: _future,
          builder: (context, snap) {
            final header = Text(
              S.airQualityTitle,
              style: Theme.of(context).textTheme.titleSmall,
            );
            if (snap.connectionState == ConnectionState.waiting) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                ],
              );
            }
            final h = snap.data?.at(widget.atUtc);
            String fmt(double? v, String unit) =>
                v == null ? S.notProvided : '${v.toStringAsFixed(0)} $unit';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 4),
                if (snap.hasError)
                  Text(
                    '暂时无法获取：${snap.error}',
                    style: const TextStyle(fontSize: 12),
                  )
                else if (h == null)
                  const Text(
                    '该时刻不在空气质量预报范围（约 5 天）。',
                    style: TextStyle(fontSize: 12),
                  )
                else ...[
                  Text(
                    h.usAqi == null
                        ? 'AQI：${S.notProvided}'
                        : 'AQI ${h.usAqi!.toStringAsFixed(0)}（${usAqiCategory(h.usAqi!)}，美国标准）',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'PM2.5 ${fmt(h.pm25, 'μg/m³')} · PM10 ${fmt(h.pm10, 'μg/m³')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${AirQualityService.attribution}。近地面浓度；山脊若在逆温层之上，实际空气可能明显好于此值。',
                  style: TextStyle(fontSize: 11, height: 1.4, color: muted),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
