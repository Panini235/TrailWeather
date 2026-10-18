import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trailweather/data/map/tile_cache.dart';

// T-169：高德直连偶发回 200 + 空白图，被 flutter_map 内置缓存留住。
// 下面用测试替身复现：内存缓存代替磁盘缓存，MockClient 代替高德服务器，
// 不访问网络。真实高德空白瓦片的字节与响应头未采到（云端无法直连高德），
// 这里用纯色 PNG、不带 Cache-Control（flutter_map 按 7 天保鲜）模拟。

const _amapTemplate =
    'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}';
const _amapUrl =
    'https://webrd04.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x=1&y=2&z=3';
const _osmUrl = 'https://tile.openstreetmap.org/3/1/2.png';

/// 内存版 MapCachingProvider，行为与内置缓存一致：有 bytes 就覆盖，无 bytes 只更新元数据。
class _MemoryCache implements MapCachingProvider {
  final tiles = <String, CachedMapTile>{};

  @override
  bool get isSupported => true;

  @override
  Future<CachedMapTile?> getTile(String url) async => tiles[url];

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    final b = bytes ?? tiles[url]?.bytes;
    if (b != null) tiles[url] = (bytes: b, metadata: metadata);
  }
}

/// 生成 256×256 PNG；[stripe] 为 true 时左半边画一条深色块（模拟有内容的瓦片）。
Future<Uint8List> _png(ui.Color color, {bool stripe = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 256, 256),
    ui.Paint()..color = color,
  );
  if (stripe) {
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 100, 128, 20),
      ui.Paint()..color = const ui.Color(0xFF333333),
    );
  }
  final image = await recorder.endRecording().toImage(256, 256);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// 走一遍 flutter_map 的真实瓦片加载路径，返回 (0,110) 处像素（条纹所在行）。
Future<int> _loadPixel(NetworkTileProvider provider) async {
  final imageProvider = provider.getImageWithCancelLoadingSupport(
    const TileCoordinates(1, 2, 3),
    TileLayer(
      urlTemplate: _amapTemplate,
      subdomains: const ['1', '2', '3', '4'],
    ),
    Completer<void>().future,
  );
  final done = Completer<ui.Image>();
  final stream = imageProvider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener(
    (info, _) => done.complete(info.image),
    onError: (e, _) => done.completeError(e),
  );
  stream.addListener(listener);
  final image = await done.future;
  stream.removeListener(listener);
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  // flutter_map 不等待 putTile，这里让写缓存跑完。
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return rgba.getUint32((110 * 256) * 4);
}

/// 相当于重开 App：清掉 Flutter 内存中的图片缓存，只剩磁盘缓存（这里是内存替身）。
void _restart() => PaintingBinding.instance.imageCache
  ..clear()
  ..clearLiveImages();

