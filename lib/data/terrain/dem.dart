import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// 公开高程数据（DEM）瓦片（D-039）：AWS 开放数据 Terrain Tiles（Mapzen / Tilezen joerd），
/// Terrarium 编码 PNG，高程 = R×256 + G + B/256 − 32768（米）。
///
/// - 中国境内 7–15 级来自 SRTM（30 m 网格，标称质量约 90 m），4–6 级为 GMTED2010；
///   SRTM / GMTED 属美国公有领域，署名 USGS。绝对高程误差十几米，陡坡、峡谷更大；
/// - 2026-10-17 实测国内直连单块约 1.3 s、20–30 KB；与 Open-Meteo 高程（Copernicus 90 m）
///   在北京平原、香山、泰山顶相差 2–20 m；
/// - 只用作显示与估算：等高线、地形阴影、手绘线路的海拔剖面。显示层必须遵守
///   《公开地图内容表示规范》（2023）：等高距大于 20 m、高程不优于 15 m（见 terrain_compute.dart）。
class DemTileKey {
  const DemTileKey(this.z, this.x, this.y);

  final int z, x, y;

  DemTileKey get parent => DemTileKey(z - 1, x >> 1, y >> 1);

  @override
  bool operator ==(Object other) =>
      other is DemTileKey && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => '$z/$x/$y';
}

/// 墨卡托世界像素坐标（256 像素一块瓦片）。
(double, double) worldPixel(double lat, double lon, int z) {
  final n = 256.0 * (1 << z);
  final r = lat.clamp(-85.05, 85.05) * math.pi / 180;
  return (
    (lon + 180) / 360 * n,
    (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n,
  );
}

LatLng latLngOfWorldPixel(double x, double y, int z) {
  final n = 256.0 * (1 << z);
  final m = math.pi * (1 - 2 * y / n);
  final lat = math.atan((math.exp(m) - math.exp(-m)) / 2) * 180 / math.pi;
  return LatLng(lat, x / n * 360 - 180);
}

/// Terrarium RGBA → 高程（米）。
Float32List terrariumToElevation(Uint8List rgba) {
  final n = rgba.length ~/ 4;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final o = i * 4;
    out[i] = rgba[o] * 256.0 + rgba[o + 1] + rgba[o + 2] / 256.0 - 32768.0;
  }
  return out;
}

class DemTile {
  DemTile(this.key, this.elevations) : assert(elevations.length == size * size);

  static const size = 256;

  final DemTileKey key;

  /// 行优先（北 → 南），每个值代表一个像素格的中心。
  final Float32List elevations;

  /// 瓦片内像素坐标 (px, py)（0–256，左上角为原点）处的双线性高程。
  double sampleAt(double px, double py) {
    final x = (px - 0.5).clamp(0.0, size - 1.0);
    final y = (py - 0.5).clamp(0.0, size - 1.0);
    final x0 = math.min(x.floor(), size - 2),
        y0 = math.min(y.floor(), size - 2);
    final tx = x - x0, ty = y - y0;
    final e = elevations;
    final i = y0 * size + x0;
    final top = e[i] * (1 - tx) + e[i + 1] * tx;
    final bottom = e[i + size] * (1 - tx) + e[i + size + 1] * tx;
    return top * (1 - ty) + bottom * ty;
  }

  /// 瓦片中心纬度处一个像素的地面宽度（米）。
  double get metersPerPixel {
    final c = latLngOfWorldPixel(
      (key.x + 0.5) * size,
      (key.y + 0.5) * size,
      key.z,
    );
    return 156543.03392 * math.cos(c.latitude * math.pi / 180) / (1 << key.z);
  }
}

typedef BytesFetcher = Future<Uint8List> Function(
  Uri uri, {
  CancelToken? cancelToken,
});

/// PNG → 非预乘 RGBA 字节。
typedef PngDecoder = Future<Uint8List> Function(Uint8List png);

BytesFetcher defaultBytesFetcher() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      responseType: ResponseType.bytes,
    ),
  );
  return (uri, {cancelToken}) async {
    final r = await dio.getUri<List<int>>(uri, cancelToken: cancelToken);
    return Uint8List.fromList(r.data ?? const []);
  };
}

/// 用引擎解码 PNG（Terrarium 瓦片不透明，没有色彩配置，解码后数值不变）。
Future<Uint8List> decodePngRgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    frame.image.dispose();
    if (data == null) throw const FormatException('高程瓦片解码失败');
    return data.buffer.asUint8List();
  } finally {
    codec.dispose();
  }
}

