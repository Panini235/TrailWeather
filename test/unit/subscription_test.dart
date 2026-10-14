import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/monetization/subscription_models.dart';
import 'package:trailweather/data/monetization/subscription_repository.dart';
import 'package:trailweather/data/settings/settings_repository.dart';

void main() {
  group('Subscription & Monetization', () {
    test('初始未付费用户为免费版（isPro 为 false）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs)],
      );

      final sub = container.read(subscriptionProvider);
      expect(sub.tier, SubscriptionTier.free);
      expect(sub.isPro, isFalse);
    });

    test('订阅年度会员赠送 7 天免费试用且进入 Pro 状态', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs)],
      );

      final notifier = container.read(subscriptionProvider.notifier);
      await notifier.purchase(SubscriptionPlan.yearly);

      final sub = container.read(subscriptionProvider);
      expect(sub.tier, SubscriptionTier.pro);
      expect(sub.plan, SubscriptionPlan.yearly);
      expect(sub.isTrial, isTrue);
      expect(sub.isPro, isTrue);
      expect(sub.expiresAtUtc, isNotNull);
      expect(
        sub.expiresAtUtc!.isAfter(
          DateTime.now().toUtc().add(const Duration(days: 360)),
        ),
        isTrue,
      );
    });

    test('终身买断一次性激活永久会员（expiresAtUtc 为 null）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs)],
      );

      final notifier = container.read(subscriptionProvider.notifier);
      await notifier.purchase(SubscriptionPlan.lifetime);

      final sub = container.read(subscriptionProvider);
      expect(sub.tier, SubscriptionTier.pro);
      expect(sub.plan, SubscriptionPlan.lifetime);
      expect(sub.expiresAtUtc, isNull);
      expect(sub.isPro, isTrue);
    });

    test('恢复购买能正确还原已保存的 Pro 订阅', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container1 = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs)],
      );
      await container1
          .read(subscriptionProvider.notifier)
          .purchase(SubscriptionPlan.monthly);

      // 新的容器模拟应用重启
      final container2 = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs)],
      );
      final restored = await container2
          .read(subscriptionProvider.notifier)
          .restorePurchases();
      expect(restored, isTrue);
      expect(container2.read(subscriptionProvider).isPro, isTrue);
    });
  });
}