void main() {
  group('isUniformRgba', () {
    test('同色与全透明为空白，有不同像素则不是', () {
      expect(
        isUniformRgba(Uint8List.fromList([9, 9, 9, 255, 10, 8, 9, 255])),
        isTrue,
      );
      expect(
        isUniformRgba(Uint8List.fromList([0, 0, 0, 0, 255, 1, 7, 0])),
        isTrue,
      );
      expect(
        isUniformRgba(Uint8List.fromList([9, 9, 9, 255, 60, 9, 9, 255])),
        isFalse,
      );
      expect(
        isUniformRgba(Uint8List.fromList([0, 0, 0, 0, 9, 9, 9, 255])),
        isFalse,
      );
    });
  });

  group('AmapTileCacheGuard', () {
    final meta7d = CachedMapTileMetadata(
      staleAt: DateTime.utc(2026, 10, 25),
      lastModified: null,
      etag: 'e1',
    );
    final now = DateTime.utc(2026, 10, 18);

    AmapTileCacheGuard guard(_MemoryCache inner) => AmapTileCacheGuard(
      inner: inner,
      isBlank: (b) async => b.first == 0,
      now: () => now,
    );

    test('高德空白瓦片不写入，读到旧空白瓦片当作未命中', () async {
      final inner = _MemoryCache();
      final g = guard(inner);
      await g.putTile(
        url: _amapUrl,
        metadata: meta7d,
        bytes: Uint8List.fromList([0]),
      );
      expect(inner.tiles, isEmpty);

      inner.tiles[_amapUrl] = (
        bytes: Uint8List.fromList([0]),
        metadata: meta7d,
      );
      expect(await g.getTile(_amapUrl), isNull);
    });

    test('高德正常瓦片写入，保鲜期截到 1 天并保留 etag', () async {
      final inner = _MemoryCache();
      final g = guard(inner);
      await g.putTile(
        url: _amapUrl,
        metadata: meta7d,
        bytes: Uint8List.fromList([1]),
      );
      final t = inner.tiles[_amapUrl]!;
      expect(t.metadata.staleAt, now.add(amapMaxFreshAge));
      expect(t.metadata.etag, 'e1');
      expect(await g.getTile(_amapUrl), isNotNull);
    });

    test('非高德瓦片原样透传', () async {
      final inner = _MemoryCache();
      final g = guard(inner);
      await g.putTile(
        url: _osmUrl,
        metadata: meta7d,
        bytes: Uint8List.fromList([0]),
      );
      expect(inner.tiles[_osmUrl]!.metadata.staleAt, meta7d.staleAt);
      expect(await g.getTile(_osmUrl), isNotNull);
    });
  });

  group('flutter_map 加载路径（T-169 复现）', () {
    setUp(_restart);

    const white = 0xF8F8F8FF;
    late Uint8List blank;
    late Uint8List good;
    Future<void> fixtures() async {
      blank = await _png(const ui.Color(0xFFF8F8F8));
      good = await _png(const ui.Color(0xFFF8F8F8), stripe: true);
    }

    // 服务器第一次回空白，之后恢复正常。
    http.Client server(List<int> calls) => MockClient((req) async {
      calls.add(1);
      return http.Response.bytes(calls.length == 1 ? blank : good, 200);
    });

    testWidgets('isBlankTile 识别纯色 PNG，放过有内容的瓦片', (tester) async {
      await tester.runAsync(() async {
        await fixtures();
        expect(await isBlankTile(blank), isTrue);
        expect(await isBlankTile(good), isFalse);
        expect(await isBlankTile(Uint8List(0)), isTrue);
        expect(await isBlankTile(Uint8List.fromList([1, 2, 3])), isTrue);
      });
    });

    testWidgets('不加守卫：空白瓦片被缓存，重开后仍显示空白（问题复现）', (tester) async {
      await tester.runAsync(() async {
        await fixtures();
        final calls = <int>[];
        final provider = NetworkTileProvider(
          httpClient: server(calls),
          cachingProvider: _MemoryCache(),
        );
        expect(await _loadPixel(provider), white);
        _restart(); // 相当于重开 App
        expect(await _loadPixel(provider), white);
        expect(calls, hasLength(1), reason: '第二次直接读了缓存里的空白瓦片');
      });
    });

    testWidgets('加守卫：空白瓦片不缓存，重开后重新请求拿到正常瓦片', (tester) async {
      await tester.runAsync(() async {
        await fixtures();
        final calls = <int>[];
        final cache = _MemoryCache();
        final provider = NetworkTileProvider(
          httpClient: server(calls),
          cachingProvider: AmapTileCacheGuard(inner: cache),
        );
        expect(await _loadPixel(provider), white); // 服务器给的就是空白，照实显示
        expect(cache.tiles, isEmpty);
        _restart();
        expect(await _loadPixel(provider), isNot(white));
        expect(calls, hasLength(2));
        expect(cache.tiles, contains(_amapUrl));
      });
    });

    testWidgets('加守卫：旧版本已缓存的空白瓦片会被重新请求覆盖', (tester) async {
      await tester.runAsync(() async {
        await fixtures();
        final cache = _MemoryCache()
          ..tiles[_amapUrl] = (
            bytes: blank,
            metadata: CachedMapTileMetadata(
              staleAt: DateTime.timestamp().add(const Duration(days: 7)),
              lastModified: null,
              etag: null,
            ),
          );
        final calls = <int>[1]; // 跳过“第一次空白”，服务器直接回正常瓦片
        final provider = NetworkTileProvider(
          httpClient: server(calls),
          cachingProvider: AmapTileCacheGuard(inner: cache),
        );
        expect(await _loadPixel(provider), isNot(white));
        expect(calls, hasLength(2));
        expect(cache.tiles[_amapUrl]!.bytes, good);
      });
    });
  });
}
