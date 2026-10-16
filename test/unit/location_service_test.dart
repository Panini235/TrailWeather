import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/location/location_service.dart';

class _FakeBackend implements GeolocatorBackend {
  _FakeBackend({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    this.last,
    this.lastError,
    this.freshResult,
    this.freshError,
  });

  final bool serviceEnabled;
  final LocationPermission permission;
  final LatLng? last;
  final Object? lastError;
  final LatLng? freshResult;
  final Object? freshError;
  final calls = <String>[];

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    calls.add('request');
    return permission;
  }

  @override
  Future<LatLng?> lastKnown() async {
    calls.add('last');
    if (lastError != null) throw lastError!;
    return last;
  }

  @override
  Future<LatLng> fresh() async {
    calls.add('fresh');
    if (freshError != null) throw freshError!;
    return freshResult!;
  }
}

void main() {
  const lastPoint = LatLng(30.1, 120.1);
  const freshPoint = LatLng(30.2, 120.2);

  group('GeolocatorLocationService 回退顺序', () {
    test('先回调上次已知位置，再返回新位置', () async {
      final backend = _FakeBackend(last: lastPoint, freshResult: freshPoint);
      final early = <LatLng>[];
      final fix = await GeolocatorLocationService(backend: backend)
          .currentPosition(onLastKnown: early.add);
      expect(backend.calls, ['last', 'fresh']);
      expect(early, [lastPoint]);
      expect(fix.point, freshPoint);
      expect(fix.isLastKnown, isFalse);
    });

    test('新位置超时 → 退回上次已知位置并标注', () async {
      final backend = _FakeBackend(
        last: lastPoint,
        freshError: TimeoutException('t'),
      );
      final fix = await GeolocatorLocationService(backend: backend)
          .currentPosition();
      expect(fix.point, lastPoint);
      expect(fix.isLastKnown, isTrue);
    });

    test('无上次已知位置且超时 → timeout 失败', () async {
      final backend = _FakeBackend(freshError: TimeoutException('t'));
      await expectLater(
        GeolocatorLocationService(backend: backend).currentPosition(),
        throwsA(
          isA<LocationFailure>().having(
            (f) => f.kind,
            'kind',
            LocationFailureKind.timeout,
          ),
        ),
      );
    });

    test('上次已知位置读取失败不影响新定位', () async {
      final backend = _FakeBackend(
        lastError: Exception('unsupported'),
        freshResult: freshPoint,
      );
      final early = <LatLng>[];
      final fix = await GeolocatorLocationService(backend: backend)
          .currentPosition(onLastKnown: early.add);
      expect(early, isEmpty);
      expect(fix.point, freshPoint);
    });

    test('无效的上次已知坐标被忽略，新定位其他错误 → unavailable', () async {
      final backend = _FakeBackend(
        last: const LatLng(91, 0),
        freshError: Exception('boom'),
      );
      await expectLater(
        GeolocatorLocationService(backend: backend).currentPosition(),
        throwsA(
          isA<LocationFailure>().having(
            (f) => f.kind,
            'kind',
            LocationFailureKind.unavailable,
          ),
        ),
      );
    });

    test('权限与服务检查在取位置之前', () async {
      final off = _FakeBackend(serviceEnabled: false, last: lastPoint);
      await expectLater(
        GeolocatorLocationService(backend: off).currentPosition(),
        throwsA(
          isA<LocationFailure>().having(
            (f) => f.kind,
            'kind',
            LocationFailureKind.serviceDisabled,
          ),
        ),
      );
      expect(off.calls, isEmpty);

      final denied = _FakeBackend(
        permission: LocationPermission.deniedForever,
        last: lastPoint,
      );
      await expectLater(
        GeolocatorLocationService(backend: denied).currentPosition(),
        throwsA(
          isA<LocationFailure>().having(
            (f) => f.kind,
            'kind',
            LocationFailureKind.deniedForever,
          ),
        ),
      );
      expect(denied.calls, isEmpty);
    });

    test('只检查不请求：未授权时不弹授权框、不读取位置', () async {
      final backend = _FakeBackend(
        permission: LocationPermission.denied,
        last: lastPoint,
      );
      await expectLater(
        GeolocatorLocationService(backend: backend)
            .currentPosition(requestPermission: false),
        throwsA(
          isA<LocationFailure>().having(
            (f) => f.kind,
            'kind',
            LocationFailureKind.denied,
          ),
        ),
      );
      expect(backend.calls, isEmpty);

      await expectLater(
        GeolocatorLocationService(backend: backend).currentPosition(),
        throwsA(isA<LocationFailure>()),
      );
      expect(backend.calls, ['request']);
    });
  });

  group('locationSettingsFor', () {
    test('Android 强制 LocationManager、medium 精度', () {
      final s = locationSettingsFor(TargetPlatform.android, isWeb: false);
      expect(s, isA<AndroidSettings>());
      expect((s as AndroidSettings).forceLocationManager, isTrue);
      expect(s.accuracy, LocationAccuracy.medium);
      expect(s.timeLimit, const Duration(seconds: 30));
    });

    test('iOS 与 Web 使用通用设置', () {
      final ios = locationSettingsFor(TargetPlatform.iOS, isWeb: false);
      expect(ios, isNot(isA<AndroidSettings>()));
      expect(ios.accuracy, LocationAccuracy.medium);
      final web = locationSettingsFor(TargetPlatform.android, isWeb: true);
      expect(web, isNot(isA<AndroidSettings>()));
    });
  });
}
