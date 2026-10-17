import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// 定位失败类型，供 UI 给出可操作且不误导的提示。
enum LocationFailureKind {
  serviceDisabled,
  denied,
  deniedForever,
  timeout,
  unavailable,
}

class LocationFailure implements Exception {
  const LocationFailure(this.kind, this.message);

  final LocationFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

/// 一次定位结果。[isLastKnown] 为 true 表示新位置未取到，退回系统缓存的
/// 上次已知位置——它可能不是用户此刻所在位置，UI 必须如实标注。
class LocationFix {
  const LocationFix(this.point, {this.isLastKnown = false});

  final LatLng point;
  final bool isLastKnown;
}

/// 设备定位边界。抽象层避免 UI 直接依赖静态插件 API，并允许组件测试覆盖
/// “自动定位 + 再次定位”的真实状态流转。
abstract interface class LocationService {
  /// 获取位置。若系统有上次已知位置，会先通过 [onLastKnown] 立即回调，
  /// 便于地图先居中；随后返回新位置，新位置失败时退回上次已知位置。
  ///
  /// [requestPermission] 为 false 时只检查、不弹系统授权框：未授权直接以
  /// [LocationFailureKind.denied] 失败。用于打开页面时的自动定位，授权只在
  /// 用户主动点“定位”时请求。
  Future<LocationFix> currentPosition({
    void Function(LatLng)? onLastKnown,
    bool requestPermission = true,
  });

  /// 打开与当前失败最相关的系统设置页。
  Future<bool> openSettings(LocationFailureKind kind);
}

/// geolocator 静态 API 的薄封装，便于测试替换。
abstract interface class GeolocatorBackend {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<LatLng?> lastKnown();
  Future<LatLng> fresh();
}

/// 平台定位参数（纯函数，可测）。
///
/// Android 强制使用系统 LocationManager：国产 ROM 多数没有 Google Play 服务，
/// 默认的 FusedLocationProvider 会一直等到超时。精度取 medium：查天气只需
/// 百米级位置，high 在室内常拿不到 GPS 定位。
LocationSettings locationSettingsFor(
  TargetPlatform platform, {
  required bool isWeb,
}) {
  const accuracy = LocationAccuracy.medium;
  const timeLimit = Duration(seconds: 30);
  if (!isWeb && platform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: accuracy,
      timeLimit: timeLimit,
      forceLocationManager: true,
    );
  }
  return const LocationSettings(accuracy: accuracy, timeLimit: timeLimit);
}

class PluginGeolocatorBackend implements GeolocatorBackend {
  const PluginGeolocatorBackend();

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<LatLng?> lastKnown() async {
    // Web 端 geolocator 不支持上次已知位置。
    if (kIsWeb) return null;
    final position = await Geolocator.getLastKnownPosition(
      forceAndroidLocationManager: _isAndroid,
    );
    return position == null
        ? null
        : LatLng(position.latitude, position.longitude);
  }

  @override
  Future<LatLng> fresh() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: locationSettingsFor(
        defaultTargetPlatform,
        isWeb: kIsWeb,
      ),
    );
    return LatLng(position.latitude, position.longitude);
  }
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService({
    this.backend = const PluginGeolocatorBackend(),
  });

  final GeolocatorBackend backend;

  static bool _isValid(LatLng p) =>
      p.latitude >= -90 &&
      p.latitude <= 90 &&
      p.longitude >= -180 &&
      p.longitude <= 180;

  @override
  Future<LocationFix> currentPosition({
    void Function(LatLng)? onLastKnown,
    bool requestPermission = true,
  }) async {
    if (!await backend.isLocationServiceEnabled()) {
      throw const LocationFailure(
        LocationFailureKind.serviceDisabled,
        '系统定位服务未开启，请开启后重试。',
      );
    }

    var permission = await backend.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await backend.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure(
        LocationFailureKind.denied,
        '未获得定位权限。你仍可手动点选地图查询天气。',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        LocationFailureKind.deniedForever,
        '定位权限已被永久拒绝，请在系统设置中允许后重试。',
      );
    }

    LatLng? last;
    try {
      last = await backend.lastKnown().timeout(const Duration(seconds: 3));
      if (last != null && !_isValid(last)) last = null;
    } catch (_) {
      last = null; // 上次已知位置只是加速手段，失败不影响后续新定位。
    }
    if (last != null) onLastKnown?.call(last);

    try {
      final point = await backend.fresh();
      if (!_isValid(point)) {
        if (last != null) return LocationFix(last, isLastKnown: true);
        throw const LocationFailure(
          LocationFailureKind.unavailable,
          '设备返回了无效坐标，请稍后重试。',
        );
      }
      return LocationFix(point);
    } on LocationFailure {
      rethrow;
    } on TimeoutException {
      if (last != null) return LocationFix(last, isLastKnown: true);
      throw const LocationFailure(
        LocationFailureKind.timeout,
        '定位超时，请到开阔处后重试。',
      );
    } catch (_) {
      if (last != null) return LocationFix(last, isLastKnown: true);
      throw const LocationFailure(
        LocationFailureKind.unavailable,
        '暂时无法获取位置，请稍后重试。',
      );
    }
  }

  @override
  Future<bool> openSettings(LocationFailureKind kind) {
    if (kind == LocationFailureKind.serviceDisabled) {
      return Geolocator.openLocationSettings();
    }
    return Geolocator.openAppSettings();
  }
}
