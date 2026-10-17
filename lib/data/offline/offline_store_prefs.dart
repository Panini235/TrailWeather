import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'offline_store.dart';
import 'offline_trip.dart';

OfflineTripStore createPlatformOfflineTripStore(SharedPreferences prefs) =>
    PreferencesOfflineTripStore(prefs);

/// Web 工程验证用；浏览器配额/清除站点数据可能导致失败或丢失，界面明确提示。
class PreferencesOfflineTripStore implements OfflineTripStore {
  PreferencesOfflineTripStore(this.prefs);
  final SharedPreferences prefs;
  static const prefix = 'offline.trips.v1.';

  String _key(String id) {
    validateOfflineId(id);
    return '$prefix$id';
  }

  @override
  Future<List<String>> ids() async => prefs
      .getKeys()
      .where((k) => k.startsWith(prefix))
      .map((k) => k.substring(prefix.length))
      .toList();

  @override
  Future<String?> read(String id) async => prefs.getString(_key(id));

  @override
  Future<void> write(String id, String value) async {
    final key = _key(id);
    if (utf8.encode(value).length > maxOfflinePackBytes) {
      throw const FormatException('离线包超过存储上限');
    }
    try {
      if (!await prefs.setString(key, value)) {
        throw StateError('离线包保存失败，请检查剩余空间');
      }
      await prefs.reload();
      if (prefs.getString(key) != value) {
        throw StateError('离线包写入校验失败');
      }
    } catch (_) {
      // setter 会先改内存缓存；持久化失败后重载，不能把未落盘的值展示为成功。
      await prefs.reload();
      rethrow;
    }
  }

  @override
  Future<void> delete(String id) async {
    if (!await prefs.remove(_key(id))) throw StateError('离线包删除失败');
  }
}
