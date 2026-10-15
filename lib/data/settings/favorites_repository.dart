import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../routes/route_models.dart';
import 'settings_repository.dart';

/// 收藏与用户导入的线路：本地保存（不上传任何用户数据）。
class FavoritesNotifier extends Notifier<List<HikingRoute>> {
  static const _key = 'favorites.v1';

  @override
  List<HikingRoute> build() {
    final prefs = ref.read(prefsProvider);
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list) HikingRoute.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist() async {
    final prefs = ref.read(prefsProvider);
    await prefs.setString(
      _key,
      jsonEncode([for (final r in state) r.toJson()]),
    );
  }

  bool isFavorite(String id) => state.any((r) => r.id == id);

  Future<void> add(HikingRoute route) async {
    state = [...state.where((r) => r.id != route.id), route];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((r) => r.id != id).toList();
    await _persist();
  }

  Future<void> toggle(HikingRoute route) async {
    if (isFavorite(route.id)) {
      await remove(route.id);
    } else {
      await add(route);
    }
  }

  /// 导出用户自有数据（收藏+导入线路）为 JSON 文本。
  String exportJson() =>
      const JsonEncoder.withIndent('  ')
          .convert([for (final r in state) r.toJson()]);
}

final favoritesProvider =
    NotifierProvider<FavoritesNotifier, List<HikingRoute>>(
      FavoritesNotifier.new,
    );
