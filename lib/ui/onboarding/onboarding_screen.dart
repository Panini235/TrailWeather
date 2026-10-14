import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/settings/settings_repository.dart';

/// 新用户引导流（Onboarding），符合海明Dev付费转化规范：
/// 痛点问诊 → 价值唤醒与对比 → 核心功能演示 → 权益与试用选择。
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;
  String _selectedScene = 'long'; // long: 重装长线, day: 单日登山, camp: 露营越野

  void _finishOnboarding({bool openPaywall = false}) {
    ref.read(settingsProvider.notifier).completeOnboarding();
    if (openPaywall) {
      unawaited(context.push('/paywall'));
    } else {
      context.go('/');
    }
  }

  void _nextPage() {
    if (_currentPage < 3) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => _finishOnboarding(),
            child: const Text('跳过'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                children: [
                  _buildSceneQuestionPage(),
                  _buildValueAwakeningPage(),
                  _buildFeatureShowcasePage(),
                  _buildOfferPage(),
                ],
              ),
            ),

            // 底部指示器与操作栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 圆点指示器
                  Row(
                    children: List.generate(
                      4,
                      (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == i ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? primary
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),

                  // 下一步按钮
                  FilledButton(
                    onPressed: _nextPage,
                    child: Text(_currentPage == 3 ? '开始探索' : '下一步'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Page 0: 痛点问诊
  Widget _buildSceneQuestionPage() {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '定制你的专属气象哨兵',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '你最常在什么场景下徒步？',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '山地气象瞬息万变，我们将根据你的偏好推荐最关键的沿途风险指标。',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
          ),
          const SizedBox(height: 24),
          _buildSceneOption(
            key: 'long',
            icon: '🏔️',
            title: '高海拔多日重装徒步',
            subtitle: '如雨崩、TMB、乌孙、冈仁波齐等，强风寒与失温风险极高',
          ),
          const SizedBox(height: 12),
          _buildSceneOption(
            key: 'day',
            icon: '🌲',
            title: '单日郊野登山与周末爬山',
            subtitle: '如北京香山、杭州九溪、深圳梧桐山，需准确降雨窗口与能见度',
          ),
          const SizedBox(height: 12),
          _buildSceneOption(
            key: 'camp',
            icon: '⛺️',
            title: '山地露营与越野自驾',
            subtitle: '夜间降温幅度、山谷阵风、雷暴窗口与离线离网预警',
          ),
        ],
      ),
    );
  }

  Widget _buildSceneOption({
    required String key,
    required String icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedScene == key;
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _selectedScene = key),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? primary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: primary, size: 20),
          ],
        ),
      ),
    );
  }

  /// Page 1: 价值唤醒（普通天气 vs 沿途微气候）
  Widget _buildValueAwakeningPage() {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '为什么普通天气预报在山里不准？',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '普通天气只取山脚城市基站。海拔每上升 1000m，气温下降 6.5℃，山脊阵风常超山谷数倍！',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
          ),
          const SizedBox(height: 24),
          // 对比卡片
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: const Row(
              children: [
                Text('📱', style: TextStyle(fontSize: 28)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '普通手机天气：26℃ 晴朗微风',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '仅代表山脚城市基站，无法预警山顶骤降的冰雹与失温',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: primary.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Text('🏔️', style: TextStyle(fontSize: 28)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TrailWeather 空间微气候推演',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '沿轨迹 24 个节点垂直修正，垭口 3℃ 阵风 9 级 ⚡️ 触发失温哨兵',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Page 2: 核心功能赋能（全球神线、手绘、导入）
  Widget _buildFeatureShowcasePage() {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '全能户外路线与气象工坊',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '无论世界顶级神线还是周末自制路线，全部一触即达。',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
          ),
          const SizedBox(height: 24),
          _buildFeatureBullet(
            icon: '🌍',
            title: '徒步星球 · 44+ 条全球顶级经典神线',
            desc: '环勃朗峰 TMB、冈仁波齐、EBC、虎跳峡，随时查看未来 7 天微气候窗口。',
          ),
          const SizedBox(height: 16),
          _buildFeatureBullet(
            icon: '✏️',
            title: 'Trail Studio · 线路手绘规划工坊',
            desc: '在底图上打点画线、标记营地水源、推演耗时，一键导出 GPX/KML 至奥维或手表。',
          ),
          const SizedBox(height: 16),
          _buildFeatureBullet(
            icon: '📂',
            title: '商业级导入 · 支持奥维/两步路/KMZ/GPX',
            desc: '突破大小与点数限制，自适应智能抽稀，保护极值海拔，绝不崩溃。',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBullet({
    required String icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                desc,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Page 3: 权益与试用选择
  Widget _buildOfferPage() {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Icon(Icons.workspace_premium, color: Colors.amber, size: 48),
          ),
          const SizedBox(height: 8),
          Text(
            '开启 TrailWeather Pro 7天免费试用',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '尊享高程垂直微气候修正、突发失温哨兵、无网离线包与等高线地形图',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primary.withValues(alpha: 0.3)),
            ),
            child: const Column(
              children: [
                Text(
                  '年度会员 · ¥98/年（折合 ¥8.1/月）',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  '今日开启享受 7 天免费试用，试用期内随时可免费取消',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ),
          ),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => _finishOnboarding(openPaywall: true),
            child: const Text(
              '查看 Pro 方案并开始 7 天试用',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => _finishOnboarding(openPaywall: false),
            child: const Text('先免费体验，稍后再说'),
          ),
        ],
      ),
    );
  }
}