/// 高程瓦片的下载、解码与内存缓存。新瓦片就绪时通知监听者（图层重绘、剖面重算）。
///
/// 请求纪律：同一瓦片并发请求合并；最多 6 个同时下载；失败的瓦片 1 分钟内不重试。
class DemService extends ChangeNotifier {
  DemService({
    BytesFetcher? fetcher,
    PngDecoder? decoder,
    DateTime Function()? now,
    this.capacity = 96,
  }) : _fetch = fetcher ?? defaultBytesFetcher(),
       _decode = decoder ?? decodePngRgba,
       _now = now ?? DateTime.now;

  final BytesFetcher _fetch;
  final PngDecoder _decode;
  final DateTime Function() _now;

  /// 内存里最多保留的瓦片数（每块 256 KB）。
  final int capacity;

  /// SRTM 30 m 对应约 12 级；更大比例尺用 12 级数据插值显示。
  static const maxZoom = 12;
  static const minZoom = 6;
  static const _maxParallel = 6;
  static const _retryAfter = Duration(minutes: 1);

  static const attribution = '高程：Terrain Tiles（AWS 开放数据）· SRTM / GMTED（USGS）';

  static Uri tileUri(DemTileKey k) => Uri.https(
    's3.amazonaws.com',
    '/elevation-tiles-prod/terrarium/${k.z}/${k.x}/${k.y}.png',
  );

  final _cache = <DemTileKey, DemTile>{}; // 插入有序：最近使用的在末尾
  final _inflight = <DemTileKey, Future<DemTile?>>{};
  final _failedAt = <DemTileKey, DateTime>{};
  final _queue = Queue<Completer<void>>();
  int _running = 0;
  bool _disposed = false;

  DemTile? cached(DemTileKey k) {
    final t = _cache.remove(k);
    if (t != null) _cache[k] = t; // 最近使用移到末尾
    return t;
  }

  bool isLoading(DemTileKey k) => _inflight.containsKey(k);

  /// 取瓦片；已缓存直接返回。网络或解码失败返回 null（1 分钟内不再重试，
  /// 除非 [retry]：用户点了“重试”）。
  Future<DemTile?> load(DemTileKey k, {bool retry = false}) {
    final hit = cached(k);
    if (hit != null) return Future.value(hit);
    final failed = _failedAt[k];
    if (!retry && failed != null && _now().difference(failed) < _retryAfter) {
      return Future.value(null);
    }
    return _inflight[k] ??= _download(k).whenComplete(() {
      // 不能写成 `=> _inflight.remove(k)`：remove 返回的正是这个 Future，whenComplete 会等它自己。
      _inflight.remove(k);
    });
  }

  Future<DemTile?> _download(DemTileKey k) async {
    await _slot();
    try {
      final rgba = await _decode(await _fetch(tileUri(k)));
      if (rgba.length != DemTile.size * DemTile.size * 4) {
        throw const FormatException('高程瓦片尺寸不符');
      }
      final tile = DemTile(k, terrariumToElevation(rgba));
      _cache[k] = tile;
      while (_cache.length > capacity) {
        _cache.remove(_cache.keys.first);
      }
      _failedAt.remove(k);
      if (!_disposed) notifyListeners();
      return tile;
    } catch (_) {
      _failedAt[k] = _now();
      return null;
    } finally {
      _release();
    }
  }

  Future<void> _slot() {
    if (_running < _maxParallel) {
      _running++;
      return Future.value();
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future;
  }

  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    } else {
      _running--;
    }
  }

  /// 某点的高程（只读缓存，未缓存返回 null）。
  double? elevationAt(LatLng p, {int z = maxZoom}) {
    final (x, y) = worldPixel(p.latitude, p.longitude, z);
    final k = DemTileKey(z, x ~/ 256, y ~/ 256);
    final t = cached(k);
    return t?.sampleAt(x - k.x * 256, y - k.y * 256);
  }

  /// 覆盖经纬度范围的瓦片。
  static Set<DemTileKey> tilesForBounds({
    required double south,
    required double west,
    required double north,
    required double east,
    required int z,
  }) {
    final (x0, y0) = worldPixel(north, west, z);
    final (x1, y1) = worldPixel(south, east, z);
    final n = 1 << z;
    return {
      for (
        var x = (x0 ~/ 256).clamp(0, n - 1);
        x <= (x1 ~/ 256).clamp(0, n - 1);
        x++
      )
        for (
          var y = (y0 ~/ 256).clamp(0, n - 1);
          y <= (y1 ~/ 256).clamp(0, n - 1);
          y++
        )
          DemTileKey(z, x, y),
    };
  }

  /// 覆盖这些点的瓦片。
  static Set<DemTileKey> tilesForPoints(Iterable<LatLng> points, int z) => {
    for (final p in points)
      () {
        final (x, y) = worldPixel(p.latitude, p.longitude, z);
        return DemTileKey(z, x ~/ 256, y ~/ 256);
      }(),
  };

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
