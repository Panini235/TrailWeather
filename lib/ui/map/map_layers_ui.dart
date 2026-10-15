import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/map/tianditu.dart';
import '../../data/map/tile_sources.dart';
import '../../data/settings/settings_repository.dart';
import '../strings.dart';
import '../widgets/common.dart';
import 'basemap.dart';

/// 地图上的“图层”按钮：打开底图/叠加层选择面板。
class MapLayerButton extends StatelessWidget {
  const MapLayerButton({super.key, this.heroTag = 'mapLayers'});

  final Object heroTag;

  @override
  Widget build(BuildContext context) => FloatingActionButton.small(
    heroTag: heroTag,
    tooltip: S.mapLayers,
    onPressed: () => showMapLayerSheet(context),
    child: const Icon(Icons.layers_outlined),
  );
}

Future<void> showMapLayerSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => MapLayerPanel(scrollController: controller),
      ),
    );

IconData _categoryIcon(TileCategory c) => switch (c) {
  TileCategory.standard => Icons.map_outlined,
  TileCategory.satellite => Icons.satellite_alt_outlined,
  TileCategory.terrain => Icons.terrain_outlined,
  TileCategory.annotation => Icons.text_fields,
  TileCategory.custom => Icons.tune,
};

/// 底图单选 + 叠加层开关/透明度。
class MapLayerPanel extends ConsumerWidget {
  const MapLayerPanel({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final style = Basemap.fromSettings(settings).style;
    final sources = allTileSources(settings.customTileSources);
    final keys = settings.tiandituKeys;
    final key = keys.forRequester(flutterMapRequester);
    final selected = {for (final o in settings.overlayLayers) o.id: o};
    final muted = TextStyle(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        Text(S.mapLayers, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const GranularityNotice(text: S.mapLayerDatumNote),
        if (style.baseFallbackReason != null) ...[
          const SizedBox(height: 6),
          GranularityNotice(text: style.baseFallbackReason!),
        ],
        const TiandituErrorBanner(margin: EdgeInsets.only(top: 6)),
        const SizedBox(height: 8),
        Text(S.baseLayer, style: Theme.of(context).textTheme.titleSmall),
        for (final s in sources)
          if (!s.overlayOnly)
            Builder(
              builder: (context) {
                final usable = s.resolvedTemplate(tiandituKey: key) != null;
                final isBase = style.base.id == s.id;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  enabled: usable,
                  leading: Icon(
                    isBase
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isBase
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Row(
                    children: [
                      Icon(_categoryIcon(s.category), size: 16),
                      const SizedBox(width: 6),
                      Flexible(child: Text(s.name)),
                    ],
                  ),
                  subtitle: Text(
                    '${datumLabel(s.datum)} · '
                    '${usable ? s.note : _keyMissingText(flutterMapRequester)}',
                    style: muted,
                  ),
                  onTap: usable ? () => notifier.setBaseLayer(s.id) : null,
                );
              },
            ),
        const Divider(height: 20),
        Text(S.overlayLayers, style: Theme.of(context).textTheme.titleSmall),
        for (final s in sources)
          if (s.id != style.base.id)
            Builder(
              builder: (context) {
                final reason = overlayBlockReason(
                  style.base,
                  s,
                  tiandituKeys: keys,
                  requester: flutterMapRequester,
                );
                final sel = selected[s.id];
                final on = sel != null && reason == null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(_categoryIcon(s.category), size: 18),
                      title: Text(s.name),
                      subtitle: Text(
                        reason ?? '${datumLabel(s.datum)} · ${s.note}',
                        style: muted,
                      ),
                      value: on,
                      onChanged: reason == null
                          ? (_) => notifier.toggleOverlay(s.id)
                          : null,
                    ),
                    if (on)
                      Row(
                        children: [
                          const SizedBox(width: 40),
                          Text(S.overlayOpacity, style: muted),
                          Expanded(
                            child: Slider(
                              value: sel.opacity,
                              min: 0.1,
                              max: 1.0,
                              divisions: 9,
                              label: '${(sel.opacity * 100).round()}%',
                              onChanged: (v) =>
                                  notifier.setOverlayOpacity(s.id, v),
                            ),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MapSourcesPage()),
          ),
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: const Text(S.manageTileSources),
        ),
      ],
    );
  }
}

/// 天地图 Key 与自定义图源管理页。
class MapSourcesPage extends StatelessWidget {
  const MapSourcesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(S.manageTileSources)),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: const [
        TiandituKeyCard(),
        SizedBox(height: 8),
        CustomTileSourcesCard(),
      ],
    ),
  );
}

class TiandituKeyCard extends ConsumerStatefulWidget {
  const TiandituKeyCard({super.key});

  @override
  ConsumerState<TiandituKeyCard> createState() => _TiandituKeyCardState();
}

