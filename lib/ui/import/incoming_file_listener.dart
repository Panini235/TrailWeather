import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/routes/incoming_file_source.dart';
import '../../data/routes/route_file_import.dart';
import '../../data/settings/settings_repository.dart';
import 'import_flow.dart';
import '../strings.dart';

/// 监听外部应用传入的轨迹文件，解析后走与导入页相同的确认 → 保存 → 打开详情流程。
/// 首次启动尚未同意隐私说明时先暂存文件，同意并回到主界面后再处理。
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

  /// 已处理过的文件标识：iOS 冷启动时同一文件可能既经 onFile 推送、又经 getInitialFile 取到。
  final Set<String> _handled = {};

  /// 同意隐私说明前收到的文件。
  IncomingFile? _pending;

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
    if (!mounted) return;
    if (!ref.read(settingsProvider).privacyAccepted) {
      _pending = file;
      return;
    }
    if (_busy || !_handled.add(file.uri)) return;
    _busy = true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(S.importIncomingParsing(file.name))),
    );
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
        SnackBar(content: Text(S.importIncomingFailed(file.name, e.message))),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(S.importIncomingReadFailed(file.name, '$e'))),
      );
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accepted = ref.watch(
      settingsProvider.select((s) => s.privacyAccepted),
    );
    // 依赖路由状态：引导页等上层页面关闭后才处理暂存文件，
    // 否则确认框会挂在即将移除的页面上被一并关掉。
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    final file = _pending;
    if (file != null && accepted && onTop) {
      _pending = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _handle(file));
    }
    return widget.child;
  }
}
