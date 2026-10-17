import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/settings/settings_repository.dart';
import '../strings.dart';

/// 首次使用先进入真实线路体验；商业化暂缓期间不展示套餐或购买引导。
///
/// 隐私说明需用户主动勾选同意（不默认勾选）才能继续；未同意前不能返回关闭本页。
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _finishing = false;
  late bool _agreed = ref.read(settingsProvider).privacyAccepted;

  Future<void> _finish({bool importRoute = false}) async {
    if (_finishing) return;
    if (!_agreed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(S.privacyRequired)));
      return;
    }
    setState(() => _finishing = true);
    final settings = ref.read(settingsProvider.notifier);
    await settings.acceptPrivacy();
    await settings.completeOnboarding();
    if (!mounted) return;
    final router = GoRouter.of(context);
    router.go('/');
    if (importRoute) unawaited(router.push('/import'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope(
      canPop: ref.watch(settingsProvider).privacyAccepted,
      child: Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/branding/app-icon.png',
                      width: 64,
                      height: 64,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(S.appTitle, style: theme.textTheme.headlineSmall),
                ],
              ),
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(
                  '出发前，看懂沿途天气',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '导入一条徒步线路，按出发时间查看沿途预报。\n不需要注册账号，也可以先从示例线路开始。',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              const _GuideStep(
                icon: Icons.file_upload_outlined,
                title: '带上你的线路',
                description: '支持 GPX、KML、KMZ 和 GeoJSON，也可以在地图上手绘。',
              ),
              const _GuideStep(
                icon: Icons.schedule_outlined,
                title: '选择出发时间',
                description: '查看同一时刻的天气，或结合配速估算沿途到达时间。',
              ),
              const _GuideStep(
                icon: Icons.cloud_outlined,
                title: '核对来源与更新时间',
                description: '预报不是实测；缺失数据和超出预报范围的时段会明确说明。',
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    '出发前可在线下载线路与预报，再从首页打开离线行程包。离线底图尚未提供，请另备地图。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                S.privacySummary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              CheckboxListTile(
                value: _agreed,
                onChanged: _finishing
                    ? null
                    : (v) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        setState(() => _agreed = v ?? false);
                      },
                title: const Text(S.privacyAgree),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => context.push('/privacy'),
                  child: const Text(S.privacyRead),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _finishing ? null : () => _finish(importRoute: true),
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('导入我的线路'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _finishing ? null : _finish,
                child: const Text('先看示例线路'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
