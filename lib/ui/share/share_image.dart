import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';

/// 把一张“分享卡片”渲染成 PNG，交给系统分享面板（微信 / QQ / X / Threads 等）。
///
/// 卡片是专门为图片排版的组件（固定宽度、浅色背景、自带来源与免责声明），
/// 不是屏幕截图；预览页让用户先看到将要分享的内容。
class SharePreviewPage extends StatefulWidget {
  const SharePreviewPage({
    super.key,
    required this.title,
    required this.card,
    required this.fileName,
    this.shareText,
  });

  final String title;
  final Widget card;
  final String fileName;
  final String? shareText;

  @override
  State<SharePreviewPage> createState() => _SharePreviewPageState();
}

class _SharePreviewPageState extends State<SharePreviewPage> {
  final _boundary = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    try {
      final bytes = await capturePng(_boundary);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png')],
          fileNameOverrides: [widget.fileName],
          text: widget.shareText,
          // iPad 分享面板需要锚点。
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('分享失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        child: Center(
          child: RepaintBoundary(
            key: _boundary,
            // 分享图固定用浅色主题，保证在聊天软件里清晰可读。
            child: Theme(data: AppTheme.light(), child: widget.card),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _share,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.ios_share),
        label: const Text('分享图片'),
      ),
    );
  }
}

/// 把 [boundaryKey] 对应的 RepaintBoundary 渲染为 PNG（3 倍像素密度，聊天软件里不糊）。
Future<Uint8List> capturePng(
  GlobalKey boundaryKey, {
  double pixelRatio = 3,
}) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// 分享卡片外框：品牌抬头 + 内容 + 来源 / 免责页脚。
class ShareCardFrame extends StatelessWidget {
  const ShareCardFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.footer,
  });

  final String title;
  final String subtitle;
  final List<Widget> body;
  final List<String> footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 360,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: scheme.onSurface, fontSize: 13, height: 1.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.terrain, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  '山晴 · 徒步天气',
                  style: TextStyle(fontSize: 12, color: scheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            ...body,
            const SizedBox(height: 12),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 8),
            for (final f in footer)
              Text(
                f,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
