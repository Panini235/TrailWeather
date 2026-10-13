import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/routes/geojson_import.dart';
import '../../data/routes/gpx_import.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/favorites_repository.dart';
import '../detail/route_detail_screen.dart';
import '../strings.dart';
import '../widgets/common.dart';

/// 导入 GPX / GeoJSON。
///
/// 安全与限制：
/// - 输入大小 ≤ 2MB、点数 ≤ 5000、坐标/海拔/时间逐项校验；
/// - XML 使用纯 Dart 解析器，不启用外部实体（防 XXE）；
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
      label: 'GPX / GeoJSON',
      extensions: ['gpx', 'geojson', 'json', 'xml', 'txt'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    setState(() => _loading = true);
    try {
      final content = await file.readAsString();
      _textCtrl.text = content;
      _import(content, file.name);
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
      final HikingRoute route;
      final trimmed = content.trimLeft();
      if (trimmed.startsWith('<')) {
        final parsed = GpxImport.parse(content);
        _warnings = parsed.warnings;
        route = GpxImport.toRoute(parsed, fileName: fileName);
      } else {
        route = GeoJsonImport.toRoute(content, fileName: fileName);
      }
      final ok = await _confirm(route);
      if (!ok) {
        setState(() => _loading = false);
        return;
      }
      await ref.read(favoritesProvider.notifier).add(route);
      if (mounted) {
        context.push('/route/${route.id}',
            extra: RouteDetailArgs(route: route));
      }
    } on GpxImportException catch (e) {
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
                    label: const Text('选择 GPX / GeoJSON 文件'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '限制：≤ 2 MB、≤ 5000 点。坐标、海拔与时间字段逐项校验，'
                    '异常内容将被拒绝或忽略并提示。XML 解析不启用外部实体（防 XXE）。',
                    style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5),
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
            onPressed: _loading ? null : () => _import(_textCtrl.text, 'pasted-import'),
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