class _TiandituKeyCardState extends ConsumerState<TiandituKeyCard> {
  late final TextEditingController _server = TextEditingController(
    text: ref.read(settingsProvider).tiandituServerKey,
  );
  late final TextEditingController _browser = TextEditingController(
    text: ref.read(settingsProvider).tiandituBrowserKey,
  );

  @override
  void dispose() {
    _server.dispose();
    _browser.dispose();
    super.dispose();
  }

  Widget _status(bool configured) => configured
      ? const Icon(Icons.check_circle, size: 16, color: Colors.green)
      : const Text(
          S.tiandituKeyNotConfigured,
          style: TextStyle(fontSize: 11, color: Colors.orange),
        );

  Widget _field(
    TextEditingController c, {
    required String label,
    required String hint,
    required bool configured,
  }) => TextField(
    controller: c,
    obscureText: true,
    decoration: InputDecoration(
      labelText: label,
      helperText: hint,
      helperMaxLines: 2,
      isDense: true,
      border: const OutlineInputBorder(),
      suffixIcon: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: _status(configured),
      ),
      suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final keys = ref.watch(settingsProvider).tiandituKeys;
    final error = ref.watch(tiandituErrorProvider);
    final errorColor = Theme.of(context).colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.vpn_key_outlined, size: 16),
                SizedBox(width: 6),
                Text(S.tiandituKeyTitle, style: TextStyle(fontSize: 14)),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              S.tiandituKeyHelp,
              style: TextStyle(fontSize: 11, height: 1.5, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(switch (flutterMapRequester) {
              TileRequester.nativeApp => S.tiandituUsingServerKey,
              TileRequester.browser => S.tiandituUsingBrowserKey,
            }, style: const TextStyle(fontSize: 11, height: 1.5)),
            const SizedBox(height: 10),
            _field(
              _server,
              label: S.tiandituServerKeyLabel,
              hint: S.tiandituServerKeyHint,
              configured: keys.server.trim().isNotEmpty,
            ),
            const SizedBox(height: 10),
            _field(
              _browser,
              label: S.tiandituBrowserKeyLabel,
              hint: S.tiandituBrowserKeyHint,
              configured: keys.browser.trim().isNotEmpty,
            ),
            if (keys.sameValueInBoth) ...[
              const SizedBox(height: 8),
              const GranularityNotice(text: S.tiandituSameKeyWarning),
            ],
            if (error != null &&
                error.key == keys.forRequester(flutterMapRequester)) ...[
              const SizedBox(height: 8),
              Text(
                tiandituErrorText(error),
                style: TextStyle(fontSize: 12, height: 1.4, color: errorColor),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () async {
                  await ref
                      .read(settingsProvider.notifier)
                      .setTiandituKeys(
                        server: _server.text,
                        browser: _browser.text,
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text(S.saved)));
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

String _keyMissingText(TileRequester r) => switch (r) {
  TileRequester.nativeApp => S.tiandituServerKeyMissing,
  TileRequester.browser => S.tiandituBrowserKeyMissing,
};

/// 天地图错误码 → 提示文案。
String tiandituErrorText(TiandituTileError e) => switch (e.kind) {
  TiandituErrorKind.invalidKey => S.tiandituErrInvalidKey,
  TiandituErrorKind.browserKeyNotInBrowser =>
    S.tiandituErrBrowserKeyNotInBrowser,
  TiandituErrorKind.serverKeyInBrowser => S.tiandituErrServerKeyInBrowser,
  TiandituErrorKind.blocked => S.tiandituErrBlocked,
  TiandituErrorKind.other =>
    '${S.tiandituErrOther}（HTTP ${e.statusCode}'
        '${e.code == null ? '' : '，code ${e.code}'}）',
};

/// 地图上的天地图错误提示：当前图层用到天地图、且错误来自当前所用 Key 时显示，
/// 避免只留空白瓦片。可关闭；“设置”打开 Key 管理页。
class TiandituErrorBanner extends ConsumerWidget {
  const TiandituErrorBanner({
    super.key,
    this.compact = false,
    this.margin = EdgeInsets.zero,
  });

  /// 小地图用：文案最多两行。
  final bool compact;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(tiandituErrorProvider);
    final settings = ref.watch(settingsProvider);
    if (error == null ||
        !Basemap.fromSettings(settings).style.usesTianditu ||
        error.key != settings.tiandituKeys.forRequester(flutterMapRequester)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: margin,
      child: Material(
        color: scheme.errorContainer.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  compact
                      ? tiandituErrorText(error)
                      : '${S.tiandituErrorTitle}：${tiandituErrorText(error)}',
                  maxLines: compact ? 2 : null,
                  overflow: compact ? TextOverflow.ellipsis : null,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
              IconButton(
                tooltip: S.tiandituOpenKeySettings,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.vpn_key_outlined, size: 18),
                color: scheme.onErrorContainer,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MapSourcesPage(),
                  ),
                ),
              ),
              IconButton(
                tooltip: S.close,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                color: scheme.onErrorContainer,
                onPressed: () =>
                    ref.read(tiandituErrorProvider.notifier).dismiss(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomTileSourcesCard extends ConsumerWidget {
  const CustomTileSourcesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = ref.watch(settingsProvider).customTileSources;
    final notifier = ref.read(settingsProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(S.customTileSources, style: TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            const Text(
              S.customTileSourcesHelp,
              style: TextStyle(fontSize: 11, height: 1.5, color: Colors.grey),
            ),
            if (custom.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  S.noCustomTileSources,
                  style: TextStyle(fontSize: 12),
                ),
              ),
            for (final c in custom)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  c.overlayOnly ? Icons.layers : Icons.map_outlined,
                ),
                title: Text(c.name),
                subtitle: Text(
                  '${datumLabel(c.datum)} · ${c.urlTemplate}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => notifier.removeCustomTileSource(c.id),
                ),
                onTap: () async {
                  final edited = await showCustomTileSourceEditor(
                    context,
                    existing: c,
                  );
                  if (edited != null) {
                    await notifier.upsertCustomTileSource(edited);
                  }
                },
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  final created = await showCustomTileSourceEditor(context);
                  if (created != null) {
                    await notifier.upsertCustomTileSource(created);
                  }
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text(S.addCustomTileSource),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<TileSourceDef?> showCustomTileSourceEditor(
  BuildContext context, {
  TileSourceDef? existing,
}) => showDialog<TileSourceDef>(
  context: context,
  builder: (_) => _CustomTileSourceDialog(existing: existing),
);

class _CustomTileSourceDialog extends StatefulWidget {
  const _CustomTileSourceDialog({this.existing});

  final TileSourceDef? existing;

  @override
  State<_CustomTileSourceDialog> createState() =>
      _CustomTileSourceDialogState();
}

class _CustomTileSourceDialogState extends State<_CustomTileSourceDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _url = TextEditingController(
    text: widget.existing?.urlTemplate ?? '',
  );
  late final _subdomains = TextEditingController(
    text: widget.existing?.subdomains.join(',') ?? '',
  );
  late final _maxZoom = TextEditingController(
    text: '${widget.existing?.maxNativeZoom ?? 18}',
  );
  late final _attribution = TextEditingController(
    text: widget.existing?.attribution ?? '',
  );
  late TileDatum _datum = widget.existing?.datum ?? TileDatum.wgs84;
  late bool _overlayOnly = widget.existing?.overlayOnly ?? false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _url, _subdomains, _maxZoom, _attribution]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final subs = _subdomains.text
        .split(RegExp(r'[,，\s]+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final error = validateCustomTemplate(_url.text, subdomains: subs);
    final zoom = int.tryParse(_maxZoom.text.trim());
    final name = _name.text.trim();
    setState(() {
      _error =
          error ??
          (name.isEmpty ? '请填写名称' : null) ??
          (zoom == null || zoom < 1 || zoom > 22 ? '最大缩放级别需为 1–22' : null);
    });
    if (_error != null) return;
    Navigator.of(context).pop(
      TileSourceDef(
        id:
            widget.existing?.id ??
            'custom_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        category: TileCategory.custom,
        urlTemplate: _url.text.trim(),
        datum: _datum,
        attribution: _attribution.text.trim(),
        subdomains: subs,
        maxNativeZoom: zoom!,
        overlayOnly: _overlayOnly,
        note: '用户自定义图源：可用性与授权由使用者自行确认。',
        builtIn: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const dense = InputDecoration(isDense: true, border: OutlineInputBorder());
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? S.addCustomTileSource
            : S.editCustomTileSource,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: dense.copyWith(labelText: '名称'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: dense.copyWith(
                labelText: 'URL 模板',
                hintText: 'https://{s}.example.com/{z}/{x}/{y}.png',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _subdomains,
              decoration: dense.copyWith(
                labelText: '子域名（可选，逗号分隔）',
                hintText: 'a,b,c',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _maxZoom,
              keyboardType: TextInputType.number,
              decoration: dense.copyWith(labelText: '最大原生缩放级别'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _attribution,
              decoration: dense.copyWith(labelText: '署名（地图角标显示）'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('坐标系', style: TextStyle(fontSize: 13)),
                const Spacer(),
                SegmentedButton<TileDatum>(
                  segments: const [
                    ButtonSegment(
                      value: TileDatum.wgs84,
                      label: Text('WGS-84'),
                    ),
                    ButtonSegment(
                      value: TileDatum.gcj02,
                      label: Text('GCJ-02'),
                    ),
                  ],
                  selected: {_datum},
                  onSelectionChanged: (s) => setState(() => _datum = s.first),
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                S.customTileOverlayOnly,
                style: TextStyle(fontSize: 13),
              ),
              value: _overlayOnly,
              onChanged: (v) => setState(() => _overlayOnly = v),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(S.cancel),
        ),
        FilledButton(onPressed: _submit, child: const Text(S.ok)),
      ],
    );
  }
}
