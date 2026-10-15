import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../settings/settings_repository.dart';
import 'photo_picker.dart';
import 'photo_store.dart';

/// 附着在线路某个位置上的图片。按坐标锚定（不按节点序号）：采样间距或
/// 行走方向改变后节点会重新计算，坐标锚点保持不变。
class RoutePhoto {
  const RoutePhoto({
    required this.id,
    required this.routeId,
    required this.lat,
    required this.lon,
    required this.storageKey,
    required this.createdAtUtc,
    this.caption = '',
  });

  final String id;
  final String routeId;
  final double lat;
  final double lon;
  final String storageKey;
  final DateTime createdAtUtc;
  final String caption;

  LatLng get pos => LatLng(lat, lon);

  RoutePhoto copyWith({String? caption}) => RoutePhoto(
    id: id,
    routeId: routeId,
    lat: lat,
    lon: lon,
    storageKey: storageKey,
    createdAtUtc: createdAtUtc,
    caption: caption ?? this.caption,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'routeId': routeId,
    'lat': lat,
    'lon': lon,
    'storageKey': storageKey,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'caption': caption,
  };

  static RoutePhoto fromJson(Map<String, dynamic> m) => RoutePhoto(
    id: m['id'] as String,
    routeId: m['routeId'] as String,
    lat: (m['lat'] as num).toDouble(),
    lon: (m['lon'] as num).toDouble(),
    storageKey: m['storageKey'] as String,
    createdAtUtc: DateTime.parse(m['createdAtUtc'] as String).toUtc(),
    caption: m['caption'] as String? ?? '',
  );
}

/// 节点详情中视为“在此节点”的最大距离。
const nodePhotoRadiusM = 60.0;

/// 某线路在 [pos] 附近（[radiusM] 内）的图片，按添加时间排序。
List<RoutePhoto> photosNear(
  List<RoutePhoto> all,
  String routeId,
  LatLng pos, {
  double radiusM = nodePhotoRadiusM,
}) =>
    all
        .where(
          (p) => p.routeId == routeId && Geo.distanceM(p.pos, pos) <= radiusM,
        )
        .toList()
      ..sort((a, b) => a.createdAtUtc.compareTo(b.createdAtUtc));

class RoutePhotosNotifier extends Notifier<List<RoutePhoto>> {
  static const _key = 'route_photos.v1';

  @override
  List<RoutePhoto> build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          RoutePhoto.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist() => ref
      .read(prefsProvider)
      .setString(_key, jsonEncode([for (final p in state) p.toJson()]));

  Future<RoutePhoto> add({
    required String routeId,
    required LatLng pos,
    required Uint8List bytes,
    required String extension,
    String caption = '',
  }) async {
    final now = DateTime.now().toUtc();
    final id = 'ph_${now.microsecondsSinceEpoch}';
    final key = await ref.read(photoStoreProvider).save(id, bytes, extension);
    final photo = RoutePhoto(
      id: id,
      routeId: routeId,
      lat: pos.latitude,
      lon: pos.longitude,
      storageKey: key,
      createdAtUtc: now,
      caption: caption,
    );
    state = [...state, photo];
    await _persist();
    return photo;
  }

  Future<void> updateCaption(String id, String caption) async {
    state = [
      for (final p in state) p.id == id ? p.copyWith(caption: caption) : p,
    ];
    await _persist();
  }

  Future<void> remove(RoutePhoto photo) async {
    await ref.read(photoStoreProvider).delete(photo.storageKey);
    state = state.where((p) => p.id != photo.id).toList();
    await _persist();
  }
}

final photoStoreProvider = Provider<PhotoStore>((ref) => createPhotoStore());

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => const ImagePickerPhotoPicker(),
);

final routePhotosProvider =
    NotifierProvider<RoutePhotosNotifier, List<RoutePhoto>>(
      RoutePhotosNotifier.new,
    );
