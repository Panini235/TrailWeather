import 'dart:async';

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

/// 设备定位边界。抽象层避免 UI 直接依赖静态插件 API，并允许组件测试覆盖
/// “自动定位 + 再次定位”的真实状态流转。
abstract interface class LocationService {
  Future<LatLng> currentPosition();

  /// 打开与当前失败最相关的系统设置页。
  Future<bool> openSettings(LocationFailureKind kind);
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LatLng> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(
        LocationFailureKind.serviceDisabled,
        '系统定位服务未开启，请开启后重试。',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
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

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final point = LatLng(position.latitude, position.longitude);
      if (point.latitude < -90 ||
          point.latitude > 90 ||
          point.longitude < -180 ||
          point.longitude > 180) {
        throw const LocationFailure(
          LocationFailureKind.unavailable,
          '设备返回了无效坐标，请稍后重试。',
        );
      }
      return point;
    } on TimeoutException {
      throw const LocationFailure(
        LocationFailureKind.timeout,
        '定位超时，请到开阔处后重试。',
      );
    } on LocationFailure {
      rethrow;
    } catch (_) {
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
