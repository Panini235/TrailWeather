import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/routes/geojson_import.dart';
import '../../data/routes/gpx_import.dart';
import '../../data/routes/kml_import.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/favorites_repository.dart';
import '../detail/route_detail_screen.dart';
import '../strings.dart';
import '../widgets/common.dart';

/// 导入 GPX / KML / GeoJSON。
///
/// 安全与鲁棒性：
/// - 单文件上限 30MB，超长轨迹自适应平滑抽稀（保留最高/最低海拔与关键转向）；
/// - XML 使用纯 Dart 解析器，不启用外部实体（防 XXE）；
/// - 异常海拔与漂移点自动过滤清洗，不直接报错；
/// - 导入内容仅存本机（收藏），不上传；
/// - 提示：线路可能包含住宅、常去出发点等敏感位置，分享前请注意。
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _textCtrl = TextEditingController();
  String? _error;
  List<String> _warnings = const [];
  bool _loading = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    const typeGroup = XTypeGroup(
      label: 'GPX / KML / GeoJSON',
      extensions: ['gpx', 'kml', 'kmz', 'geojson', 'json', 'xml', 'txt', 'gsx'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    setState(() => _loading = true);
    try {
      final bytes = await file.readAsBytes();
      // 容错解码（防止非纯 UTF-8 编码或老旧设备导出的文本抛异常）
      final content = utf8.decode(bytes, allowMalformed: true);
      _textCtrl.text = content;
      unawaited(_import(content, file.name));
    } catch (e) {
      setState(() {
        _error = '读取文件失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _import(String content, String fileName) async {
    setState(() {
      _error = null;
      _warnings = const [];
    });
    try {
      HikingRoute route;
      var trimmed = content.trimLeft();
      if (trimmed.startsWith('\uFEFF')) {
        trimmed = trimmed.substring(1).trimLeft();
      }

      if (trimmed.startsWith('<')) {
        // XML 格式：智能嗅探 KML 与 GPX
        final lowerSnippet = trimmed.length > 500
            ? trimmed.substring(0, 500).toLowerCase()
            : trimmed.toLowerCase();
        if (lowerSnippet.contains('<kml') || lowerSnippet.contains('kml:')) {
          final parsed = KmlImport.parse(trimmed);
          _warnings = parsed.warnings;
          route = KmlImport.toRoute(parsed, fileName: fileName);
        } else if (lowerSnippet.contains('<gpx') ||
            lowerSnippet.contains('gpx:')) {
          final parsed = GpxImport.parse(trimmed);
          _warnings = parsed.warnings;
          route = GpxImport.toRoute(parsed, fileName: fileName);
        } else {
          // 未明确标明，优先尝试 GPX，若失败尝试 KML
          try {
            final parsed = GpxImport.parse(trimmed);
            _warnings = parsed.warnings;
            route = GpxImport.toRoute(parsed, fileName: fileName);
          } catch (_) {
            final parsed = KmlImport.parse(trimmed);
            _warnings = parsed.warnings;
            route = KmlImport.toRoute(parsed, fileName: fileName);
          }
        }
      } else if (trimmed.startsWith('{')) {
        route = GeoJsonImport.toRoute(trimmed, fileName: fileName);
      } else {
        throw const FormatException('无法识别的文件格式。请选择标准的 GPX、KML 或 GeoJSON 文件。');
      }

      final ok = await _confirm(route);
      if (!ok) {
        setState(() => _loading = false);
        return;
      }
      await ref.read(favoritesProvider.notifier).add(route);
      if (mounted) {
        unawaited(
          context.push(
            '/route/${route.id}',
            extra: RouteDetailArgs(route: route),
          ),
        );
      }
    } on GpxImportException catch (e) {
      setState(() => _error = e.message);
    } on KmlImportException catch (e) {
      setState(() => _error = e.message);
    } on GeoJsonImportException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '导入失败：$e');
    }
    setState(() => _loading = false);
  }

  Future<bool> _confirm(HikingRoute route) async {
    // 展示解析摘要，用户确认后保存。
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        title: Text('导入：${route.name}'),
        content: Text(
          '段数：${route.segments.length}\n'
          '总点数：${route.flatPoints.length}\n'
          '长度：约 ${(route.totalDistanceM / 1000).toStringAsFixed(1)} km\n'
          '累计爬升：${route.totalAscentM == null ? S.unknown : '${(route.totalAscentM! / 1000).toStringAsFixed(2)} km'}\n\n'
          '线路将保存到本机收藏（不上传）。注意：线路数据可能包含住宅、常去出发点等敏感位置，分享前请自行判断。',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('保存到收藏'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.importRoute)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.icon(
                    onPressed: _loading ? null : _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择 GPX / KML / GeoJSON 文件'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '支持标准 GPX、KML（奥维互动地图/两步路/Google Earth）与 GeoJSON。'
                    '单文件上限 30MB，超长轨迹自动平滑抽稀保留峰顶与关键地形特征，异常漂移点自动过滤。纯本地解析，不上传云端。',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('或粘贴内容：'),
          const SizedBox(height: 4),
          TextField(
            controller: _textCtrl,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '<gpx …> 或 {"type": "FeatureCollection", …}',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _loading
                ? null
                : () => _import(_textCtrl.text, 'pasted-import'),
            child: const Text('解析并导入'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ErrorCard(title: '导入失败', detail: _error!),
            ),
          for (final w in _warnings)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: GranularityNotice(text: w),
            ),
        ],
      ),
    );
  }
}
