import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/weather/typhoon.dart';

/// 2026-10-17 实测 JMA 响应（台风 Champi，test/fixtures/jma）。
String _fx(String name) => File('test/fixtures/jma/$name').readAsStringSync();

void main() {
  test('解析实况：编号、名称、等级、气压、风速、移向与风区', () {
    final t = TyphoonService.parse(
      id: 'TC2636',
      forecastJson: _fx('TC2636_forecast.json'),
      specificationsJson: _fx('TC2636_specifications.json'),
    );
    expect(t.number, '2630');
    expect(t.nameEn, 'Champi');
    expect(t.title, 'Champi（2630）');
    expect(t.category, 'TY');
    expect(t.categoryLabel, '台风');
    expect(t.intensityLabel, '强');
    expect(t.issueUtc, DateTime.utc(2026, 10, 17, 6, 45));
    expect(t.center, const LatLng(12.5, 147.3));
    expect(t.pressureHpa, 960);
    expect(t.maxWindMs, 40); // 10 分钟平均
    expect(t.gustMs, 60);
    expect(t.course, '西');
    expect(t.speedKmh, 25);
    expect(t.track.length, greaterThan(10));
    expect(t.track.last, const LatLng(12.5, 147.3));
    expect(t.galeRadiusM, 388920);
    expect(t.stormRadiusM, 111120);
  });

  test('路径预报：12–120 小时，概率圆随时效变大，强度来自对应时次', () {
    final t = TyphoonService.parse(
      id: 'TC2636',
      forecastJson: _fx('TC2636_forecast.json'),
      specificationsJson: _fx('TC2636_specifications.json'),
    );
    expect([for (final f in t.forecasts) f.hours], [12, 24, 48, 72, 96, 120]);
    expect(t.forecasts.first.validUtc, DateTime.utc(2026, 10, 17, 18));
    expect(t.forecasts.first.probabilityRadiusM, 46300);
    expect(
      t.forecasts.last.probabilityRadiusM,
      greaterThan(t.forecasts.first.probabilityRadiusM!),
    );
    expect(t.forecasts.first.pressureHpa, 955);
    expect(t.forecasts[3].maxWindMs, 50);
    expect(t.allPoints.length, t.track.length + 1 + t.forecasts.length);
  });

  test('active()：按列表逐个取预报与实况', () async {
    final seen = <String>[];
    final s = TyphoonService(
      fetcher: (uri, {headers, cancelToken}) async {
        seen.add(uri.path);
        final name = uri.path.endsWith('targetTc.json')
            ? 'targetTc.json'
            : 'TC2636_${uri.pathSegments.last}';
        return _fx(name);
      },
    );
    final list = await s.active();
    expect(list.single.id, 'TC2636');
    expect(seen.first, '/bosai/typhoon/data/targetTc.json');
    expect(seen, contains('/bosai/typhoon/data/TC2636/forecast.json'));
  });

  test('没有活跃台风：空列表', () async {
    final s = TyphoonService(
      fetcher: (uri, {headers, cancelToken}) async => '[]',
    );
    expect(await s.active(), isEmpty);
  });

  test('移向：日文十六方位转中文', () {
    expect(typhoonCourseZh('西北西'), '西偏北');
    expect(typhoonCourseZh('北東'), '东北');
    expect(typhoonCourseZh('ほとんど停滞'), '几乎停滞');
    expect(typhoonCourseZh(null), isNull);
  });
}
