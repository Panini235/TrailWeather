import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings/settings_repository.dart';
import '../../data/weather/meteoblue_provider.dart';
import '../../data/weather/meteoblue_settings.dart';
import '../widgets/common.dart';
import '../strings.dart';

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
          .showSnackBar(const SnackBar(content: Text(S.saved)));
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
                  child: Text(S.meteoblueTitle, style: TextStyle(fontSize: 14)),
                ),
                ConfiguredStatus(configured: mb.configured),
              ],
            ),
            const SizedBox(height: 4),
            const HelpText(S.meteoblueHelp),
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
              S.meteoblueUsage(
                mb.networkCalls,
                (used / 10000).toStringAsFixed(1),
              ),
              style: const TextStyle(fontSize: 11),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: _save,
                child: const Text(S.save, style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
