/// 支付通道状态。
///
/// 未接入应用商店内购（Google Play Billing / App Store IAP）与服务端验单前，
/// 不得在本地直接授予 Pro：否则任何人点击即可免费获得“终身会员”。
/// 接入支付属于需用户授权的事项（见 agent/blockers.md）。
class Billing {
  static const available = false;
  static const unavailableNotice = '支付尚未接入：当前为方案预览，暂不可购买或试用，不会产生任何扣费。';
}

/// 会员等级。
enum SubscriptionTier {
  /// 免费版：基础城市天气、示例路线、基础手绘与导入
  free,

  /// 专业版 (TrailWeather Pro)：
  /// 1. 沿途微气候垂直气温递减修正引擎（-0.65°C/100m）
  /// 2. 突发失温指数、强阵风、雷暴风险智能哨兵
  /// 3. 无网离线气象与离网轨迹包极速缓存
  /// 4. 户外等高线专业地形图层
  /// 5. 全球 44+ 经典神线无限制推演与手绘无限导出
  pro,
}

/// 订阅套餐计划。
enum SubscriptionPlan {
  /// 月度计划：适合单次长线突击
  monthly,

  /// 年度计划：适合四季常态徒步与领队（主推 ★★★★★，赠 7 天免费试用）
  yearly,

  /// 终身买断：一次付费，终身使用（核心离线算法为主，成本可控）
  lifetime,
}

/// 套餐详细展示信息。
class PlanProduct {
  const PlanProduct({
    required this.plan,
    required this.name,
    required this.priceDesc,
    required this.rawPrice,
    required this.currency,
    required this.billingPeriodDesc,
    required this.tag,
    this.originalPriceDesc,
    this.trialDays = 0,
    this.isFeatured = false,
  });

  final SubscriptionPlan plan;
  final String name;
  final String priceDesc;
  final double rawPrice;
  final String currency;
  final String billingPeriodDesc;
  final String tag;
  final String? originalPriceDesc;
  final int trialDays;
  final bool isFeatured;

  static const List<PlanProduct> all = [
    PlanProduct(
      plan: SubscriptionPlan.yearly,
      name: '年度会员',
      priceDesc: '¥98',
      rawPrice: 98.0,
      currency: 'CNY',
      billingPeriodDesc: '每年自动续订，折合 ¥8.1/月',
      trialDays: 7,
      isFeatured: true,
      tag: '推荐',
    ),
    PlanProduct(
      plan: SubscriptionPlan.monthly,
      name: '月度会员',
      priceDesc: '¥18',
      rawPrice: 18.0,
      currency: 'CNY',
      billingPeriodDesc: '按月自动续订，适合假期出行',
      tag: '按月',
    ),
    PlanProduct(
      plan: SubscriptionPlan.lifetime,
      name: '终身买断',
      priceDesc: '¥198',
      rawPrice: 198.0,
      currency: 'CNY',
      billingPeriodDesc: '一次付费，终身尊享全部专业功能',
      tag: '买断',
    ),
  ];
}

/// 商业化权益项。
class EntitlementItem {
  const EntitlementItem({
    required this.title,
    required this.description,
    required this.freeIncluded,
    required this.proIncluded,
    required this.icon,
    this.available = true,
  });

  final String title;
  final String description;
  final bool freeIncluded;
  final bool proIncluded;
  final String icon;

  /// 功能是否已实现上线。未实现的必须标“开发中”，不得宣称已启用。
  final bool available;

  static const List<EntitlementItem> list = [
    EntitlementItem(
      title: '高程微气候垂直修正',
      description: '动态计算海拔高度差（-0.65℃/100m），精准推演山脊垭口真实体感与冰点',
      freeIncluded: false,
      proIncluded: true,
      icon: '🏔️',
      available: false,
    ),
    EntitlementItem(
      title: '高山失温与极端天气哨兵',
      description: '风寒效应指数、雷暴突发窗口、强阵风安全阈值实时告警与撤退建议',
      freeIncluded: false,
      proIncluded: true,
      icon: '⚡️',
      available: false,
    ),
    EntitlementItem(
      title: '离网气象与离线轨迹包',
      description: '深入无信号无人区前一键缓存沿途 7 天气象预测与高精度路线，离网即查',
      freeIncluded: false,
      proIncluded: true,
      icon: '🛰️',
      available: false,
    ),
    EntitlementItem(
      title: '等高线地形与户外专题底图',
      description: '加载高分辨率等高线与山地阴影，行前直观判断山势起伏与山脊走向',
      freeIncluded: false,
      proIncluded: true,
      icon: '🗺️',
      available: false,
    ),
    EntitlementItem(
      title: '手绘规划工坊与双向互通',
      description: '支持打点画线、航点标注、预计耗时推演与标准 GPX/KML 导出到奥维/两步路',
      freeIncluded: true,
      proIncluded: true,
      icon: '✏️',
    ),
    EntitlementItem(
      title: '全球经典徒步路线库',
      description: '畅享 TMB、冈仁波齐、EBC 等 44+ 条全球神线气象窗口推演',
      freeIncluded: true,
      proIncluded: true,
      icon: '🌍',
    ),
  ];
}

/// 用户当前的会员订阅状态。
class UserSubscription {
  const UserSubscription({
    required this.tier,
    this.plan,
    this.expiresAtUtc,
    this.isTrial = false,
  });

  final SubscriptionTier tier;
  final SubscriptionPlan? plan;
  final DateTime? expiresAtUtc;
  final bool isTrial;

  bool get isPro =>
      tier == SubscriptionTier.pro &&
      (expiresAtUtc == null || expiresAtUtc!.isAfter(DateTime.now().toUtc()));

  Map<String, dynamic> toJson() => {
    'tier': tier.name,
    'plan': plan?.name,
    'expiresAtUtc': expiresAtUtc?.toIso8601String(),
    'isTrial': isTrial,
  };

  static UserSubscription fromJson(Map<String, dynamic> json) =>
      UserSubscription(
        tier: SubscriptionTier.values.byName(json['tier'] as String? ?? 'free'),
        plan: json['plan'] != null
            ? SubscriptionPlan.values.byName(json['plan'] as String)
            : null,
        expiresAtUtc: json['expiresAtUtc'] != null
            ? DateTime.parse(json['expiresAtUtc'] as String)
            : null,
        isTrial: json['isTrial'] as bool? ?? false,
      );

  static const free = UserSubscription(tier: SubscriptionTier.free);
}
