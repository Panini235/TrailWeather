import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/app_providers.dart';
import '../../data/routes/route_sampling.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/weather_repository.dart';
import '../detail/environment_cards.dart';
import '../detail/weather_cells.dart';
import '../strings.dart';
import '../weather_refresh_clock.dart';
import '../widgets/common.dart';

/// 单点天气请求。首页当前位置标签与本面板使用同一参数，标签取到的数据
/// 在打开面板时可直接命中缓存。
Future<RouteWeatherBundle> fetchPointWeather(
  WeatherRepository repository, {
  required String providerId,
  required LatLng point,
  required String label,
  required DateTime requestedAtUtc,
  bool refresh = false,
}) => watchPointWeather(
  repository,
  providerId: providerId,
  point: point,
  label: label,
  requestedAtUtc: requestedAtUtc,
  refresh: refresh,
).last;

Stream<RouteWeatherBundle> watchPointWeather(
  WeatherRepository repository, {
  required String providerId,
  required LatLng point,
  required String label,
  required DateTime requestedAtUtc,
  bool refresh = false,
}) {
  final hour = DateTime.utc(
    requestedAtUtc.year,
    requestedAtUtc.month,
    requestedAtUtc.day,
    requestedAtUtc.hour,
  );
  return repository.watchRouteWeatherBundle(
    providerId: providerId,
    nodes: [
      RouteNode(
        pointIndex: 0,
        pos: point,
        elevationM: null,
        distFromStartM: 0,
        label: label,
      ),
    ],
    startUtc: hour,
    endUtc: hour.add(const Duration(hours: 24)),
    refresh: refresh,
  );
}

/// 与请求时刻最接近的小时数据；相差超过 3 小时视为无当前时段数据。
WxHourValue? nearestPointHour(WxPointForecast point, DateTime requestedAtUtc) {
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

/// 地图任意点天气面板。每个来源独立请求、独立展示，不做跨来源平均。
class PointWeatherSheet extends ConsumerStatefulWidget {
  const PointWeatherSheet({
    super.key,
    required this.point,
    required this.label,
    required this.requestedAtUtc,
    this.locationAtUtc,
  });

  final LatLng point;
  final String label;
  final DateTime requestedAtUtc;
  final DateTime? locationAtUtc;

  @override
  ConsumerState<PointWeatherSheet> createState() => _PointWeatherSheetState();
}

class _PointWeatherSheetState extends ConsumerState<PointWeatherSheet> {
  late final WeatherRefreshClock _clock;
  LatLng get point => widget.point;
  String get label => widget.label;
  DateTime get requestedAtUtc => _clock.value;

  @override
  void initState() {
    super.initState();
    _clock = WeatherRefreshClock(
      initialUtc: widget.requestedAtUtc,
      nowUtc: ref.read(weatherNowProvider),
    )..addListener(_onTimeChanged);
  }

  void _onTimeChanged() => setState(() {});

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            S.pointWxCoordsAndTime(
              point.latitude.toStringAsFixed(5),
              point.longitude.toStringAsFixed(5),
              _formatLocal(requestedAtUtc.toLocal()),
            ),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (widget.locationAtUtc != null)
            Text(
              S.pointWxLocationReadAt(
                _formatLocal(widget.locationAtUtc!.toLocal()),
              ),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 10),
          const GranularityNotice(text: S.pointWxGridNote),
          const SizedBox(height: 10),
          AltitudeWeatherCard(point: point, atUtc: requestedAtUtc),
          const SizedBox(height: 8),
          AirQualityCard(point: point, atUtc: requestedAtUtc),
          const SizedBox(height: 10),
          for (final provider in providers)
            if (enabled.contains(provider.caps.providerId))
              _PointSourceCard(
                key: ValueKey((
                  provider.caps.providerId,
                  point,
                  requestedAtUtc,
                )),
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
      '${S.mapMonthDay(time.month, time.day)} '
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

class _PointSourceCard extends ConsumerStatefulWidget {
  const _PointSourceCard({
    super.key,
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
  /// 按次计费来源（caps.onDemandOnly）不自动请求：null 表示等待用户点击查询。
  late Stream<RouteWeatherBundle>? _stream =
      ref
          .read(weatherProvidersProvider)
          .firstWhere((p) => p.caps.providerId == widget.providerId)
          .caps
          .onDemandOnly
      ? null
      : _fetch();

  Stream<RouteWeatherBundle> _fetch({bool refresh = false}) =>
      watchPointWeather(
        ref.read(weatherRepositoryProvider),
        providerId: widget.providerId,
        point: widget.point,
        label: widget.label,
        requestedAtUtc: widget.requestedAtUtc,
        refresh: refresh,
      );

  @override
  void didUpdateWidget(covariant _PointSourceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.point != widget.point ||
        oldWidget.requestedAtUtc != widget.requestedAtUtc ||
        oldWidget.providerId != widget.providerId) {
      final onDemand = ref
          .read(weatherProvidersProvider)
          .firstWhere((p) => p.caps.providerId == widget.providerId)
          .caps
          .onDemandOnly;
      // 每个新时段的计费查询仍需用户主动触发。
      _stream = onDemand ? null : _fetch();
    }
  }

  void _retry() {
    setState(() {
      _stream = _fetch(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref
        .watch(weatherProvidersProvider)
        .firstWhere((p) => p.caps.providerId == widget.providerId)
        .caps;

    if (_stream == null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SourceBadge(caps: caps),
              const SizedBox(height: 8),
              OnDemandQueryPrompt(
                caps: caps,
                onQuery: () => setState(() {
                  _stream = _fetch();
                }),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: StreamBuilder<RouteWeatherBundle>(
          stream: _stream,
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
                title: S.pointWxSourceFailed(caps.displayName),
                detail: snapshot.error.toString(),
                onRetry: _retry,
              );
            }

            if (!snapshot.hasData) return const SizedBox.shrink();
            final result = snapshot.data!.result;
            if (result.points.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SourceBadge(caps: caps),
                  const SizedBox(height: 8),
                  const MissingValueText(label: S.pointWxNoLocationData),
                ],
              );
            }
            final forecast = result.points.first;
            final nearest = nearestPointHour(forecast, widget.requestedAtUtc);
            if (nearest == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SourceBadge(caps: caps),
                  const SizedBox(height: 8),
                  WeatherCacheNotice(result: result, onRetry: _retry),
                  const MissingValueText(label: S.pointWxNoPeriodData),
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
                WeatherCacheNotice(result: result, onRetry: _retry),
                const SizedBox(height: 8),
                Text(
                  '${S.pointWxValidTime(S.mapMonthDay(nearest.validFromUtc.toLocal().month, nearest.validFromUtc.toLocal().day))} '
                  '${nearest.validFromUtc.toLocal().hour.toString().padLeft(2, '0')}:00'
                  '${difference == 0 ? '' : S.pointWxMinutesOff(difference)}',
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
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
