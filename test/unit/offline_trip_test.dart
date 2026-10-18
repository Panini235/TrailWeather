import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/core/cache_store.dart';
import 'package:trailweather/data/offline/offline_repository.dart';
import 'package:trailweather/data/offline/offline_store.dart';
import 'package:trailweather/data/offline/offline_store_io.dart';
import 'package:trailweather/data/offline/offline_store_prefs.dart';
import 'package:trailweather/data/offline/offline_trip.dart';
import 'package:trailweather/data/weather/meteoblue_provider.dart';
import 'package:trailweather/data/weather/qweather_provider.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/weather_repository.dart';

import '../support/offline_fixtures.dart';

class FailingWriteStore implements OfflineTripStore {
  FailingWriteStore(this.inner);
  final OfflineTripStore inner;
  @override
  Future<List<String>> ids() => inner.ids();
  @override
  Future<String?> read(String id) => inner.read(id);
  @override
  Future<void> write(String id, String value) =>
      Future.error(const FileSystemException('模拟磁盘空间不足'));
  @override
  Future<void> delete(String id) => inner.delete(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late SharedPreferences prefs;
  late OfflineWeatherFixture source;
  late WeatherRepository weather;
  late OfflineTripRepository repo;
  late FileOfflineTripStore store;
  DateTime now() => DateTime.utc(2026, 10, 16, 22);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shanqing-offline-test-');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    source = OfflineWeatherFixture()..extraHours = 1;
    weather = WeatherRepository(
      cache: CacheStore(prefs, maxEntriesPerNamespace: 1),
      providers: [source],
    );
    store = FileOfflineTripStore(directory: dir);
    repo = OfflineTripRepository(
      store: store,
      weather: () => weather,
      now: now,
    );
  });
  tearDown(() async => dir.delete(recursive: true));

  Future<OfflineTrip> download({
    int hours = 72,
    bool reversed = false,
    String? replacingId,
  }) => repo.download(
    plan: offlinePlan(hours: hours, reversed: reversed),
    providerId: source.caps.providerId,
    replacingId: replacingId,
  );

  for (final hours in [24, 48, 72]) {
    test('$hours 小时包：磁盘冷启动、跨午夜、清缓存与 LRU 后仍可读取，禁止网络', () async {
      final trip = await download(hours: hours);
      final cache = CacheStore(prefs, maxEntriesPerNamespace: 1);
      for (var i = 0; i < 5; i++) {
        await cache.write(
          CacheNs.weather,
          'test-$i',
          '{}',
          const Duration(minutes: 1),
        );
      }
      await cache.clearAll();
      source.fail = true;
      final restarted = OfflineTripRepository(
        store: FileOfflineTripStore(directory: dir),
        weather: () => throw StateError('离线读取绝不能访问天气仓库'),
        now: now,
      );
      final restored = (await restarted.load(trip.id))!;
      for (final h in [0, 1, hours ~/ 2, hours - 1]) {
        for (var n = 0; n < restored.plan.nodes.length; n++) {
          final value = restored.hourFor(
            n,
            trip.plan.startUtc.add(Duration(hours: h)),
          )!;
          expect(value.values[WxVar.temperature], 12);
          expect(value.values[WxVar.precip], 0);
          expect(value.values[WxVar.precipProb], isNull);
        }
      }
      expect(restored.hourFor(0, trip.plan.endUtc), isNull);
      expect(restored.coverage.complete, isTrue);
      expect(
        restored.coverage.coreVariables,
        hours * restored.plan.nodes.length,
      );
      expect(source.calls, 1);
      expect((await restarted.list()).single.id, trip.id);
    });
  }

  test('旧包缺最后一条累计记录：最后一小时保留气温，核心指标覆盖不足', () async {
    source.extraHours = 0;
    final trip = await download(hours: 24);
    final wx = trip.hourFor(
      0,
      trip.plan.endUtc.subtract(const Duration(hours: 1)),
    )!;
    expect(wx.values[WxVar.temperature], 12);
    expect(wx.values[WxVar.precip], isNull);
    // complete 统计时次，核心变量覆盖单独统计，不能把有气温等同于降水齐全。
    expect(trip.coverage.complete, isTrue);
    expect(trip.coverage.coreVariables, 23 * trip.plan.nodes.length);
  });

  test('反向线路、营地、停留、配速、预计到达与完整溯源均原样保存', () async {
    source.extraHours = 12;
    final trip = await download(reversed: true);
    final restored = (await repo.load(trip.id))!;
    expect(restored.plan.toJson(), trip.plan.toJson());
    expect(restored.plan.reversed, isTrue);
    expect(restored.plan.route.waypoints.single.stopMinutes, 60);
    expect(restored.bundle.nodeQueryIndex, trip.bundle.nodeQueryIndex);
    final original = trip.pointFor(0)!;
    final point = restored.pointFor(0)!;
    expect(point.provenance.toDisplayMap(), original.provenance.toDisplayMap());
    expect(point.provenance.traceNote, original.provenance.traceNote);
    expect(point.provenance.requestLat, restored.plan.nodes.first.pos.latitude);
    expect(point.dailySunsetsUtc, original.dailySunsetsUtc);
    expect(point.hours, hasLength(84));
    expect(point.hours.first.symbols, {'wmo_code': '2'});
    expect(
      restored.needsUpdate(restored.oldestFetchedAtUtc.add(restored.freshFor)),
      isTrue,
    );
    expect(restored.windowEnded(restored.plan.endUtc), isTrue);
  });

  test('缺时次和缺查询点可保存但必须显示部分覆盖，不能取其他点补位', () async {
    source.missingHours = {0};
    source.omitLastPoint = true;
    final trip = await download(hours: 24);
    expect(trip.coverage.complete, isFalse);
    expect(trip.coverage.missing, 26); // 2 点各缺 1 小时，末点缺 24 小时
    expect(
      trip.hourFor(0, trip.plan.startUtc.add(const Duration(hours: 1))),
      isNull,
    );
    expect(trip.pointFor(trip.plan.nodes.length - 1), isNull);
  });

  test('只有空值不能标记下载成功，也不能创建假离线包', () async {
    source.noValues = true;
    await expectLater(download(), throwsStateError);
    expect(await store.ids(), isEmpty);
  });

  test('刷新失败保留原文件，再次重试成功替换，获取时间不伪造', () async {
    final first = await download();
    final before = await store.read(first.id);
    source.fail = true;
    await expectLater(download(replacingId: first.id), throwsStateError);
    expect(await store.read(first.id), before);
    source.fail = false;
    source.temperature = 20;
    source.fetched = source.fetched.add(const Duration(minutes: 10));
    await download(replacingId: first.id);
    final after = (await repo.load(first.id))!;
    expect(
      after.hourFor(0, after.plan.startUtc)!.values[WxVar.temperature],
      20,
    );
    expect(after.pointFor(0)!.provenance.fetchedAtUtc, source.fetched);
    expect(
      after.oldestFetchedAtUtc.isAfter(after.bundle.result.fetchedAtUtc),
      isFalse,
    );
    expect(await store.ids(), [first.id]);
    expect(
      await dir.list().where((e) => e.path.endsWith('.tmp')).isEmpty,
      isTrue,
    );
  });

  test('响应减少或存储失败时不覆盖原包', () async {
    final first = await download();
    final before = await store.read(first.id);
    source.omitLastPoint = true;
    await expectLater(download(replacingId: first.id), throwsStateError);
    expect(await store.read(first.id), before);
    source.omitLastPoint = false;
    final failing = OfflineTripRepository(
      store: FailingWriteStore(store),
      weather: () => weather,
      now: now,
    );
    await expectLater(
      failing.download(
        plan: first.plan,
        providerId: source.caps.providerId,
        replacingId: first.id,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await store.read(first.id), before);
  });

  test('坐标响应错位拒绝保存', () async {
    source.wrongCoordinates = true;
    await expectLater(download(), throwsFormatException);
    expect(await store.ids(), isEmpty);
  });

  test('完整性损坏独立显示，不遮住其他健康包；可删除损坏包', () async {
    final first = await download();
    final second = await download();
    final envelope =
        jsonDecode((await store.read(first.id))!) as Map<String, dynamic>;
    envelope['payload'] = (envelope['payload'] as String).replaceFirst(
      '离线测试线路',
      '损坏后的线路',
    );
    await store.write(first.id, jsonEncode(envelope));
    await expectLater(repo.load(first.id), throwsFormatException);
    final entries = await repo.list();
    expect(entries.where((e) => e.error != null).single.id, first.id);
    expect(entries.where((e) => e.trip != null).single.id, second.id);
    await repo.delete(first.id);
    expect((await repo.list()).single.id, second.id);
  });

  test('拒绝路径穿越 ID；残留临时文件不算下载完成', () async {
    await expectLater(store.read('../escape'), throwsFormatException);
    await File('${dir.path}/interrupted.tmp').writeAsString('partial');
    expect(await store.ids(), isEmpty);
  });

  test('Web 独立持久键经过新实例恢复，清普通缓存不删除', () async {
    final webStore = PreferencesOfflineTripStore(prefs);
    final webRepo = OfflineTripRepository(
      store: webStore,
      weather: () => weather,
      now: now,
    );
    final trip = await webRepo.download(
      plan: offlinePlan(),
      providerId: source.caps.providerId,
    );
    await CacheStore(prefs).clearAll();
    final restored = OfflineTripRepository(
      store: PreferencesOfflineTripStore(prefs),
      weather: () => throw StateError('forbidden'),
      now: now,
    );
    expect((await restored.load(trip.id))!.coverage.complete, isTrue);
  });

  test('计费单点源与尚未复核离线条款的来源不进入批量下载', () {
    expect(
      OfflineTripRepository.supportsSource(MeteoblueProvider(apiKey: '')),
      isFalse,
    );
    expect(
      OfflineTripRepository.supportsSource(
        QWeatherProvider(apiHost: '', apiKey: ''),
      ),
      isFalse,
    );
  });
}
