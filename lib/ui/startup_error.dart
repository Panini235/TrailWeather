import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_links.dart';
import 'strings.dart';

/// 启动初始化失败时的兜底页面：如实说明并给出反馈途径，不停在启动画面。
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  String get _diagnostics => S.startupDiagnostics(kAppVersion, '$error');

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Builder(
      builder: (context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(
                S.startupFailedTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(S.startupFailedBody),
              const SizedBox(height: 16),
              SelectableText(
                _diagnostics,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text(S.startupCopyDiagnostics),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _diagnostics));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text(S.startupCopied)),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              const SelectableText(kFeedbackUrl),
            ],
          ),
        ),
      ),
    ),
  );
}
