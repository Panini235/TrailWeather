import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 缓存命名空间：至少区分线路 / 地图 / 天气 / 用户数据。
class CacheNs {
  static const routes = 'routes';
  static const map = 'map';
  static const weather = 'weather';
  static const user = 'user';

  static const all = [routes, map, weather, user];
}

class CachedRead {
  final String payload;
  final DateTime storedAtUtc;
  final DateTime expiresAtUtc;

  CachedRead({
    required this.payload,
    required this.storedAtUtc,
    required this.expiresAtUtc,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAtUtc);
  bool get isStale => isExpired; // 过期但在容忍窗口内读取时由调用方标记
}

/// 基于 shared_preferences 的三端持久缓存。
/// - 每条目带 storedAt/expiresAt/lastAccess；
/// - LRU 淘汰，每命名空间有条目上限；
/// - 支持 stale-while-revalidate：read() 允许读取已过期条目，
///   由调用方负责标记“旧数据”并触发后台刷新。
class CacheStore {
  CacheStore(this._prefs, {this.maxEntriesPerNamespace = 200});

  final SharedPreferences _prefs;
  final int maxEntriesPerNamespace;

  static String _key(String ns, String key) => 'cache.$ns.$key';

  Future<CachedRead?> read(String ns, String key, {bool touch = true}) async {
    final raw = _prefs.getString(_key(ns, key));
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final entry = _Entry.fromJson(map);
      if (touch) {
        entry.lastAccessMs = DateTime.now().toUtc().millisecondsSinceEpoch;
        await _prefs.setString(_key(ns, key), jsonEncode(entry.toJson()));
      }
      return CachedRead(
        payload: entry.payload,
        storedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          entry.storedAtMs,
          isUtc: true,
        ),
        expiresAtUtc: DateTime.fromMillisecondsSinceEpoch(
          entry.expiresAtMs,
          isUtc: true,
        ),
      );
    } catch (_) {
      await _prefs.remove(_key(ns, key));
      return null;
    }
  }

  Future<void> write(
    String ns,
    String key,
    String payload,
    Duration ttl,
  ) async {
    final now = DateTime.now().toUtc();
    final entry = _Entry(
      payload: payload,
      storedAtMs: now.millisecondsSinceEpoch,
      expiresAtMs: now.add(ttl).millisecondsSinceEpoch,
      lastAccessMs: now.millisecondsSinceEpoch,
    );
    await _prefs.setString(_key(ns, key), jsonEncode(entry.toJson()));
    unawaited(_evictIfNeeded(ns));
  }

  Future<void> remove(String ns, String key) async {
    await _prefs.remove(_key(ns, key));
  }

  Future<void> clearNamespace(String ns) async {
    final prefix = 'cache.$ns.';
    final keys = _prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      await _prefs.remove(k);
    }
  }

  Future<void> clearAll() async {
    for (final ns in CacheNs.all) {
      await clearNamespace(ns);
    }
  }

  Future<int> entryCount(String ns) async {
    final prefix = 'cache.$ns.';
    return _prefs.getKeys().where((k) => k.startsWith(prefix)).length;
  }

  /// 粗略字节数（UTF-16 近似），用于设置页展示缓存占用。
  int approxSizeBytes(String ns) {
    final prefix = 'cache.$ns.';
    var total = 0;
    for (final k in _prefs.getKeys()) {
      if (k.startsWith(prefix)) {
        final v = _prefs.getString(k);
        if (v != null) total += v.length * 2;
      }
    }
    return total;
  }

  Future<void> _evictIfNeeded(String ns) async {
    final prefix = 'cache.$ns.';
    final keys = _prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    if (keys.length <= maxEntriesPerNamespace) return;
    final entries = <_Entry, String>{};
    for (final k in keys) {
      final raw = _prefs.getString(k);
      if (raw == null) continue;
      try {
        entries[_Entry.fromJson(jsonDecode(raw) as Map<String, dynamic>)] = k;
      } catch (_) {
        await _prefs.remove(k);
      }
    }
    final sorted = entries.keys.toList()
      ..sort((a, b) => a.lastAccessMs.compareTo(b.lastAccessMs));
    final toRemove = sorted.take(sorted.length - maxEntriesPerNamespace);
    for (final e in toRemove) {
      await _prefs.remove(entries[e]!);
    }
  }
}

class _Entry {
  _Entry({
    required this.payload,
    required this.storedAtMs,
    required this.expiresAtMs,
    required this.lastAccessMs,
  });

  final String payload;
  final int storedAtMs;
  final int expiresAtMs;
  int lastAccessMs;

  Map<String, dynamic> toJson() => {
    'p': payload,
    's': storedAtMs,
    'e': expiresAtMs,
    'l': lastAccessMs,
  };

  factory _Entry.fromJson(Map<String, dynamic> map) => _Entry(
    payload: map['p'] as String,
    storedAtMs: map['s'] as int,
    expiresAtMs: map['e'] as int,
    lastAccessMs: map['l'] as int,
  );
}
