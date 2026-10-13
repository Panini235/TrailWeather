import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cache_store.dart';
import '../../data/app_providers.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text(S.settings)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _section(context, '单位'),
          Card(child: Column(children: [
            SwitchListTile(
              title: const Text('英制单位', style: TextStyle(fontSize: 14)),
              subtitle: const Text('温度 °F、距离 mi、降水 in', style: TextStyle(fontSize: 11)),
              value: settings.imperial,
              onChanged: (v) => notifier.update(settings.copyWith(imperial: v)),
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
                onChanged: (v) =>
                    notifier.update(settings.copyWith(windUnit: v ?? 'km/h')),
              ),
            ),
          ])),
          _section(context, '外观'),
          Card(child: ListTile(
            dense: true,
            title: const Text('主题', style: TextStyle(fontSize: 14)),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('系统', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色', style: TextStyle(fontSize: 12))),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => notifier.update(settings.copyWith(themeMode: s.first)),
            ),
          )),
          _section(context, '地图底图'),
          Card(child: ListTile(
            dense: true,
            title: const Text('底图来源', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '高德（国内直连快，GCJ-02 显示坐标，业务数据仍为 WGS-84）/ OSM（海外网络）',
              style: TextStyle(fontSize: 11),
            ),
            trailing: SegmentedButton<BasemapSource>(
              segments: const [
                ButtonSegment(value: BasemapSource.amap, label: Text('高德', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: BasemapSource.osm, label: Text('OSM', style: TextStyle(fontSize: 12))),
              ],
              selected: {settings.basemap},
              onSelectionChanged: (sel) =>
                  notifier.update(settings.copyWith(basemap: sel.first)),
            ),
          )),
          _section(context, '数据源密钥'),
          const _QweatherCredentialsCard(),
          _section(context, '天气来源'),
          Card(child: Column(children: [
            for (final p in providers)
              SwitchListTile(
                dense: true,
                title: Text(p.caps.displayName, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  '${p.caps.vendor} · 覆盖 ${p.caps.coverage} · 预报 ${p.caps.forecastHorizonDays} 天 · ${p.caps.requiresApiKey ? '需密钥' : '无需密钥'}',
                  style: const TextStyle(fontSize: 11),
                ),
                value: settings.enabledProviderIds.contains(p.caps.providerId),
                onChanged: (_) => notifier.toggleProvider(p.caps.providerId),
              ),
            ListTile(
              dense: true,
              title: const Text('来源能力与授权对照', style: TextStyle(fontSize: 13)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => _showCapabilities(context, [for (final p in providers) p.caps]),
            ),
          ])),
          _section(context, '低耗电'),
          Card(child: Column(children: [
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
              title: Text('采样间距：${settings.samplingSpacingKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 14)),
              subtitle: const Text('线路天气节点的采样间距（工程参数，不代表天气空间分辨率）', style: TextStyle(fontSize: 11)),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: settings.samplingSpacingKm,
                  min: 1,
                  max: 3,
                  divisions: 4,
                  label: '${settings.samplingSpacingKm.toStringAsFixed(1)} km',
                  onChanged: (v) => notifier.update(settings.copyWith(samplingSpacingKm: v)),
                ),
              ),
            ),
          ])),
          _section(context, '缓存与数据'),
          const _CacheCard(),
          Card(child: Column(children: [
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
              subtitle: const Text('收藏与导入线路导出为 JSON 文本（本地操作，不上传）', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.copy, size: 18),
              onTap: () async {
                final json = ref.read(favoritesProvider.notifier).exportJson();
                await _copy(context, json);
              },
            ),
          ])),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
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
          actions: [TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text(S.close))],
        ),
      );
    }
  }

  void _showCapabilities(BuildContext context, List<ProviderCapabilities> caps) {
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
                      Text(c.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '服务商：${c.vendor}\n模型：${c.modelOrNetwork}\n覆盖：${c.coverage}\n'
                        '时效：${c.forecastHorizonDays} 天 · 间隔 ${c.intervalHours} h\n'
                        '空间分辨率：${c.spatialResolutionNote ?? '来源未提供'}\n'
                        'Web 端：${c.browserNotes}\n授权：${c.license}\n署名：${c.attribution}',
                        style: const TextStyle(fontSize: 11, height: 1.5),
                      ),
                      if (c.modelOverlapNote != null)
                        Text(c.modelOverlapNote!, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text(S.close))],
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
            '地图瓦片：© OpenStreetMap 贡献者（ODbL）。仅在线显示，不预下载。\n\n'
            '徒步线路（OSM）：© OpenStreetMap 贡献者，ODbL 1.0。线路几何来自 Overpass API 按视野查询；App 展示不构成对路线可通行性或许可进入的担保。\n\n'
            '天气：Open-Meteo（CC BY 4.0，非商业免费额度；模型来自 NOAA 等机构）；MET Norway Locationforecast 2.0（NLOD 2.0 / CC BY 4.0）。\n\n'
            '地点搜索：Open-Meteo Geocoding（GeoNames/知识共享数据）。\n\n'
            '内置示例线路为本项目演示数据（已标注“演示”），非实测。\n\n'
            '完整对照表与条款链接见 docs/data-sources.md。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text(S.close))],
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
            '· 不默认上传你的轨迹、精确位置或收藏；全部保存在本机。\n'
            '· 仅在你点击“定位到我”时读取位置（一次性），拒绝后功能仍完整。\n'
            '· 天气与线路请求会把对应坐标发送到所选数据服务（Open-Meteo / MET Norway / Overpass / OSM 瓦片）以获取数据；这是获取服务所必需的最小信息。\n'
            '· 日志不记录你的完整轨迹与精确位置；来源异常仅记录端点与状态码。\n'
            '· 缓存仅在本机；可在“缓存管理”随时清除。\n'
            '· 分享/导出线路时请注意其中可能包含住宅、常去出发点等敏感位置。\n'
            '· 本 App 的天气提示不能替代官方预警与户外安全判断。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text(S.close))],
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
  late final TextEditingController _host =
      TextEditingController(text: ref.read(settingsProvider).qweatherApiHost);
  late final TextEditingController _key =
      TextEditingController(text: ref.read(settingsProvider).qweatherApiKey);

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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.vpn_key_outlined, size: 16),
            const SizedBox(width: 6),
            const Expanded(child: Text('和风天气（大陆直连推荐）', style: TextStyle(fontSize: 14))),
            if (settings.qweatherConfigured)
              const Icon(Icons.check_circle, size: 16, color: Colors.green)
            else
              const Text('未配置', style: TextStyle(fontSize: 11, color: Colors.orange)),
          ]),
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
                await ref.read(settingsProvider.notifier).update(
                      settings.copyWith(
                        qweatherApiHost: _host.text.trim(),
                        qweatherApiKey: _key.text.trim(),
                      ),
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已保存（仅本机）')));
                }
              },
              child: const Text('保存', style: TextStyle(fontSize: 13)),
            ),
          ),
        ]),
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
              title: Text('${names[ns]}（${_stats?[ns]?.$1 ?? 0} 条 · ${((_stats?[ns]?.$2 ?? 0) / 1024).toStringAsFixed(0)} KB）',
                  style: const TextStyle(fontSize: 13)),
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
