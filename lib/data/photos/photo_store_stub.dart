import 'dart:typed_data';

import 'photo_store.dart';

PhotoStore createPlatformPhotoStore() => const _UnsupportedPhotoStore();

/// Web：浏览器存储容量小且易被清除，暂不保存图片（如实提示，不假装已保存）。
class _UnsupportedPhotoStore implements PhotoStore {
  const _UnsupportedPhotoStore();

  @override
  bool get supported => false;

  @override
  Future<String> save(String id, Uint8List bytes, String extension) =>
      throw UnsupportedError('当前平台不支持保存图片');

  @override
  Future<Uint8List?> load(String key) async => null;

  @override
  Future<void> delete(String key) async {}
}
