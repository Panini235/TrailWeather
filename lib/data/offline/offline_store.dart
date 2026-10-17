import 'package:shared_preferences/shared_preferences.dart';

import 'offline_store_prefs.dart'
    if (dart.library.io) 'offline_store_io.dart'
    as platform;

/// 独立持久存储，普通天气 LRU / 清缓存不持有这些键或文件。
abstract interface class OfflineTripStore {
  Future<List<String>> ids();
  Future<String?> read(String id);

  /// 成功前须核对写入内容；失败不得替换原有包。
  Future<void> write(String id, String value);
  Future<void> delete(String id);
}

OfflineTripStore createOfflineTripStore(SharedPreferences prefs) =>
    platform.createPlatformOfflineTripStore(prefs);

const maxOfflinePackBytes = 64 * 1024 * 1024;
