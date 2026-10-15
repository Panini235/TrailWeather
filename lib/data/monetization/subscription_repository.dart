import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/settings_repository.dart';
import 'subscription_models.dart';

class SubscriptionNotifier extends Notifier<UserSubscription> {
  static const _prefKey = 'trailweather_user_subscription_v1';

  late final SharedPreferences _prefs;

  @override
  UserSubscription build() {
    _prefs = ref.watch(prefsProvider);
    final raw = _prefs.getString(_prefKey);
    if (raw == null || raw.isEmpty) {
      return UserSubscription.free;
    }
    // 支付未接入期间，本机遗留的 Pro 记录（旧版本“模拟开通”写入）一律无效。
    if (!Billing.available) return UserSubscription.free;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final sub = UserSubscription.fromJson(json);
      // 若过期则自动重置为 free
      if (sub.tier == SubscriptionTier.pro &&
          sub.expiresAtUtc != null &&
          sub.expiresAtUtc!.isBefore(DateTime.now().toUtc())) {
        return UserSubscription.free;
      }
      return sub;
    } catch (_) {
      return UserSubscription.free;
    }
  }

  /// 购买套餐或开始试用。
  ///
  /// 支付未接入时抛 [StateError]：绝不在没有真实支付/验单的情况下授予 Pro。
  Future<void> purchase(SubscriptionPlan plan) async {
    if (!Billing.available) {
      throw StateError(Billing.unavailableNotice);
    }
    final now = DateTime.now().toUtc();
    final UserSubscription newSub = switch (plan) {
      SubscriptionPlan.yearly => UserSubscription(
        tier: SubscriptionTier.pro,
        plan: plan,
        // 年费：7 天试用 + 365 天
        expiresAtUtc: now.add(const Duration(days: 372)),
        isTrial: true,
      ),
      SubscriptionPlan.monthly => UserSubscription(
        tier: SubscriptionTier.pro,
        plan: plan,
        expiresAtUtc: now.add(const Duration(days: 30)),
        isTrial: false,
      ),
      SubscriptionPlan.lifetime => UserSubscription(
        tier: SubscriptionTier.pro,
        plan: plan,
        expiresAtUtc: null, // 终身有效
        isTrial: false,
      ),
    };

    state = newSub;
    await _prefs.setString(_prefKey, jsonEncode(newSub.toJson()));
  }

  /// 恢复购买。需向商店查询订单；支付未接入时没有可恢复的订单。
  Future<bool> restorePurchases() async {
    if (!Billing.available) return false;
    final raw = _prefs.getString(_prefKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final sub = UserSubscription.fromJson(json);
        if (sub.isPro) {
          state = sub;
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// 重置为免费版（供测试和演示使用）
  Future<void> resetToFree() async {
    state = UserSubscription.free;
    await _prefs.remove(_prefKey);
  }
}

final subscriptionProvider =
    NotifierProvider<SubscriptionNotifier, UserSubscription>(
      SubscriptionNotifier.new,
    );
