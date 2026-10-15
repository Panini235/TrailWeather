import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/photos/photo_picker.dart';
import '../../data/photos/route_photos.dart';
import '../strings.dart';
import '../widgets/common.dart';

/// 节点详情中的图片区：查看附近图片、从相册/相机添加。
class NodePhotosSection extends ConsumerStatefulWidget {
  const NodePhotosSection({
    super.key,
    required this.routeId,
    required this.pos,
  });

  final String routeId;
  final LatLng pos;

  @override
  ConsumerState<NodePhotosSection> createState() => _NodePhotosSectionState();
}

class _NodePhotosSectionState extends ConsumerState<NodePhotosSection> {
  bool _busy = false;

  Future<void> _add(PhotoPickSource source) async {
    setState(() => _busy = true);
    try {
      final picked = await ref.read(photoPickerProvider).pick(source);
      if (picked == null) return;
      await ref
          .read(routePhotosProvider.notifier)
          .add(
            routeId: widget.routeId,
            pos: widget.pos,
            bytes: picked.bytes,
            extension: picked.extension,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.photoAddFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = ref.watch(photoStoreProvider).supported;
    final photos = photosNear(
      ref.watch(routePhotosProvider),
      widget.routeId,
      widget.pos,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(S.nodePhotos, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (supported && _busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (supported) ...[
              TextButton.icon(
                onPressed: () => _add(PhotoPickSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text(S.photoFromGallery),
              ),
              if (!kIsWeb)
                TextButton.icon(
                  onPressed: () => _add(PhotoPickSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text(S.photoFromCamera),
                ),
            ],
          ],
        ),
        if (!supported)
          const GranularityNotice(text: S.photosUnsupported)
        else if (photos.isEmpty)
          Text(
            S.noNodePhotos,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => showRoutePhotoViewer(context, photos[i]),
                child: RoutePhotoImage(photo: photos[i], width: 84, height: 84),
              ),
            ),
          ),
        const SizedBox(height: 2),
        Text(
          S.photosLocalOnly,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 从本地存储读取并显示图片；文件丢失时如实显示占位。
class RoutePhotoImage extends ConsumerStatefulWidget {
  const RoutePhotoImage({
    super.key,
    required this.photo,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final RoutePhoto photo;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  ConsumerState<RoutePhotoImage> createState() => _RoutePhotoImageState();
}

class _RoutePhotoImageState extends ConsumerState<RoutePhotoImage> {
  late Future<Uint8List?> _bytes = _load();

  Future<Uint8List?> _load() =>
      ref.read(photoStoreProvider).load(widget.photo.storageKey);

  @override
  void didUpdateWidget(RoutePhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.storageKey != widget.photo.storageKey) {
      _bytes = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: FutureBuilder<Uint8List?>(
          future: _bytes,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const ColoredBox(color: Colors.black12);
            }
            final bytes = snap.data;
            if (bytes == null) {
              return const ColoredBox(
                color: Colors.black12,
                child: Center(
                  child: Tooltip(
                    message: S.photoMissing,
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              );
            }
            return Image.memory(
              bytes,
              fit: widget.fit,
              errorBuilder: (_, _, _) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
            );
          },
        ),
      ),
    );
  }
}

Future<void> showRoutePhotoViewer(BuildContext context, RoutePhoto photo) =>
    showDialog<void>(
      context: context,
      builder: (_) => _RoutePhotoDialog(photo: photo),
    );

class _RoutePhotoDialog extends ConsumerStatefulWidget {
  const _RoutePhotoDialog({required this.photo});

  final RoutePhoto photo;

  @override
  ConsumerState<_RoutePhotoDialog> createState() => _RoutePhotoDialogState();
}

class _RoutePhotoDialogState extends ConsumerState<_RoutePhotoDialog> {
  late final _caption = TextEditingController(text: widget.photo.caption);

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.photo.createdAtUtc.toLocal();
    final notifier = ref.read(routePhotosProvider.notifier);
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RoutePhotoImage(photo: widget.photo, fit: BoxFit.contain),
            const SizedBox(height: 8),
            Text(
              '${S.photoAddedAt} ${t.year}-${t.month.toString().padLeft(2, '0')}-'
              '${t.day.toString().padLeft(2, '0')} '
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
              ' · WGS-84 ${widget.photo.lat.toStringAsFixed(5)}, '
              '${widget.photo.lon.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _caption,
              decoration: const InputDecoration(
                labelText: S.photoCaption,
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await notifier.remove(widget.photo);
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text(S.photoDelete),
        ),
        FilledButton(
          onPressed: () async {
            await notifier.updateCaption(widget.photo.id, _caption.text.trim());
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text(S.ok),
        ),
      ],
    );
  }
}

/// 地图上的图片标记。
class PhotoMapMarker extends StatelessWidget {
  const PhotoMapMarker({super.key});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiary,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)],
    ),
    child: const Icon(Icons.photo_camera, size: 13, color: Colors.white),
  );
}
