import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/weather/layering.dart';
import 'package:trailweather/data/weather/risk_rules.dart';
import 'package:trailweather/data/weather/weather_models.dart';

WxHourValue _wx(DateTime t, Map<WxVar, double?> v) => WxHourValue(
  validFromUtc: t,
  values: {for (final x in WxVar.values) x: null, ...v},
);

/// 三个节点：起点、山顶（最冷）、终点。
List<NodeWeatherEntry> _route({
  required List<double?> apparent,
  List<double?>? temp,
  double? gust,
  double? prob,
  double? precip,
  double? uv,
  double? snowDepth,
  DateTime? start,
}) {
  final t0 = start ?? DateTime.utc(2026, 10, 18, 0);
  return [
    for (var i = 0; i < apparent.length; i++)
      NodeWeatherEntry(
        validUtc: t0.add(Duration(hours: i * 2)),
        elevationM: [300.0, 1800.0, 300.0][i % 3],
        weather: _wx(t0.add(Duration(hours: i * 2)), {
          WxVar.apparentTemp: apparent[i],
          WxVar.temperature: temp?[i] ?? apparent[i],
          WxVar.windGust: gust,
          WxVar.precipProb: prob,
          WxVar.precip: precip,
          WxVar.uvIndex: uv,
          WxVar.snowDepth: snowDepth,
        }),
      ),
  ];
}

