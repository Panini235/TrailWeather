import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/app_providers.dart';
import '../../data/routes/route_sampling.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/weather_repository.dart';
import '../detail/weather_cells.dart';
import '../strings.dart';
import '../widgets/common.dart';

/// 地图任意点天气面板。每个来源独立请求、独立展示，不做跨来源平均。
class PointWeatherSheet extends ConsumerWidget {
  const PointWeatherSheet({
    super.key,
    required this.point,
    required this.label,
    required this.requestedAtUtc,
  });

  final LatLng point;
  final String label;
  final DateTime requestedAtUtc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final providers = ref.watch(weatherProvidersProvider);
    final enabled = settings.enabledProviderIds;

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: [
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'WGS-84 ${point.latitude.toStringAsFixed(5)}, '
            '${point.longitude.toStringAsFixed(5)} · '
            '${_formatLocal(requestedAtUtc.toLocal())}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          const GranularityNotice(
            text:
                '这里展示的是所选坐标附近的网格预报，不是该点实测。'
                '各来源独立显示，返回坐标、网格颗粒度和缺失项以来源说明为准。',
          ),
          const SizedBox(height: 10),
          for (final provider in providers)
            if (enabled.contains(provider.caps.providerId))
              _PointSourceCard(
                providerId: provider.caps.providerId,
                point: point,
                label: label,
                requestedAtUtc: requestedAtUtc,
                settings: settings,
              ),
        ],
      ),
    );
  }

  static String _formatLocal(DateTime time) =>
      '${time.month}月${time.day}日 '
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

class _PointSourceCard extends ConsumerStatefulWidget {
  const _PointSourceCard({
    required this.providerId,
    required this.point,
    required this.label,
    required this.requestedAtUtc,
    required this.settings,
  });

  final String providerId;
  final LatLng point;
  final String label;
  final DateTime requestedAtUtc;
  final AppSettings settings;

  @override
  ConsumerState<_PointSourceCard> createState() => _PointSourceCardState();
}

class _PointSourceCardState extends ConsumerState<_PointSourceCard> {
  late Future<RouteWeatherBundle> _future = _fetch();

  Future<RouteWeatherBundle> _fetch({bool refresh = false}) {
    final hour = DateTime.utc(
      widget.requestedAtUtc.year,
      widget.requestedAtUtc.month,
      widget.requestedAtUtc.day,
      widget.requestedAtUtc.hour,
    );
    return ref
        .read(weatherRepositoryProvider)
        .getRouteWeatherBundle(
          providerId: widget.providerId,
          nodes: [
            RouteNode(
              pointIndex: 0,
              pos: widget.point,
              elevationM: null,
              distFromStartM: 0,
              label: widget.label,
            ),
          ],
          startUtc: hour,
          endUtc: hour.add(const Duration(hours: 24)),
          refresh: refresh,
        );
  }

  void _retry() {
    setState(() => _future = _fetch(refresh: true));
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref
        .watch(weatherProvidersProvider)
        .firstWhere((p) => p.caps.providerId == widget.providerId)
        .caps;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<RouteWeatherBundle>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SourceBadge(caps: caps),
                  const SizedBox(height: 18),
                  const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 18),
                ],
              );
            }
            if (snapshot.hasError) {
              return ErrorCard(
                title: '${caps.displayName} 请求失败',
                detail: snapshot.error.toString(),
                onRetry: _retry,
              );
            }

            final result = snapshot.data!.result;
            if (result.points.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SourceBadge(caps: caps),
                  const SizedBox(height: 8),
                  const MissingValueText(label: '该来源未返回此位置数据'),
                ],
              );
            }
            final forecast = result.points.first;
            final nearest = _nearest(forecast, widget.requestedAtUtc);
            if (nearest == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SourceBadge(caps: caps),
                  const SizedBox(height: 8),
                  const MissingValueText(label: '该来源未返回当前时段数据'),
                ],
              );
            }
            final provenance = forecast.provenance;
            final difference = nearest.validFromUtc
                .difference(widget.requestedAtUtc)
                .inMinutes
                .abs();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    SourceBadge(caps: caps),
                    DataKindChip(kind: caps.dataKind),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '有效时次 ${nearest.validFromUtc.toLocal().month}月'
                  '${nearest.validFromUtc.toLocal().day}日 '
                  '${nearest.validFromUtc.toLocal().hour.toString().padLeft(2, '0')}:00'
                  '${difference == 0 ? '' : ' · 相差 $difference 分钟'}',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 8),
                WxVarGrid(wx: nearest, settings: widget.settings),
                const SizedBox(height: 6),
                GranularityNotice(text: provenance.granularityStatement()),
                const SizedBox(height: 4),
                Text(
                  '${S.fetchedAt}：'
                  '${provenance.fetchedAtUtc.toIso8601String().substring(0, 16)} UTC'
                  '${result.stale ? ' · ${S.staleData}' : ''}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  WxHourValue? _nearest(WxPointForecast point, DateTime requestedAtUtc) {
    WxHourValue? best;
    var bestMinutes = 1 << 30;
    for (final hour in point.hours) {
      final minutes = hour.validFromUtc
          .difference(requestedAtUtc)
          .inMinutes
          .abs();
      if (minutes < bestMinutes) {
        best = hour;
        bestMinutes = minutes;
      }
    }
    return bestMinutes <= 180 ? best : null;
  }
}
