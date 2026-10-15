import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/routes/incoming_file_source.dart';
import '../../data/routes/route_file_import.dart';
import 'import_flow.dart';

/// 监听外部应用传入的轨迹文件，解析后走与导入页相同的确认 → 保存 → 打开详情流程。
class IncomingFileListener extends ConsumerStatefulWidget {
  const IncomingFileListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IncomingFileListener> createState() =>
      _IncomingFileListenerState();
}

class _IncomingFileListenerState extends ConsumerState<IncomingFileListener> {
  StreamSubscription<IncomingFile>? _sub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final source = ref.read(incomingFileSourceProvider);
    _sub = source.files.listen(_handle);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final first = await source.initialFile();
      if (first != null) await _handle(first);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _handle(IncomingFile file) async {
    if (!mounted || _busy) return;
    _busy = true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('正在解析 ${file.name}…')));
    try {
      final bytes = await ref.read(incomingFileSourceProvider).readBytes(file);
      final result = await compute(importRouteFile, (
        bytes: bytes,
        fileName: file.name,
      ));
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      await confirmAndSaveImportedRoute(
        context,
        ref,
        result.route,
        warnings: result.warnings,
      );
    } on RouteImportException catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('无法导入 ${file.name}：${e.message}')),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('无法读取 ${file.name}：$e')));
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
