/// 高德瓦片的磁盘缓存守卫（T-169）。
///
/// flutter_map 8 的 `NetworkTileImageProvider` 只要服务器回 200 就把响应原样写进
/// 内置缓存（`BuiltInMapCachingProvider`），不检查内容；没有 Cache-Control 时按
/// 7 天保鲜，期间直接读缓存、不再请求服务器。高德无 Key 直连偶尔回 200 + 空白图，
/// 这张空白图于是在同一缩放级别一直显示，直到清除应用数据。
///
/// [AmapTileCacheGuard] 包在内置缓存外面，只作用于高德瓦片：
/// - 空白瓦片（整张同一颜色，或无法解码）不写入缓存，读缓存时命中的旧空白瓦片也
///   当作未命中，强制向服务器重新请求；
/// - 保鲜期最长 [amapMaxFreshAge]，漏网的异常瓦片最多留存这么久。
///
/// 不伪造瓦片：识别出空白只决定“不缓存、重新请求”，显示的仍是服务器返回的内容。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_map/flutter_map.dart';

/// 高德瓦片缓存的最长保鲜期。过期后带条件头重新验证（服务器支持时只回 304）。
const amapMaxFreshAge = Duration(days: 1);

/// 高德瓦片域名（webrd0x / webst0x.is.autonavi.com）。
bool isAmapTileUrl(Uri url) => url.host.endsWith('.is.autonavi.com');

/// 判断瓦片字节是否不值得缓存：返回 true 表示空白或不是可解码的图片。
typedef BlankTileDetector = Future<bool> Function(Uint8List bytes);

/// 纯色瓦片编码后很小（PNG 几百字节、JPEG 一两 KB）；更大的瓦片不解码检查，
/// 避免每张瓦片都多解码一次。
const _maxBlankCandidateBytes = 4096;

/// 每个通道允许的差值，容忍 JPEG 压缩噪声。
const _channelTolerance = 2;

/// 默认空白识别：空字节、无法解码，或解码后所有像素同一颜色（含全透明）。
Future<bool> isBlankTile(Uint8List bytes) async {
  if (bytes.isEmpty) return true;
  if (bytes.length > _maxBlankCandidateBytes) return false;
  final ui.Image image;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    image = (await codec.getNextFrame()).image;
    codec.dispose();
  } catch (_) {
    return true;
  }
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return false;
    return isUniformRgba(data.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

/// RGBA 像素是否全部同一颜色（每通道容差 [_channelTolerance]）。
bool isUniformRgba(Uint8List rgba) {
  if (rgba.length < 4) return true;
  final r = rgba[0], g = rgba[1], b = rgba[2], a = rgba[3];
  // 全透明像素的颜色通道无意义，只比较 alpha。
  for (var i = 4; i + 3 < rgba.length; i += 4) {
    if ((rgba[i + 3] - a).abs() > _channelTolerance) return false;
    if (a == 0 && rgba[i + 3] == 0) continue;
    if ((rgba[i] - r).abs() > _channelTolerance ||
        (rgba[i + 1] - g).abs() > _channelTolerance ||
        (rgba[i + 2] - b).abs() > _channelTolerance) {
      return false;
    }
  }
  return true;
}

/// 包在 flutter_map 内置缓存外的守卫，见库说明。非高德 URL 原样透传。
class AmapTileCacheGuard implements MapCachingProvider {
  AmapTileCacheGuard({
    this.inner,
    this.isBlank = isBlankTile,
    this.maxFreshAge = amapMaxFreshAge,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.timestamp;

  /// 为 null 时用 flutter_map 的内置缓存单例（Web 上内置缓存不可用，自动跳过）。
  final MapCachingProvider? inner;
  final BlankTileDetector isBlank;
  final Duration maxFreshAge;
  final DateTime Function() _now;

  MapCachingProvider get _cache =>
      inner ?? BuiltInMapCachingProvider.getOrCreateInstance();

  @override
  bool get isSupported => _cache.isSupported;

  @override
  Future<CachedMapTile?> getTile(String url) async {
    final tile = await _cache.getTile(url);
    if (tile == null || !_isAmap(url)) return tile;
    // 旧版本已缓存的空白瓦片：当作未命中，让 flutter_map 重新请求并覆盖。
    if (await isBlank(tile.bytes)) return null;
    return tile;
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    if (!_isAmap(url)) {
      return _cache.putTile(url: url, metadata: metadata, bytes: bytes);
    }
    // bytes 为 null 是 304 重新验证，只更新元数据；内容在写入时已检查过。
    if (bytes != null && await isBlank(bytes)) return;
    final latest = _now().add(maxFreshAge);
    return _cache.putTile(
      url: url,
      metadata: metadata.staleAt.isAfter(latest)
          ? CachedMapTileMetadata(
              staleAt: latest,
              lastModified: metadata.lastModified,
              etag: metadata.etag,
            )
          : metadata,
      bytes: bytes,
    );
  }

  static bool _isAmap(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && isAmapTileUrl(uri);
  }
}

/// 高德图层共用的守卫实例（内部按需取内置缓存单例）。
final amapTileCacheGuard = AmapTileCacheGuard();