void main() {
  group('planLayers', () {
    test('冷而有风：保暖排汗 + 薄羽绒（出发穿、行进收、停留穿）+ 防风', () {
      final plan = planLayers(
        entries: _route(
          apparent: [4, 2, 9],
          gust: 12,
          prob: 10,
          precip: 0,
          uv: 4,
        ),
        labels: ['起点', '山顶', '终点'],
      )!;
      expect(plan.feels[LayerScene.start], 4);
      expect(plan.feels[LayerScene.stop], 2);
      expect(plan.layer(LayerKind.base)!.name, '保暖排汗长袖'); // 行进 4° < 8
      final mid = plan.layer(LayerKind.mid)!;
      expect(mid.name, '薄羽绒或厚抓绒');
      expect(mid.wear[LayerScene.start], Wear.worn); // 出发 4° < 5
      expect(mid.wear[LayerScene.moving], Wear.packed);
      expect(mid.wear[LayerScene.stop], Wear.worn);
      expect(mid.reason, contains('山顶'));
      final shell = plan.layer(LayerKind.shell)!;
      expect(shell.name, '软壳或防风外套'); // 阵风 12 ≥ 10.8，无雨
      expect(shell.wear[LayerScene.stop], Wear.worn);
      final acc = plan.accessories.map((a) => a.item).toSet();
      expect(
        acc,
        containsAll([Accessory.sunscreen, Accessory.beanie, Accessory.gloves]),
      );
      expect(acc, isNot(contains(Accessory.sunglasses))); // uv 4 < 6
      expect(plan.notes, isEmpty);
    });

    test('下雨：防水硬壳优先于防风，配雨裤和防雨罩', () {
      final plan = planLayers(
        entries: _route(
          apparent: [14, 12, 15],
          gust: 12,
          prob: 80,
          precip: 1.5,
        ),
      )!;
      expect(plan.layer(LayerKind.shell)!.name, '防水硬壳');
      expect(plan.layer(LayerKind.shell)!.wear[LayerScene.start], Wear.worn);
      final acc = plan.accessories.map((a) => a.item).toSet();
      expect(acc, containsAll([Accessory.rainPants, Accessory.packCover]));
      expect(plan.layer(LayerKind.legs)!.name, '速干长裤');
    });

    test('炎热晴朗：短袖短裤，无保暖层与防护层，防晒三件套', () {
      final plan = planLayers(
        entries: _route(
          apparent: [26, 22, 30],
          gust: 3,
          prob: 0,
          precip: 0,
          uv: 9,
        ),
      )!;
      expect(plan.layer(LayerKind.base)!.name, '短袖速干');
      expect(plan.layer(LayerKind.mid), isNull);
      expect(plan.layer(LayerKind.shell), isNull);
      expect(plan.layer(LayerKind.legs)!.name, '速干短裤');
      final acc = plan.accessories.map((a) => a.item).toSet();
      expect(
        acc,
        containsAll([
          Accessory.sunscreen,
          Accessory.sunHat,
          Accessory.sunglasses,
        ]),
      );
    });

    test('严寒：厚羽绒行进也穿，厚手套与头巾', () {
      final plan = planLayers(
        entries: _route(
          apparent: [-12, -18, -10],
          gust: 8,
          prob: 0,
          precip: 0,
          uv: 2,
        ),
      )!;
      final mid = plan.layer(LayerKind.mid)!;
      expect(mid.name, '厚羽绒');
      expect(mid.wear[LayerScene.moving], Wear.worn);
      expect(plan.layer(LayerKind.base)!.name, '保暖排汗长袖');
      expect(plan.layer(LayerKind.legs)!.name, '软壳长裤');
      final acc = plan.accessories.map((a) => a.item).toSet();
      expect(acc, containsAll([Accessory.warmGloves, Accessory.buff]));
    });

    test('个人偏好平移 3 ℃：怕冷更厚、怕热可省；显示仍为原体感', () {
      final e = _route(apparent: [13, 12.5, 14], gust: 2, prob: 0, precip: 0);
      expect(planLayers(entries: e)!.layer(LayerKind.mid)!.name, '薄抓绒');
      final cold = planLayers(entries: e, coldSensitivity: -1)!;
      expect(cold.layer(LayerKind.mid)!.name, '抓绒衣');
      expect(cold.feels[LayerScene.stop], 12.5);

      final warm = _route(
        apparent: [16, 15.5, 17],
        gust: 2,
        prob: 0,
        precip: 0,
      );
      expect(planLayers(entries: warm)!.layer(LayerKind.mid)!.name, '薄抓绒');
      expect(
        planLayers(entries: warm, coldSensitivity: 1)!.layer(LayerKind.mid),
        isNull,
      );
    });

    test('积雪 + 紫外线 2：仍建议墨镜（雪面反光）', () {
      final plan = planLayers(
        entries: _route(
          apparent: [-2, -6, -1],
          gust: 4,
          prob: 0,
          precip: 0,
          uv: 2,
          snowDepth: 0.2,
        ),
      )!;
      final glasses = plan.accessories.firstWhere(
        (a) => a.item == Accessory.sunglasses,
      );
      expect(glasses.reason, contains('雪'));
    });

    test('日落后才到终点：头灯', () {
      final start = DateTime.utc(2026, 10, 18, 4);
      final plan = planLayers(
        entries: _route(apparent: [10, 8, 9], start: start),
        sunsetUtc: start.add(const Duration(hours: 3)),
      )!;
      expect(plan.accessories.map((a) => a.item), contains(Accessory.headlamp));
    });

    test('缺体感按气温并说明；缺阵风/降水/紫外线逐项说明，不默认够用', () {
      final plan = planLayers(
        entries: [
          for (var i = 0; i < 3; i++)
            NodeWeatherEntry(
              validUtc: DateTime.utc(2026, 10, 18, i),
              weather: _wx(DateTime.utc(2026, 10, 18, i), {
                WxVar.temperature: 6,
              }),
            ),
        ],
      )!;
      expect(plan.usedApparent, isFalse);
      expect(
        plan.notes.join(),
        allOf(contains('气温'), contains('阵风'), contains('降水'), contains('紫外线')),
      );
      expect(plan.layer(LayerKind.shell), isNull); // 没有风雨数据就不判断
    });

    test('完全没有温度：返回 null（信息不足）', () {
      final plan = planLayers(
        entries: [
          NodeWeatherEntry(validUtc: DateTime.utc(2026, 10, 18), weather: null),
        ],
      );
      expect(plan, isNull);
    });
  });
}
