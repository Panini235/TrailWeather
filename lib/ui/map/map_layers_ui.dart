import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/map/tile_sources.dart';
import '../../data/settings/settings_repository.dart';
import '../strings.dart';
import '../widgets/common.dart';

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
    final style = resolveMapStyle(
      baseLayerId: settings.baseLayerId,
      overlays: settings.overlayLayers,
      custom: settings.customTileSources,
      tiandituKey: settings.tiandituKey,
    );
    final sources = allTileSources(settings.customTileSources);
    final key = settings.tiandituKey;
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
                    '${usable ? s.note : S.tiandituKeyMissing}',
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
                  tiandituKey: key,
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
  late final TextEditingController _key = TextEditingController(
    text: ref.read(settingsProvider).tiandituKey,
  );

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(settingsProvider).tiandituKey.isNotEmpty;
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
                    S.tiandituKeyTitle,
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                if (configured)
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
              S.tiandituKeyHelp,
              style: TextStyle(fontSize: 11, height: 1.5, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _key,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: S.tiandituKeyTitle,
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
                      .setTiandituKey(_key.text);
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
