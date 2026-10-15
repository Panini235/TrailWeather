import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/cache_store.dart';
import '../../data/app_providers.dart';
import '../../data/monetization/subscription_models.dart';
import '../../data/monetization/subscription_repository.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/weather_models.dart';
import '../strings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final providers = ref.watch(weatherProvidersProvider);
    final subscription = ref.watch(subscriptionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(S.settings)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildProBanner(context, ref, subscription),
          const SizedBox(height: 12),
          _section(context, '单位'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('英制单位', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '温度 °F、距离 mi、降水 in',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: settings.imperial,
                  onChanged: (v) =>
                      notifier.update(settings.copyWith(imperial: v)),
                ),
                ListTile(
                  dense: true,
                  title: const Text('风速单位', style: TextStyle(fontSize: 14)),
                  trailing: DropdownButton<String>(
                    value: ['km/h', 'm/s', 'mph'].contains(settings.windUnit)
                        ? settings.windUnit
                        : 'km/h',
                    items: const [
                      DropdownMenuItem(value: 'km/h', child: Text('km/h')),
                      DropdownMenuItem(value: 'm/s', child: Text('m/s')),
                      DropdownMenuItem(value: 'mph', child: Text('mph')),
                    ],
                    onChanged: (v) => notifier.update(
                      settings.copyWith(windUnit: v ?? 'km/h'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _section(context, '外观'),
          Card(
            child: ListTile(
              dense: true,
              title: const Text('主题', style: TextStyle(fontSize: 14)),
              trailing: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('系统', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('浅色', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('深色', style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (s) =>
                    notifier.update(settings.copyWith(themeMode: s.first)),
              ),
            ),
          ),
          _section(context, '地图底图'),
          Card(
            child: ListTile(
              dense: true,
              title: const Text('底图来源', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '高德（国内直连快，GCJ-02 显示坐标，业务数据仍为 WGS-84）/ OSM（海外网络）',
                style: TextStyle(fontSize: 11),
              ),
              trailing: SegmentedButton<BasemapSource>(
                segments: const [
                  ButtonSegment(
                    value: BasemapSource.amap,
                    label: Text('高德', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: BasemapSource.osm,
                    label: Text('OSM', style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {settings.basemap},
                onSelectionChanged: (sel) =>
                    notifier.update(settings.copyWith(basemap: sel.first)),
              ),
            ),
          ),
          _section(context, '数据源密钥'),
          const _QweatherCredentialsCard(),
          _section(context, '天气来源'),
          Card(
            child: Column(
              children: [
                for (final p in providers)
                  SwitchListTile(
                    dense: true,
                    title: Text(
                      p.caps.displayName,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      '${p.caps.vendor} · 覆盖 ${p.caps.coverage} · 预报 ${p.caps.forecastHorizonDays} 天 · ${p.caps.requiresApiKey ? '需密钥' : '无需密钥'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    value: settings.enabledProviderIds.contains(
                      p.caps.providerId,
                    ),
                    onChanged: (_) =>
                        notifier.toggleProvider(p.caps.providerId),
                  ),
                ListTile(
                  dense: true,
                  title: const Text(
                    '来源能力与授权对照',
                    style: TextStyle(fontSize: 13),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _showCapabilities(context, [
                    for (final p in providers) p.caps,
                  ]),
                ),
              ],
            ),
          ),
          _section(context, '低耗电'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  title: const Text('低耗电模式', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '加大采样间距与节点上限（减少请求与计算），不自动刷新。精细度会变化并在详情页可见。',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: settings.lowPower,
                  onChanged: notifier.setLowPower,
                ),
                ListTile(
                  dense: true,
                  title: Text(
                    '采样间距：${settings.samplingSpacingKm.toStringAsFixed(1)} km',
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    '线路天气节点的采样间距（工程参数，不代表天气空间分辨率）',
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: SizedBox(
                    width: 150,
                    child: Slider(
                      value: settings.samplingSpacingKm,
                      min: 1,
                      max: 3,
                      divisions: 4,
                      label:
                          '${settings.samplingSpacingKm.toStringAsFixed(1)} km',
                      onChanged: (v) => notifier.update(
                        settings.copyWith(samplingSpacingKm: v),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _section(context, '专业微气候算法 (PRO)'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  title: const Text(
                    '高程气温垂直递减修正（开发中）',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    '尚未接入天气计算：开启与否都不会修改任何温度数据。',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: false,
                  // 功能未实现前禁用，避免让人以为温度已被修正。
                  onChanged: null,
                ),
              ],
            ),
          ),
          _section(context, '新用户与引导'),
          Card(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.explore_outlined, size: 20),
                  title: const Text('重温新手引导流程', style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                    '重新探索场景偏好与微气候反差演示',
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => context.push('/onboarding'),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.workspace_premium_outlined,
                    size: 20,
                  ),
                  title: const Text(
                    '会员方案与权益对比',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    '查看月度、年度与终身买断套餐详情',
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => context.push('/paywall'),
                ),
              ],
            ),
          ),
          _section(context, '缓存与数据'),
          const _CacheCard(),
          Card(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.verified_user_outlined, size: 20),
                  title: const Text('数据授权与署名', style: TextStyle(fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _showAttribution(context),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.privacy_tip_outlined, size: 20),
                  title: const Text('隐私说明', style: TextStyle(fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _showPrivacy(context),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.file_download_outlined, size: 20),
                  title: const Text('导出我的线路数据', style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                    '收藏与导入线路导出为 JSON 文本（本地操作，不上传）',
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.copy, size: 18),
                  onTap: () async {
                    final json = ref
                        .read(favoritesProvider.notifier)
                        .exportJson();
                    await _copy(context, json);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (dCtx) => AlertDialog(
          title: const Text('导出数据（已复制到剪贴板）'),
          content: SizedBox(
            width: 420,
            child: SelectableText(text, style: const TextStyle(fontSize: 11)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text(S.close),
            ),
          ],
        ),
      );
    }
  }

  void _showCapabilities(
    BuildContext context,
    List<ProviderCapabilities> caps,
  ) {
    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('来源能力与授权对照'),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in caps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '服务商：${c.vendor}\n模型：${c.modelOrNetwork}\n覆盖：${c.coverage}\n'
                        '时效：${c.forecastHorizonDays} 天 · 间隔 ${c.intervalHours} h\n'
                        '空间分辨率：${c.spatialResolutionNote ?? '来源未提供'}\n'
                        'Web 端：${c.browserNotes}\n授权：${c.license}\n署名：${c.attribution}',
                        style: const TextStyle(fontSize: 11, height: 1.5),
                      ),
                      if (c.modelOverlapNote != null)
                        Text(
                          c.modelOverlapNote!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text(S.close),
          ),
        ],
      ),
    );
  }

  void _showAttribution(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('数据授权与署名'),
        content: const SingleChildScrollView(
          child: Text(
            '地图瓦片：默认 © 高德地图；可切换 © OpenStreetMap 贡献者。仅在线显示，不预下载。\n\n'
            '徒步线路与具名路径段（OSM）：© OpenStreetMap 贡献者，ODbL 1.0。线路几何来自 Overpass API 按视野查询；路径段不冒充完整路线，App 展示不构成对路线可通行性或许可进入的担保。\n\n'
            '天气：Open-Meteo（CC BY 4.0，非商业免费额度；模型来自 NOAA 等机构）；MET Norway Locationforecast 2.0（NLOD 2.0 / CC BY 4.0）。\n\n'
            '地点搜索：Open-Meteo Geocoding（GeoNames/知识共享数据）。\n\n'
            '内置示例线路为本项目演示数据（已标注“演示”），非实测。\n\n'
            '完整对照表与条款链接见 docs/data-sources.md。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text(S.close),
          ),
        ],
      ),
    );
  }

  void _showPrivacy(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('隐私说明'),
        content: const SingleChildScrollView(
          child: Text(
            '· 不默认上传你的轨迹、精确位置或收藏；收藏和缓存保存在本机。\n'
            '· 首页会请求一次前台定位，用于显示当前位置天气并查询当地线路；之后仅在你再次点击定位按钮时读取，不持续监听、不后台定位。\n'
            '· 定位成功、点击地图或查看线路天气时，会把对应坐标/视野发送到已启用天气来源和 Overpass；地图瓦片请求发送标准瓦片坐标。\n'
            '· 混合搜索会把关键词发送给地点搜索；只有你主动点击外部攻略入口时，才在系统浏览器用百度搜索小红书/两步路/六只脚。App 不读取 Cookie，也不抓取或缓存外部网页内容。\n'
            '· 拒绝定位后仍可手动点选地图、搜索地点和查看线路天气。\n'
            '· 日志不记录你的完整轨迹与精确位置；来源异常仅记录端点与状态码。\n'
            '· 缓存仅在本机；可在“缓存管理”随时清除。\n'
            '· 分享/导出线路时请注意其中可能包含住宅、常去出发点等敏感位置。\n'
            '· 本 App 的天气提示不能替代官方预警与户外安全判断。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text(S.close),
          ),
        ],
      ),
    );
  }

  Widget _buildProBanner(
    BuildContext context,
    WidgetRef ref,
    UserSubscription sub,
  ) {
    final theme = Theme.of(context);
    final isPro = sub.isPro;

    return Card(
      elevation: isPro ? 2 : 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isPro
              ? Colors.amber.shade600
              : theme.colorScheme.primary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: isPro
                ? [const Color(0xFFFFF8E1), const Color(0xFFFFECB3)]
                : [
                    theme.colorScheme.primary.withValues(alpha: 0.12),
                    theme.colorScheme.primary.withValues(alpha: 0.04),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.workspace_premium,
                  color: isPro
                      ? Colors.amber.shade800
                      : theme.colorScheme.primary,
                  size: 26,
                ),
                const SizedBox(width: 8),
                Text(
                  isPro ? 'TrailWeather Pro 尊享会员' : 'TrailWeather Pro（规划中）',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (isPro)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade800,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      sub.plan == SubscriptionPlan.lifetime
                          ? '终身尊享'
                          : (sub.isTrial ? '试用中' : '有效中'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isPro
                  ? (sub.expiresAtUtc != null
                        ? '有效期至：${sub.expiresAtUtc!.toLocal().year}-${sub.expiresAtUtc!.toLocal().month.toString().padLeft(2, '0')}-${sub.expiresAtUtc!.toLocal().day.toString().padLeft(2, '0')}'
                        : '终身会员已永久激活，尊享所有后续专业算法与离网包升级。')
                  : '高程气温修正、失温提示、离线气象包与等高线地形图正在开发中，支付尚未接入。当前已上线的功能全部免费可用。',
              style: TextStyle(
                fontSize: 12,
                color: isPro ? Colors.amber.shade900 : Colors.grey.shade700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isPro)
                  FilledButton.icon(
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text(
                      '查看方案预览',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => context.push('/paywall'),
                  )
                else
                  OutlinedButton(
                    onPressed: () => context.push('/paywall'),
                    child: const Text('会员权益详情', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 和风天气密钥配置（仅存本机，不上传）。
/// 免费订阅即可获得；2024 起新账号需使用控制台分配的专属 API Host。
class _QweatherCredentialsCard extends ConsumerStatefulWidget {
  const _QweatherCredentialsCard();

  @override
  ConsumerState<_QweatherCredentialsCard> createState() =>
      _QweatherCredentialsCardState();
}

class _QweatherCredentialsCardState
    extends ConsumerState<_QweatherCredentialsCard> {
  late final TextEditingController _host = TextEditingController(
    text: ref.read(settingsProvider).qweatherApiHost,
  );
  late final TextEditingController _key = TextEditingController(
    text: ref.read(settingsProvider).qweatherApiKey,
  );

  @override
  void dispose() {
    _host.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
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
                  child: Text('和风天气（大陆直连推荐）', style: TextStyle(fontSize: 14)),
                ),
                if (settings.qweatherConfigured)
                  const Icon(Icons.check_circle, size: 16, color: Colors.green)
                else
                  const Text(
                    '未配置',
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '在 dev.qweather.com 免费注册订阅后，于“控制台”查看你的 API Key 与 API Host'
              '（新账号为专属域名，形如 abc123.qweatherapi.com；旧账号可用 devapi.qweather.com）。'
              '密钥仅保存在本机。未配置时该来源会显示配置指引，其余来源不受影响。',
              style: TextStyle(fontSize: 11, height: 1.5, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'API Host',
                hintText: 'abc123.qweatherapi.com',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _key,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () async {
                  await ref
                      .read(settingsProvider.notifier)
                      .update(
                        settings.copyWith(
                          qweatherApiHost: _host.text.trim(),
                          qweatherApiKey: _key.text.trim(),
                        ),
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已保存（仅本机）')));
                  }
                },
                child: const Text('保存', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CacheCard extends ConsumerStatefulWidget {
  const _CacheCard();

  @override
  ConsumerState<_CacheCard> createState() => _CacheCardState();
}

class _CacheCardState extends ConsumerState<_CacheCard> {
  Map<String, (int, int)>? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cache = CacheStore(ref.read(prefsProvider));
    final stats = <String, (int, int)>{};
    for (final ns in CacheNs.all) {
      stats[ns] = (await cache.entryCount(ns), cache.approxSizeBytes(ns));
    }
    setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) {
    final names = {
      CacheNs.routes: '线路数据',
      CacheNs.map: '地图/区域查询',
      CacheNs.weather: '天气数据',
      CacheNs.user: '用户数据',
    };
    return Card(
      child: Column(
        children: [
          for (final ns in CacheNs.all)
            ListTile(
              dense: true,
              title: Text(
                '${names[ns]}（${_stats?[ns]?.$1 ?? 0} 条 · ${((_stats?[ns]?.$2 ?? 0) / 1024).toStringAsFixed(0)} KB）',
                style: const TextStyle(fontSize: 13),
              ),
              trailing: TextButton(
                child: const Text('清除', style: TextStyle(fontSize: 12)),
                onPressed: () async {
                  final cache = CacheStore(ref.read(prefsProvider));
                  await cache.clearNamespace(ns);
                  await _load();
                },
              ),
            ),
        ],
      ),
    );
  }
}
