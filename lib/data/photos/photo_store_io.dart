import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'photo_store.dart';

PhotoStore createPlatformPhotoStore() => _FilePhotoStore();

/// 移动端/桌面：保存在应用文档目录 route_photos/ 下（随 App 卸载删除）。
class _FilePhotoStore implements PhotoStore {
  Directory? _dir;

  Future<Directory> _root() async {
    final existing = _dir;
    if (existing != null) return existing;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/route_photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  @override
  bool get supported => true;

  /// 存储键只含文件名，避免文档目录路径变化（iOS 升级后容器路径会变）。
  @override
  Future<String> save(String id, Uint8List bytes, String extension) async {
    final name = '$id.$extension';
    await File('${(await _root()).path}/$name')
        .writeAsBytes(bytes, flush: true);
    return name;
  }

  @override
  Future<Uint8List?> load(String key) async {
    final file = File('${(await _root()).path}/$key');
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> delete(String key) async {
    final file = File('${(await _root()).path}/$key');
    if (await file.exists()) await file.delete();
  }
}
