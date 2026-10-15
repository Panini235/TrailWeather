import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/routes/route_file_import.dart';
import '../strings.dart';
import '../widgets/common.dart';
import 'import_flow.dart';

/// 导入 GPX / KML / KMZ / GeoJSON。
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

  /// 文件类型过滤：仅 Web/桌面按扩展名过滤。
  /// - Android：扩展名经 MimeTypeMap 转 MIME，gpx 等无映射，且文件管理器常报
  ///   application/octet-stream → 轨迹文件被置灰无法选择；
  /// - iOS：只给扩展名会直接抛 ArgumentError（要求 UTI）。
  /// 因此移动端不过滤，选中后按内容嗅探格式。
  static List<XTypeGroup> get _typeGroups {
    final mobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (mobile) return const [XTypeGroup(label: '轨迹文件')];
    return const [
      XTypeGroup(
        label: 'GPX / KML / KMZ / GeoJSON',
        extensions: ['gpx', 'kml', 'kmz', 'geojson', 'json', 'xml', 'txt'],
      ),
      XTypeGroup(label: '所有文件'),
    ];
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _warnings = const [];
    });
    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: _typeGroups);
    } catch (e) {
      setState(() => _error = '无法打开文件选择器：$e');
      return;
    }
    if (file == null) return;
    setState(() => _loading = true);
    try {
      final bytes = await file.readAsBytes();
      // 解析放到后台 isolate（Web 上 compute 同步执行），大文件不卡 UI。
      final result = await compute(importRouteFile, (
        bytes: bytes,
        fileName: file.name,
      ));
      await _finish(result);
    } on RouteImportException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '导入失败：$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _importPasted() async {
    setState(() {
      _error = null;
      _warnings = const [];
      _loading = true;
    });
    try {
      await _finish(RouteFileImport.fromText(_textCtrl.text, 'pasted-import'));
    } on RouteImportException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '导入失败：$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _finish(RouteImportResult result) async {
    if (!mounted) return;
    setState(() => _warnings = result.warnings);
    await confirmAndSaveImportedRoute(context, ref, result.route);
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
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.folder_open),
                    label: Text(
                      _loading ? '正在解析…' : '选择 GPX / KML / KMZ / GeoJSON 文件',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '支持标准 GPX、KML/KMZ（奥维互动地图/两步路/Google Earth）与 GeoJSON，按文件内容自动识别格式。'
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
            onPressed: _loading ? null : _importPasted,
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
