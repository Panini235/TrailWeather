import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/weather/risk_rules.dart';
import 'package:trailweather/data/weather/weather_models.dart';

WxHourValue _hour({
  double? gust,
  double? precip,
  double? precipProb,
  double? temp,
}) => WxHourValue(
  validFromUtc: DateTime.utc(2026, 10, 13, 10),
  values: {
    WxVar.windGust: gust,
    WxVar.precip: precip,
    WxVar.precipProb: precipProb,
    WxVar.temperature: temp,
  },
);

void main() {
  test('阵风超阈值触发大风提示（非官方预警）', () {
    final hints = computeHints(
      entries: [
        NodeWeatherEntry(
          weather: _hour(gust: 18.0),
          validUtc: DateTime.utc(2026, 10, 13, 10),
        ),
      ],
    );
    final gust = hints.where((h) => h.id == 'gust').toList();
    expect(gust, hasLength(1));
    expect(gust.first.level, HintLevel.warning);
    expect(gust.first.basis, contains('非官方预警'));
  });

  test('阵风缺失不触发', () {
    final hints = computeHints(
      entries: [
        NodeWeatherEntry(
          weather: _hour(),
          validUtc: DateTime.utc(2026, 10, 13, 10),
        ),
      ],
    );
    expect(hints.where((h) => h.id == 'gust'), isEmpty);
  });

  test('累计降水达标触发强降水', () {
    final hints = computeHints(
      entries: [
        for (var i = 0; i < 3; i++)
          NodeWeatherEntry(
            weather: _hour(precip: 3.0),
            validUtc: DateTime.utc(2026, 10, 13, 10 + i),
          ),
      ],
    );
    expect(hints.any((h) => h.id == 'precip'), isTrue);
  });

  test('高降水概率不等于降水量（分别提示）', () {
    final hints = computeHints(
      entries: [
        NodeWeatherEntry(
          weather: _hour(precipProb: 80, precip: 0.0),
          validUtc: DateTime.utc(2026, 10, 13),
        ),
      ],
    );
    final prob = hints.where((h) => h.id == 'precip_prob').toList();
    expect(prob, hasLength(1));
    expect(prob.first.detail, contains('降水概率不等于降水量'));
    expect(hints.any((h) => h.id == 'precip'), isFalse);
  });

  test('全部无数据显示信息不足（不默认安全）', () {
    final hints = computeHints(
      entries: [
        NodeWeatherEntry(weather: null, validUtc: DateTime.utc(2026, 10, 13)),
        NodeWeatherEntry(
          weather: null,
          validUtc: DateTime.utc(2026, 10, 13, 1),
        ),
      ],
    );
    expect(hints, hasLength(1));
    expect(hints.first.id, 'insufficient');
  });

  test('部分节点缺数据有明确提示', () {
    final hints = computeHints(
      entries: [
        NodeWeatherEntry(
          weather: _hour(temp: 20),
          validUtc: DateTime.utc(2026, 10, 13),
        ),
        NodeWeatherEntry(
          weather: null,
          validUtc: DateTime.utc(2026, 10, 13, 1),
        ),
      ],
    );
    expect(hints.any((h) => h.id == 'partial'), isTrue);
  });

  test('低温与高温', () {
    final cold = computeHints(
      entries: [
        NodeWeatherEntry(
          weather: _hour(temp: -12),
          validUtc: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
    expect(cold.any((h) => h.id == 'cold'), isTrue);
    final hot = computeHints(
      entries: [
        NodeWeatherEntry(
          weather: _hour(temp: 37),
          validUtc: DateTime.utc(2026, 7, 1),
        ),
      ],
    );
    expect(hot.any((h) => h.id == 'heat'), isTrue);
  });

  test('日落提示', () {
    final hint = sunsetHint(
      finishEtaUtc: DateTime.utc(2026, 10, 13, 12, 30),
      sunsetUtc: DateTime.utc(2026, 10, 13, 10, 0),
    );
    expect(hint, isNotNull);
    expect(hint!.id, 'sunset');
    final ok = sunsetHint(
      finishEtaUtc: DateTime.utc(2026, 10, 13, 9),
      sunsetUtc: DateTime.utc(2026, 10, 13, 10),
    );
    expect(ok, isNull);
  });

  test('官方预警固定为未接入表述', () {
    expect(officialAlertsNotAvailable, contains('未接入'));
    expect(officialAlertsNotAvailable, contains('不能替代'));
  });
}
