import 'dart:typed_data';

import 'photo_store_stub.dart'
    if (dart.library.io) 'photo_store_io.dart'
    as impl;

/// 节点图片的本地存储边界。图片只保存在本机，不上传。
abstract interface class PhotoStore {
  /// 当前平台是否支持保存图片（Web 端暂不支持）。
  bool get supported;

  /// 保存图片字节，返回存储键（之后用于读取与删除）。
  Future<String> save(String id, Uint8List bytes, String extension);

  Future<Uint8List?> load(String key);

  Future<void> delete(String key);
}

PhotoStore createPhotoStore() => impl.createPlatformPhotoStore();

/// 内存实现：测试用。
class MemoryPhotoStore implements PhotoStore {
  final Map<String, Uint8List> files = {};

  @override
  bool get supported => true;

  @override
  Future<String> save(String id, Uint8List bytes, String extension) async {
    final key = '$id.$extension';
    files[key] = bytes;
    return key;
  }

  @override
  Future<Uint8List?> load(String key) async => files[key];

  @override
  Future<void> delete(String key) async => files.remove(key);
}
