import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/weather/satellite_frames.dart';
import 'package:trailweather/data/weather/weather_field.dart';

/// 按请求里的坐标个数生成多点响应（与 Open-Meteo 多坐标响应结构一致）。
String fakeFieldResponse(Uri uri, {double? missingAt}) {
  final lats = uri.queryParameters['latitude']!.split(',');
  return jsonEncode([
    for (var i = 0; i < lats.length; i++)
      {
        'latitude': double.parse(lats[i]),
        'hourly': {
          'time': ['2026-10-17T07:00', '2026-10-17T08:00', '2026-10-17T09:00'],
          'precipitation': [i == missingAt ? null : i * 0.1, 0.0, 2.0],
          'cloud_cover': [100, 50, 0],
          'cloud_cover_low': [80, 40, 0],
          'cloud_cover_mid': [10, 10, 10],
          'cloud_cover_high': [0, 0, 0],
        },
      },
  ]);
}

void main() {
  final now = DateTime.utc(2026, 10, 17, 7, 20);

  group('gridShape', () {
    test('竖屏多行、横屏多列，总数不超过上限', () {
      final (c1, r1) = gridShape(0.5);
      expect(r1, greaterThan(c1));
      expect(c1 * r1, lessThanOrEqualTo(120));
      final (c2, r2) = gridShape(2);
      expect(c2, greaterThan(r2));
      expect(c2 * r2, lessThanOrEqualTo(120));
    });
  });

  group('FieldBounds', () {
    test('扩展比例与最小跨度', () {
      const b = FieldBounds(south: 40, west: 116, north: 40.01, east: 116.01);
      final e = b.expanded(0.15);
      expect(e.latSpan, closeTo(0.45, 1e-9));
      expect(e.lonSpan, closeTo(0.6, 1e-9));
      expect(e.contains(b), isTrue);
    });
  });

  group('WeatherFieldService', () {
    test('请求：多坐标、5 个变量、48 小时；行按墨卡托等距由北向南', () async {
      Uri? seen;
      final s = WeatherFieldService(
        now: () => now,
        fetcher: (uri, {headers, cancelToken}) async {
          seen = uri;
          return fakeFieldResponse(uri);
        },
      );
      const view = FieldBounds(south: 39, west: 115, north: 41, east: 117);
      final g = await s.fetch(view, aspect: 0.5);
      expect(seen!.host, 'api.open-meteo.com');
      expect(seen!.queryParameters['forecast_hours'], '48');
      expect(seen!.queryParameters['hourly'], contains('cloud_cover_low'));
      expect(
        seen!.queryParameters['latitude']!.split(',').length,
        g.cols * g.rows,
      );
      expect(g.lats.first, greaterThan(g.lats.last));
      // 墨卡托等距：靠北的行间距（纬度）比靠南的小
      expect(
        g.lats[0] - g.lats[1],
        lessThan(g.lats[g.rows - 2] - g.lats[g.rows - 1]),
      );
      expect(g.timesUtc.first, DateTime.utc(2026, 10, 17, 7));
      expect(g.at(FieldVar.precip, 0, 0, 1), closeTo(0.1, 1e-6));
      expect(g.at(FieldVar.cloudLow, 1, 0, 0), 40);
      expect(g.timeIndexOf(now), 0);
      expect(g.timeIndexOf(DateTime.utc(2026, 10, 17, 9, 59)), 2);
      expect(g.timeIndexOf(DateTime.utc(2026, 10, 17, 10)), isNull);
      expect(g.spacingKm, greaterThan(10));
    });

    test('缺失值为 null（不当 0）', () {
      final g = WeatherFieldService.parse(
        fakeFieldResponse(
          Uri.parse('https://x/?latitude=1,2,3,4'),
          missingAt: 2,
        ),
        bounds: const FieldBounds(south: 0, west: 0, north: 1, east: 1),
        cols: 2,
        rows: 2,
        lats: const [1, 0],
        lons: const [0, 1],
        fetchedAtUtc: now,
      );
      expect(g.at(FieldVar.precip, 0, 1, 0), isNull);
      expect(g.at(FieldVar.precip, 0, 1, 1), closeTo(0.3, 1e-6));
    });

    test('视野在已取范围内且未过期：复用，不再请求；缩小很多则重新请求', () async {
      var calls = 0;
      var t = now;
      final s = WeatherFieldService(
        now: () => t,
        fetcher: (uri, {headers, cancelToken}) async {
          calls++;
          return fakeFieldResponse(uri);
        },
      );
      const view = FieldBounds(south: 39, west: 115, north: 41, east: 117);
      await s.fetch(view, aspect: 0.5);
      await s.fetch(
        const FieldBounds(south: 39.5, west: 115.5, north: 40.5, east: 116.5),
        aspect: 0.5,
      );
      expect(calls, 1);
      await s.fetch(
        const FieldBounds(south: 40, west: 116, north: 40.2, east: 116.2),
        aspect: 0.5,
      );
      expect(calls, 2);
      t = t.add(const Duration(minutes: 31));
      await s.fetch(
        const FieldBounds(south: 40, west: 116, north: 40.2, east: 116.2),
        aspect: 0.5,
      );
      expect(calls, 3);
    });

    test('格点数与请求不符：抛错，不画错位的场', () {
      expect(
        () => WeatherFieldService.parse(
          '[{"hourly":{"time":[]}}]',
          bounds: const FieldBounds(south: 0, west: 0, north: 1, east: 1),
          cols: 2,
          rows: 2,
          lats: const [1, 0],
          lons: const [0, 1],
          fetchedAtUtc: now,
        ),
        throwsFormatException,
      );
    });
  });

  group('SatelliteFrameService', () {
    test('只返回真实存在的时次；每 30 分钟一帧，升序', () async {
      final probed = <Uri>[];
      final s = SatelliteFrameService(
        now: () => DateTime.utc(2026, 10, 17, 7, 5),
        probe: (uri) async {
          probed.add(uri);
          // 06:50 尚未发布，06:10 缺失，其余可用
          final p = uri.path;
          if (p.contains('T06:50') || p.contains('T06:10')) return 404;
          return 200;
        },
      );
      final frames = await s.recentFrames();
      expect(probed.first.path, contains('2026-10-17T06:50:00Z'));
      expect(probed.first.path, endsWith('/2/1/3.png'));
      expect(frames.last, DateTime.utc(2026, 10, 17, 6, 40));
      // 06:10 缺失：用 10 分钟内最近的可用时次（06:20）顶上，不出现缺失时次
      expect(frames, contains(DateTime.utc(2026, 10, 17, 6, 20)));
      expect(frames, isNot(contains(DateTime.utc(2026, 10, 17, 6, 10))));
      expect(frames.length, 7);
      expect(frames, orderedEquals([...frames]..sort()));
    });

    test('一张都没有：空列表', () async {
      final s = SatelliteFrameService(
        now: () => DateTime.utc(2026, 10, 17, 7),
        probe: (_) async => 0,
      );
      expect(await s.recentFrames(), isEmpty);
    });

    test('瓦片地址：时间为 UTC 秒级', () {
      expect(
        SatelliteFrameService.tileTemplate(DateTime.utc(2026, 10, 17, 6, 40)),
        contains('/default/2026-10-17T06:40:00Z/GoogleMapsCompatible_Level6/'),
      );
    });
  });
}
