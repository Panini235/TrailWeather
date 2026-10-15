import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_repository.dart';

/// meteoblue 密钥与本机调用计数（仅本机保存，不上传）。
///
/// 单独存储而不并入 AppSettings：额度计数会频繁变化，不应触发天气来源重建。
class MeteoblueSettings {
  const MeteoblueSettings({this.apiKey = '', this.networkCalls = 0});

  final String apiKey;

  /// 本机发起的真实请求次数（缓存命中不计）。剩余额度以 meteoblue 后台为准。
  final int networkCalls;

  bool get configured => apiKey.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {'key': apiKey, 'calls': networkCalls};

  static MeteoblueSettings fromJson(Map<String, dynamic> m) =>
      MeteoblueSettings(
        apiKey: m['key'] as String? ?? '',
        networkCalls: (m['calls'] as num?)?.toInt() ?? 0,
      );
}

class MeteoblueSettingsNotifier extends Notifier<MeteoblueSettings> {
  static const _key = 'meteoblue.v1';

  @override
  MeteoblueSettings build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return const MeteoblueSettings();
    try {
      return MeteoblueSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const MeteoblueSettings();
    }
  }

  Future<void> _save(MeteoblueSettings s) async {
    state = s;
    await ref.read(prefsProvider).setString(_key, jsonEncode(s.toJson()));
  }

  Future<void> setApiKey(String key) => _save(
    MeteoblueSettings(apiKey: key.trim(), networkCalls: state.networkCalls),
  );

  Future<void> recordCall() => _save(
    MeteoblueSettings(
      apiKey: state.apiKey,
      networkCalls: state.networkCalls + 1,
    ),
  );
}

final meteoblueSettingsProvider =
    NotifierProvider<MeteoblueSettingsNotifier, MeteoblueSettings>(
      MeteoblueSettingsNotifier.new,
    );
