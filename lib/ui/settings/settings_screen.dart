import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/cache_store.dart';
import '../../data/app_providers.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/meteoblue_settings.dart';
import '../../data/weather/weather_models.dart';
import '../map/basemap.dart';
import '../map/map_layers_ui.dart';
import '../strings.dart';
import '../departure/departure_threshold_screen.dart';
import 'feedback_sheet.dart';
import 'meteoblue_card.dart';
import '../widgets/common.dart';

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
          _section(context, S.settingsDisplaySection),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text(
                    S.settingsImperial,
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    S.settingsImperialHint,
                    style: TextStyle(fontSize: 11),
                  ),
                  value: settings.imperial,
                  onChanged: (v) =>
                      notifier.update(settings.copyWith(imperial: v)),
                ),
                ListTile(
                  dense: true,
                  title: const Text(
                    S.settingsWindUnit,
                    style: TextStyle(fontSize: 14),
                  ),
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
          Card(
            child: ListTile(
              dense: true,
              title: const Text(
                S.settingsTheme,
                style: TextStyle(fontSize: 14),
              ),
              trailing: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(
                      S.settingsThemeSystem,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(
                      S.settingsThemeLight,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(
                      S.settingsThemeDark,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (s) =>
                    notifier.update(settings.copyWith(themeMode: s.first)),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: const Text(S.departureThresholdTitle),
              subtitle: const Text(S.settingsThresholdHint),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DepartureThresholdScreen(),
                ),
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  title: const Text(
                    S.settingsLowPower,
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    S.settingsLowPowerHint,
                    style: TextStyle(fontSize: 11),
                  ),
                  value: settings.lowPower,
                  onChanged: notifier.setLowPower,
                ),
                ListTile(
                  dense: true,
                  title: Text(
                    S.settingsSamplingSpacing(
                      settings.samplingSpacingKm.toStringAsFixed(1),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    S.settingsSamplingSpacingHint,
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
          Card(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.layers_outlined),
                  title: const Text(
                    S.mapLayers,
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    '${Basemap.fromSettings(settings).style.base.name}'
                    '${settings.overlayLayers.isEmpty ? '' : S.settingsOverlayCount(settings.overlayLayers.length)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showMapLayerSheet(context),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.tune),
                  title: const Text(
                    S.manageTileSources,
                    style: TextStyle(fontSize: 14),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MapSourcesPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _section(context, S.settingsSourcesSection),
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
                      S.settingsProviderSubtitle(
                        p.caps.vendor,
                        p.caps.coverage,
                        p.caps.forecastHorizonDays,
                        p.caps.requiresApiKey,
                      ),
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
                    S.settingsCapabilities,
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
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.vpn_key_outlined, size: 20),
              title: const Text(
                S.settingsApiKeys,
                style: TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                S.settingsApiKeysStatus(
                  settings.qweatherConfigured,
                  ref.watch(meteoblueSettingsProvider).configured,
                ),
                style: const TextStyle(fontSize: 11),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: const [
                _QweatherCredentialsCard(),
                MeteoblueCredentialsCard(),
              ],
            ),
          ),
          _section(context, S.settingsDataSection),
          Card(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.explore_outlined, size: 20),
                  title: const Text(
                    S.settingsGuide,
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    S.settingsGuideHint,
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => context.push('/onboarding'),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.feedback_outlined, size: 20),
                  title: const Text(
                    S.feedbackTitle,
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    S.feedbackSubtitle,
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => showFeedbackSheet(context, ref),
                ),
              ],
            ),
          ),
          const _CacheCard(),
          Card(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.verified_user_outlined, size: 20),
                  title: const Text(
                    S.settingsAttribution,
                    style: TextStyle(fontSize: 13),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _showAttribution(context),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.privacy_tip_outlined, size: 20),
                  title: const Text(
                    S.privacyTitle,
                    style: TextStyle(fontSize: 13),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => context.push('/privacy'),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.file_download_outlined, size: 20),
                  title: const Text(
                    S.settingsExport,
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    S.settingsExportHint,
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
          title: const Text(S.settingsExportDone),
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
        title: const Text(S.settingsCapabilities),
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
                        S.settingsCapabilityDetails(
                          vendor: c.vendor,
                          model: c.modelOrNetwork,
                          coverage: c.coverage,
                          horizonDays: c.forecastHorizonDays,
                          intervalHours: c.intervalHours,
                          resolution: c.spatialResolutionNote,
                          browserNotes: c.browserNotes,
                          license: c.license,
                          attribution: c.attribution,
                        ),
                        style: const TextStyle(fontSize: 11, height: 1.5),
                      ),
                      if (c.modelOverlapNote != null)
                        Text(
                          c.modelOverlapNote!,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
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
        title: const Text(S.settingsAttribution),
        content: const SingleChildScrollView(
          child: Text(
            S.settingsAttributionBody,
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
}

/// 和风天气密钥配置（仅存本机，不上传）。
/// 使用用户在和风控制台开通的 API 服务和专属 API Host。
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
                  child: Text(
                    S.settingsQweatherTitle,
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                ConfiguredStatus(configured: settings.qweatherConfigured),
              ],
            ),
            const SizedBox(height: 4),
            const HelpText(S.settingsQweatherHelp),
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
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text(S.saved)));
                  }
                },
                child: const Text(S.save, style: TextStyle(fontSize: 13)),
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
      CacheNs.routes: S.settingsCacheRoutes,
      CacheNs.map: S.settingsCacheMap,
      CacheNs.weather: S.settingsCacheWeather,
      CacheNs.user: S.settingsCacheUser,
    };
    return Card(
      child: Column(
        children: [
          for (final ns in CacheNs.all)
            ListTile(
              dense: true,
              title: Text(
                S.settingsCacheEntry(
                  names[ns],
                  _stats?[ns]?.$1 ?? 0,
                  ((_stats?[ns]?.$2 ?? 0) / 1024).toStringAsFixed(0),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              trailing: TextButton(
                child: const Text(
                  S.settingsCacheClear,
                  style: TextStyle(fontSize: 12),
                ),
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
