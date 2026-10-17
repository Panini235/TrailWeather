import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'weather_provider.dart';

/// 天气图（降水 / 云量）的格点场（D-035）。
///
/// 数据：Open-Meteo 模式预报（best_match），按视野内规则格点批量请求；
/// 不是雷达或卫星实况。格点之间的平滑只用于显示，取值仍是格点上的来源值；
/// 降水为该时刻前一小时累计（Open-Meteo precipitation 语义）。
enum FieldVar {
  precip('precipitation'),
  cloud('cloud_cover'),
  cloudLow('cloud_cover_low'),
  cloudMid('cloud_cover_mid'),
  cloudHigh('cloud_cover_high');

  const FieldVar(this.api);
  final String api;
}

/// 视野范围（WGS-84 度）。
class FieldBounds {
  const FieldBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south, west, north, east;

  bool contains(FieldBounds o) =>
      o.south >= south && o.north <= north && o.west >= west && o.east <= east;

  double get latSpan => north - south;
  double get lonSpan => east - west;

  /// 向四周扩展 [f]（比例），并保证最小跨度（放大到街区级时仍取一片区域）。
  FieldBounds expanded(double f, {double minLat = 0.45, double minLon = 0.6}) {
    final cy = (north + south) / 2, cx = (east + west) / 2;
    final h = math.max(latSpan * (1 + 2 * f), minLat) / 2;
    final w = math.max(lonSpan * (1 + 2 * f), minLon) / 2;
    return FieldBounds(
      south: math.max(cy - h, -85),
      north: math.min(cy + h, 85),
      west: cx - w,
      east: cx + w,
    );
  }
}

/// 一次请求得到的格点场。行按墨卡托 y 等距（北 → 南），列按经度等距（西 → 东），
/// 这样在网络地图上格点是均匀的，按格点画三角网不会变形。
class FieldGrid {
  FieldGrid({
    required this.bounds,
    required this.cols,
    required this.rows,
    required this.lats,
    required this.lons,
    required this.timesUtc,
    required this.values,
    required this.fetchedAtUtc,
  });

  final FieldBounds bounds;
  final int cols, rows;
  final List<double> lats; // rows 个，北 → 南
  final List<double> lons; // cols 个，西 → 东
  final List<DateTime> timesUtc;

  /// [var][时次] → rows*cols（行优先）；缺失为 NaN。
  final Map<FieldVar, List<Float32List>> values;
  final DateTime fetchedAtUtc;

  /// 列间距（km，按中心纬度），用于“网格约 X km”标注。
  double get spacingKm {
    final midLat = lats[rows ~/ 2] * math.pi / 180;
    return (lons[1] - lons[0]) * 111.32 * math.cos(midLat);
  }

  double? at(FieldVar v, int t, int r, int c) {
    final x = values[v]?[t][r * cols + c];
    return x == null || x.isNaN ? null : x;
  }

  /// 离 [utc] 最近的时次下标；超出范围返回 null。
  int? timeIndexOf(DateTime utc) {
    for (var i = 0; i < timesUtc.length; i++) {
      final d = utc.difference(timesUtc[i]);
      if (!d.isNegative && d < const Duration(hours: 1)) return i;
    }
    return null;
  }
}

double _mercY(double lat) {
  final r = lat * math.pi / 180;
  return math.log(math.tan(math.pi / 4 + r / 2));
}

double _latOfMercY(double y) =>
    (2 * math.atan(math.exp(y)) - math.pi / 2) * 180 / math.pi;

/// 按视野宽高比分配格点数（总数不超过 [maxPoints]）。
(int cols, int rows) gridShape(double aspect, {int maxPoints = 120}) {
  final a = aspect.clamp(0.25, 4.0);
  var cols = math.sqrt(maxPoints * a).round().clamp(4, 16);
  var rows = (maxPoints / cols).floor().clamp(4, 16);
  while (cols * rows > maxPoints) {
    rows--;
  }
  return (cols, rows);
}

