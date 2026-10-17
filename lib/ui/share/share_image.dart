import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_links.dart';
import '../theme.dart';

/// 把一张“分享卡片”渲染成 PNG，交给系统分享面板（微信 / QQ / X / Threads 等）。
///
/// 卡片是专门为图片排版的组件（固定宽度、浅色背景、自带来源与免责声明），
/// 不是屏幕截图；预览页让用户先看到将要分享的内容。
/// 分享图的一种版式：名称、图标、卡片，以及文件名后缀。
class ShareVariant {
  const ShareVariant({
    required this.label,
    required this.icon,
    required this.card,
    this.fileSuffix = '',
  });

  final String label;
  final IconData icon;
  final Widget card;
  final String fileSuffix;
}

class SharePreviewPage extends StatefulWidget {
  const SharePreviewPage({
    super.key,
    required this.title,
    required this.card,
    required this.fileName,
    this.shareText,
    this.variants,
  });

  final String title;

  /// 单一卡片（没有 [variants] 时使用）。
  final Widget card;
  final String fileName;
  final String? shareText;

  /// 多种版式：预览页顶部可切换，分享当前选中的版式。
  final List<ShareVariant>? variants;

  @override
  State<SharePreviewPage> createState() => _SharePreviewPageState();
}

class _SharePreviewPageState extends State<SharePreviewPage> {
  final _boundary = GlobalKey();
  bool _busy = false;
  int _variant = 0;

  ShareVariant? get _current {
    final v = widget.variants;
    return v == null || v.isEmpty ? null : v[_variant.clamp(0, v.length - 1)];
  }

  String get _fileName {
    final suffix = _current?.fileSuffix ?? '';
    if (suffix.isEmpty) return widget.fileName;
    final dot = widget.fileName.lastIndexOf('.');
    return dot < 0
        ? '${widget.fileName}-$suffix'
        : '${widget.fileName.substring(0, dot)}-$suffix${widget.fileName.substring(dot)}';
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    try {
      final bytes = await capturePng(_boundary);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png')],
          fileNameOverrides: [_fileName],
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
        child: Column(
          children: [
            if (widget.variants case final variants? when variants.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SegmentedButton<int>(
                  segments: [
                    for (final (i, v) in variants.indexed)
                      ButtonSegment(
                        value: i,
                        icon: Icon(v.icon),
                        label: Text(v.label),
                      ),
                  ],
                  selected: {_variant},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _variant = s.first),
                ),
              ),
            // 横图比屏幕宽：预览时按屏宽缩小显示；RepaintBoundary 在缩放之内，
            // 导出的图片仍是卡片原始尺寸（640 宽）× pixelRatio。
            FittedBox(
              fit: BoxFit.scaleDown,
              child: RepaintBoundary(
                key: _boundary,
                // 分享图固定用浅色主题，保证在聊天软件里清晰可读。
                child: Theme(
                  data: AppTheme.light(),
                  child: _current?.card ?? widget.card,
                ),
              ),
            ),
          ],
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

/// 分享卡片外框：品牌抬头 → 标题 → 内容（分区留白）→ 来源 / 免责页脚 → 宣传语 + 下载二维码。
class ShareCardFrame extends StatelessWidget {
  const ShareCardFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.footer,
    this.width = 360,
  });

  final String title;
  final String subtitle;
  final List<Widget> body;
  final List<String> footer;

  /// 竖版 360；横图 640。
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: DefaultTextStyle(
        style: TextStyle(color: scheme.onSurface, fontSize: 13, height: 1.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.terrain, size: 16, color: scheme.primary),
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
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  for (final b in body) ...[const SizedBox(height: 14), b],
                  const SizedBox(height: 14),
                  for (final f in footer)
                    Text(
                      f,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            const SharePromoBar(),
          ],
        ),
      ),
    );
  }
}

/// 卡片底部宣传条：一句宣传语 + 下载二维码（地址见 [kDownloadUrl]）。
class SharePromoBar extends StatelessWidget {
  const SharePromoBar({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.primaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kShareSlogan,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '导入轨迹，按出发时间查看沿途天气\n扫码下载测试版',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            color: Colors.white,
            child: QrImageView(
              data: kDownloadUrl,
              size: 76,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              semanticsLabel: '下载二维码',
            ),
          ),
        ],
      ),
    );
  }
}
