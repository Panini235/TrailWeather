import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_links.dart';
import '../../data/app_providers.dart';
import '../../data/settings/settings_repository.dart';
import '../strings.dart';

/// 反馈用诊断信息：只含构建、平台与偏好开关，不含位置、线路或 Key。
String feedbackDiagnostics(
  AppSettings settings, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) {
  final os = isWeb ? 'Web' : (platform ?? defaultTargetPlatform).name;
  String onOff(bool v) => v ? '开' : '关';
  return [
    '${S.appTitle} 测试版',
    '版本：$kAppVersion',
    '下载：$kDownloadUrl',
    '平台：$os',
    '天气来源：${settings.enabledProviderIds.join(', ')}',
    '底图：${settings.baseLayerId}',
    '低耗电：${onOff(settings.lowPower)}',
    '海拔订正：${onOff(settings.elevationLapseRateCorrection)}',
    '和风天气 Key：${settings.qweatherConfigured ? '已配置' : '未配置'}',
  ].join('\n');
}

Future<void> showFeedbackSheet(BuildContext context, WidgetRef ref) {
  final diagnostics = feedbackDiagnostics(ref.read(settingsProvider));
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final messenger = ScaffoldMessenger.of(context);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(S.feedbackTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                S.feedbackIntro,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    diagnostics,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: diagnostics));
                  messenger.showSnackBar(
                    const SnackBar(content: Text(S.feedbackCopied)),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text(S.feedbackCopy),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final url = '$kFeedbackUrl/new';
                  final ok = await ref
                      .read(externalUrlLauncherProvider)
                      .open(Uri.parse(url))
                      .catchError((_) => false);
                  if (ok) return;
                  await Clipboard.setData(ClipboardData(text: url));
                  messenger.showSnackBar(
                    const SnackBar(content: Text(S.feedbackOpenFailed)),
                  );
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text(S.feedbackOpenIssues),
              ),
              const SizedBox(height: 8),
              Text(
                S.feedbackIssuesNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
