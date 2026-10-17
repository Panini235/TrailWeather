import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/weather/risk_rules.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/wx_importance.dart';

WxHourValue _wx(Map<WxVar, double?> v) => WxHourValue(
  validFromUtc: DateTime.utc(2026, 10, 18, 4),
  values: {for (final x in WxVar.values) x: null, ...v},
);

void main() {
  test('每个变量都有层级；决策层恰好是 6 个关键变量', () {
    final decide = WxVar.values
        .where((v) => tierOf(v) == WxTier.decide)
        .toSet();
    expect(decide, {
      WxVar.temperature,
      WxVar.apparentTemp,
      WxVar.precip,
      WxVar.precipProb,
      WxVar.windGust,
      WxVar.visibility,
    });
    expect(tierOf(WxVar.uvIndex), WxTier.prepare);
    expect(tierOf(WxVar.uvIndexClearSky), WxTier.reference);
    expect(tierOf(WxVar.windSpeed), WxTier.reference); // 持续风速不顶替阵风
  });

  test('紫外线分级（世界卫生组织）', () {
    expect(uvLevelOf(2.9), UvLevel.low);
    expect(uvLevelOf(3), UvLevel.moderate);
    expect(uvLevelOf(6), UvLevel.high);
    expect(uvLevelOf(8), UvLevel.veryHigh);
    expect(uvLevelOf(11), UvLevel.extreme);
  });

  group('signalsFor', () {
    test('紫外线 ≥ 6 升为重点；≥ 8 为警示', () {
      final s = signalsFor(_wx({WxVar.uvIndex: 9}));
      expect(s.single.kind, WxSignalKind.uv);
      expect(s.single.level, WxSignalLevel.warning);
      expect(s.single.label, '紫外线很高 9');
      expect(signalsFor(_wx({WxVar.uvIndex: 5})), isEmpty);
    });

    test('只有晴空值：只说“晴空可达”，不当预报', () {
      final s = signalsFor(_wx({WxVar.uvIndexClearSky: 7}));
      expect(s.single.kind, WxSignalKind.uvClearSky);
      expect(s.single.level, WxSignalLevel.info);
      expect(s.single.label, contains('晴空'));
      // 有预报值时不再显示晴空值
      expect(
        signalsFor(_wx({WxVar.uvIndex: 1, WxVar.uvIndexClearSky: 7})),
        isEmpty,
      );
    });

    test('积雪 + 紫外线 → 雪面反光；节点高于 0℃ 层；低云；湿冷；对流潜势', () {
      final s = signalsFor(
        _wx({
          WxVar.uvIndex: 3,
          WxVar.snowDepth: 0.12,
          WxVar.freezingLevel: 1500,
          WxVar.cloudLow: 90,
          WxVar.temperature: 2,
          WxVar.humidity: 95,
          WxVar.cape: 1200,
        }),
        elevationM: 1800,
      );
      final kinds = s.map((x) => x.kind).toSet();
      expect(kinds, {
        WxSignalKind.snowGlare,
        WxSignalKind.aboveFreezing,
        WxSignalKind.snowCover,
        WxSignalKind.lowCloud,
        WxSignalKind.dampCold,
        WxSignalKind.convective,
      });
      // 按严重程度排序：caution 在 info 之前
      expect(s.first.level, WxSignalLevel.caution);
    });

    test('缺失变量不触发', () {
      expect(signalsFor(_wx({}), elevationM: 3000), isEmpty);
    });
  });

  group('紫外线提示（computeHints）', () {
    NodeWeatherEntry e(double? uv, {double? ele, double? clear}) =>
        NodeWeatherEntry(
          validUtc: DateTime.utc(2026, 10, 18, 4),
          elevationM: ele,
          weather: _wx({
            WxVar.uvIndex: uv,
            WxVar.uvIndexClearSky: clear,
            WxVar.temperature: 10,
            WxVar.precip: 0,
            WxVar.windGust: 2,
          }),
        );

    test('≥ 6 提示；≥ 8 升为注意；高处说明可能更强', () {
      final h = computeHints(entries: [e(5), e(9, ele: 2400)]);
      final uv = h.firstWhere((x) => x.id == 'uv');
      expect(uv.level, HintLevel.caution);
      expect(uv.detail, contains('1 个节点'));
      expect(uv.detail, contains('高处'));
      expect(uv.basis, contains('未按节点海拔修正'));
    });

    test('只有晴空值不触发', () {
      final h = computeHints(entries: [e(null, clear: 9)]);
      expect(h.where((x) => x.id == 'uv'), isEmpty);
    });
  });
}
