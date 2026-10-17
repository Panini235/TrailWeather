import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/core/cache_store.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/weather_repository.dart';

import 'weather_repository_test.dart' show FakeProvider, node;

class WindowProvider extends FakeProvider {
  WindowProvider() : super(responses: {});
  bool offline = false;
  double temperature = 12;
  Set<int> missingHours = {};
  Completer<void>? gate;

  @override
  Future<List<WxPointForecast>> fetchPoints({
    required List<LatLng> points,
    required DateTime startUtc,
    required DateTime endUtc,
    CancelToken? cancelToken,
  }) async {
    if (offline) {
      callCount++;
      throw StateError('测试网络不可达');
    }
    final base = await super.fetchPoints(
      points: points,
      startUtc: startUtc,
      endUtc: endUtc,
    );
    await gate?.future;
    return [
      for (final point in base)
        WxPointForecast(
          lat: point.lat,
          lon: point.lon,
          provenance: point.provenance,
          hours: [
            for (
              var t = startUtc;
              t.isBefore(endUtc);
              t = t.add(const Duration(hours: 1))
            )
              if (!missingHours.contains(t.hour))
                WxHourValue(
                  validFromUtc: t,
                  values: {WxVar.temperature: temperature},
                ),
          ],
        ),
    ];
  }
}

Future<DateTime> ageCache(SharedPreferences prefs) async {
  final old = DateTime.now().toUtc().subtract(const Duration(hours: 7));
  for (final key in prefs.getKeys().where(
    (k) => k.startsWith('cache.weather.'),
  )) {
    final entry = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
    final payload = jsonDecode(entry['p'] as String) as Map<String, dynamic>;
    payload['fetchedAt'] = old.toIso8601String();
    for (final p in payload['points'] as List) {
      p['prov']['f'] = old.toIso8601String();
    }
    entry['p'] = jsonEncode(payload);
    entry['s'] = old.millisecondsSinceEpoch;
    entry['e'] = old.add(const Duration(minutes: 30)).millisecondsSinceEpoch;
    await prefs.setString(key, jsonEncode(entry));
  }
  return old;
}

void main() {
  late SharedPreferences prefs;
  late WindowProvider provider;
  late WeatherRepository repo;
  final start = DateTime.utc(2026, 10, 16, 23);
  final nodes = [node(30, 120)];
  Stream<WxSourceResult> read(
    DateTime from,
    DateTime until, {
    bool refresh = false,
  }) => repo.watchRouteWeather(
    providerId: 'fake:test',
    nodes: nodes,
    startUtc: from,
    endUtc: until,
    refresh: refresh,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    provider = WindowProvider();
    repo = WeatherRepository(cache: CacheStore(prefs), providers: [provider]);
  });

  test('冷启动后跨小时、跨午夜复用真实覆盖的 72 小时预报，不重复请求', () async {
    await read(start, start.add(const Duration(hours: 72))).last;
    repo = WeatherRepository(cache: CacheStore(prefs), providers: [provider]);
    provider.offline = true;
    for (final shift in [1, 24, 48, 71]) {
      final from = start.add(Duration(hours: shift));
      final states = await read(
        from,
        from.add(const Duration(hours: 1)),
      ).toList();
      expect(states, hasLength(1));
      expect(states.single.fromCache, isTrue);
      expect(states.single.partialCoverage, isFalse);
      expect(states.single.points.single.hourAt(from), isNotNull);
    }
    expect(provider.callCount, 1);
  });

  test('七小时旧缓存先显示，再成功刷新；刷新成功通过同一流交给页面', () async {
    final end = start.add(const Duration(hours: 24));
    await read(start, end).last;
    final old = await ageCache(prefs);
    provider.temperature = 22;
    final states = await read(start, end).toList();
    expect(states, hasLength(2));
    expect(states.first.refreshing, isTrue);
    expect(states.first.stale, isTrue);
    expect(states.first.fetchedAtUtc, old);
    expect(states.last.fromCache, isFalse);
    expect(states.last.refreshFailed, isFalse);
    expect(states.last.points.single.hours.first.values[WxVar.temperature], 22);
    expect(provider.callCount, 2);
  });

  test('后台更新失败是可见状态，缓存获取时间不变，没有未处理异步错误', () async {
    final end = start.add(const Duration(hours: 24));
    await read(start, end).last;
    final old = await ageCache(prefs);
    provider.offline = true;
    final states = await read(start, end).toList();
    expect(states, hasLength(2));
    expect(states.last.refreshing, isFalse);
    expect(states.last.refreshFailed, isTrue);
    expect(states.last.stale, isTrue);
    expect(states.last.fetchedAtUtc, old);
    expect(states.last.points.single.hours.first.values[WxVar.temperature], 12);
    expect(provider.callCount, 2);
  });

  test('部分覆盖断网时仍可读，小时缺口不能用前后时次冒充', () async {
    provider.missingHours = {1};
    await read(start, start.add(const Duration(hours: 6))).last;
    provider.offline = true;
    final from = start.add(const Duration(hours: 1)); // 次日 00:00
    final result = await read(from, from.add(const Duration(hours: 3))).last;
    expect(result.partialCoverage, isTrue);
    expect(result.refreshFailed, isTrue);
    expect(result.points.single.hourAt(from), isNotNull);
    expect(
      result.points.single.hourAt(from.add(const Duration(hours: 1))),
      isNull,
    );
  });

  test('缓存无重叠时断网报错，不把旧时段预报冒充新日期', () async {
    await read(start, start.add(const Duration(hours: 2))).last;
    provider.offline = true;
    final tomorrow = start.add(const Duration(days: 1));
    await expectLater(
      read(tomorrow, tomorrow.add(const Duration(hours: 1))).last,
      throwsStateError,
    );
  });

  test('同一查询并发刷新只发一次请求，成功后允许再次主动刷新', () async {
    provider.gate = Completer<void>();
    final end = start.add(const Duration(hours: 2));
    final first = read(start, end).last;
    final second = read(start, end).last;
    await Future<void>.delayed(Duration.zero);
    expect(provider.callCount, 1);
    provider.gate!.complete();
    await Future.wait([first, second]);
    await read(start, end, refresh: true).last;
    expect(provider.callCount, 2);
  });

  test('刷新空响应不得覆盖原有可用缓存', () async {
    final end = start.add(const Duration(hours: 1));
    await read(start, end).last;
    provider.missingHours = {23};
    final result = await read(start, end, refresh: true).last;
    expect(result.refreshFailed, isTrue);
    expect(result.points.single.hourAt(start), isNotNull);
    provider.offline = true;
    repo = WeatherRepository(cache: CacheStore(prefs), providers: [provider]);
    final restored = await read(start, end).last;
    expect(restored.points.single.hourAt(start), isNotNull);
    expect(provider.callCount, 2);
  });
}
