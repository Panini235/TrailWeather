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

    test('支付未接入时购买抛错且不授予 Pro（不得本地白送会员）', () async {
      expect(Billing.available, isFalse);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs)],
      );
      final notifier = container.read(subscriptionProvider.notifier);
      for (final plan in SubscriptionPlan.values) {
        await expectLater(notifier.purchase(plan), throwsStateError);
      }
      expect(container.read(subscriptionProvider).isPro, isFalse);
      expect(await notifier.restorePurchases(), isFalse);
    });

    test('旧版本“模拟开通”遗留的本机 Pro 记录无效', () async {
      SharedPreferences.setMockInitialValues({
        'trailweather_user_subscription_v1': '{"tier":"pro","plan":"lifetime","expiresAtUtc":null,"isTrial":false}',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs)],
      );
      expect(container.read(subscriptionProvider).isPro, isFalse);
    });

    test('未实现的 Pro 权益必须标为不可用', () {
      final unavailable = EntitlementItem.list
          .where((e) => !e.available)
          .map((e) => e.title);
      expect(
        unavailable,
        containsAll(['高程微气候垂直修正', '高山失温与极端天气哨兵', '离网气象与离线轨迹包', '等高线地形与户外专题底图']),
      );
    });

    test('UserSubscription 序列化往返（为接入真实支付保留）', () {
      final sub = UserSubscription(
        tier: SubscriptionTier.pro,
        plan: SubscriptionPlan.yearly,
        expiresAtUtc: DateTime.utc(2027),
        isTrial: true,
      );
      final back = UserSubscription.fromJson(sub.toJson());
      expect(back.plan, SubscriptionPlan.yearly);
      expect(back.isTrial, isTrue);
      expect(back.expiresAtUtc, DateTime.utc(2027));
    });
  });
}
