import 'package:flutter/material.dart';

import '../strings.dart';

/// 隐私说明全文（首启引导与设置页共用）。
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(S.privacyTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              S.privacySummary,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
            for (final (title, body) in S.privacySections) ...[
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