class WeatherFieldService {
  WeatherFieldService({StringFetcher? fetcher, DateTime Function()? now})
    : fetcher = fetcher ?? defaultFetcher(),
      _now = now ?? (() => DateTime.now().toUtc());

  final StringFetcher fetcher;
  final DateTime Function() _now;

  static const hours = 48;
  static const ttl = Duration(minutes: 30);

  FieldGrid? _last;

  /// 视野 [view] 已被上次结果覆盖且未过期时直接复用（拖动地图不重复请求）。
  FieldGrid? cachedFor(FieldBounds view) {
    final g = _last;
    if (g == null) return null;
    if (_now().difference(g.fetchedAtUtc) > ttl) return null;
    // 视野比上次小很多时格点太稀，重新请求更密的格点。
    if (!g.bounds.contains(view)) return null;
    if (view.lonSpan < g.bounds.lonSpan / 3 && g.bounds.lonSpan > 0.7) {
      return null;
    }
    return g;
  }

  Future<FieldGrid> fetch(
    FieldBounds view, {
    required double aspect,
    CancelToken? cancelToken,
  }) async {
    final hit = cachedFor(view);
    if (hit != null) return hit;
    final b = view.expanded(0.15);
    final (cols, rows) = gridShape(aspect);
    final yN = _mercY(b.north), yS = _mercY(b.south);
    final lats = [
      for (var r = 0; r < rows; r++)
        _latOfMercY(yN + (yS - yN) * r / (rows - 1)),
    ];
    final lons = [
      for (var c = 0; c < cols; c++)
        b.west + (b.east - b.west) * c / (cols - 1),
    ];
    final latParam = <String>[], lonParam = <String>[];
    for (final la in lats) {
      for (final lo in lons) {
        latParam.add(la.toStringAsFixed(3));
        lonParam.add(lo.toStringAsFixed(3));
      }
    }
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latParam.join(','),
      'longitude': lonParam.join(','),
      'hourly': [for (final v in FieldVar.values) v.api].join(','),
      'models': 'best_match',
      'timezone': 'UTC',
      'forecast_hours': '$hours',
    });
    final body = await fetcher(uri, cancelToken: cancelToken);
    final grid = parse(
      body,
      bounds: b,
      cols: cols,
      rows: rows,
      lats: lats,
      lons: lons,
      fetchedAtUtc: _now(),
    );
    _last = grid;
    return grid;
  }

  /// 解析多坐标响应（与请求顺序一致，行优先）。
  static FieldGrid parse(
    String body, {
    required FieldBounds bounds,
    required int cols,
    required int rows,
    required List<double> lats,
    required List<double> lons,
    required DateTime fetchedAtUtc,
  }) {
    final decoded = jsonDecode(body);
    final arr = decoded is List ? decoded : [decoded];
    if (arr.length != cols * rows) {
      throw FormatException('格点数不符：${arr.length} ≠ ${cols * rows}');
    }
    final first =
        (arr.first as Map<String, dynamic>)['hourly'] as Map<String, dynamic>;
    final times = [
      for (final t in (first['time'] as List? ?? const []))
        DateTime.parse('${t}Z'),
    ];
    final values = <FieldVar, List<Float32List>>{
      for (final v in FieldVar.values)
        v: [
          for (var t = 0; t < times.length; t++)
            Float32List(cols * rows)..fillRange(0, cols * rows, double.nan),
        ],
    };
    for (var i = 0; i < arr.length; i++) {
      final h =
          (arr[i] as Map<String, dynamic>)['hourly'] as Map<String, dynamic>?;
      if (h == null) continue;
      for (final v in FieldVar.values) {
        final list = h[v.api] as List?;
        if (list == null) continue;
        for (var t = 0; t < times.length && t < list.length; t++) {
          final x = list[t] as num?;
          if (x != null) values[v]![t][i] = x.toDouble();
        }
      }
    }
    return FieldGrid(
      bounds: bounds,
      cols: cols,
      rows: rows,
      lats: lats,
      lons: lons,
      timesUtc: times,
      values: values,
      fetchedAtUtc: fetchedAtUtc,
    );
  }
}
