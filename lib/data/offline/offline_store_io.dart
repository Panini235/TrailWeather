import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_store.dart';
import 'offline_trip.dart';

OfflineTripStore createPlatformOfflineTripStore(SharedPreferences prefs) =>
    FileOfflineTripStore();

/// App 文档目录，临时文件落盘并逐字核对后才原子替换；不另设易失的索引。
class FileOfflineTripStore implements OfflineTripStore {
  FileOfflineTripStore({this.directory});
  Directory? directory;
  int _serial = 0;

  Future<Directory> _root() async {
    final dir = directory ??= Directory(
      '${(await getApplicationDocumentsDirectory()).path}/offline_trips_v1',
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file(String id) async {
    validateOfflineId(id);
    return File('${(await _root()).path}/$id.json');
  }

  @override
  Future<List<String>> ids() async => [
    await for (final entry in (await _root()).list())
      if (entry is File && entry.path.endsWith('.json'))
        entry.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), ''),
  ];

  @override
  Future<String?> read(String id) async {
    final file = await _file(id);
    if (!await file.exists()) return null;
    if (await file.length() > maxOfflinePackBytes) {
      throw const FormatException('离线包过大，无法读取');
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String id, String value) async {
    final bytes = utf8.encode(value);
    if (bytes.length > maxOfflinePackBytes) {
      throw const FormatException('离线包超过存储上限');
    }
    final target = await _file(id);
    final temp = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.${_serial++}.tmp',
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      if (await temp.readAsString() != value) {
        throw const FormatException('离线包写入校验失败');
      }
      // iOS/Android 同一文件系统 rename 的替换是原子的；中断时旧包仍完整。
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  @override
  Future<void> delete(String id) async {
    final file = await _file(id);
    if (await file.exists()) await file.delete();
  }
}
