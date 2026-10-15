import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings/settings_repository.dart';
import '../../data/weather/meteoblue_provider.dart';
import '../../data/weather/meteoblue_settings.dart';

/// meteoblue 密钥配置（仅存本机，不上传）与本机调用计数。
class MeteoblueCredentialsCard extends ConsumerStatefulWidget {
  const MeteoblueCredentialsCard({super.key});

  @override
  ConsumerState<MeteoblueCredentialsCard> createState() =>
      _MeteoblueCredentialsCardState();
}

class _MeteoblueCredentialsCardState
    extends ConsumerState<MeteoblueCredentialsCard> {
  late final TextEditingController _key = TextEditingController(
    text: ref.read(meteoblueSettingsProvider).apiKey,
  );

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(meteoblueSettingsProvider.notifier).setApiKey(_key.text);
    // 填了 key 就启用该来源（它是按需来源，不会自动消耗额度）。
    final settings = ref.read(settingsProvider);
    const id = MeteoblueProvider.providerIdValue;
    if (_key.text.trim().isNotEmpty &&
        !settings.enabledProviderIds.contains(id)) {
      await ref.read(settingsProvider.notifier).toggleProvider(id);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存（仅本机）')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mb = ref.watch(meteoblueSettingsProvider);
    final used = mb.networkCalls * MeteoblueProvider.creditsPerCall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.vpn_key_outlined, size: 16),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'meteoblue（逐点海拔，按次计费）',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                if (mb.configured)
                  const Icon(Icons.check_circle, size: 16, color: Colors.green)
                else
                  const Text(
                    '未配置',
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '在 meteoblue 账户的 Weather API 页面获取 key。每次查询约 8000 credits'
              '（免费版 1 年 1000 万 ≈ 1,250 次），所以只在节点详情“多来源对比”或地图选点里'
              '点“查询此点”时才请求，按节点海拔计算；3 小时内重复查询同一点使用缓存。'
              '密钥仅保存在本机。',
              style: TextStyle(fontSize: 11, height: 1.5, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _key,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API key',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '本机已发起 ${mb.networkCalls} 次请求（约 ${(used / 10000).toStringAsFixed(1)} 万 credits）；'
              '剩余额度以 meteoblue 后台为准。',
              style: const TextStyle(fontSize: 11),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: _save,
                child: const Text('保存', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
