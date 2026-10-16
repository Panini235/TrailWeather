import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/weather/node_wx_class.dart';
import 'package:trailweather/data/weather/weather_models.dart';

WxHourValue _wx({
  double? temp = 10,
  double? precip = 0,
  double? prob,
  double? wind = 3,
  double? gust = 5,
}) => WxHourValue(
  validFromUtc: DateTime.utc(2026, 10, 15, 6),
  values: {
    for (final v in WxVar.values) v: null,
    WxVar.temperature: temp,
    WxVar.precip: precip,
    WxVar.precipProb: prob,
    WxVar.windSpeed: wind,
    WxVar.windGust: gust,
  },
);

void main() {
  test('无数据与关键变量缺失不归为“未触发阈值”', () {
    expect(classifyNodeWx(null), NodeWxClass.noData);
    expect(classifyNodeWx(_wx(precip: null)), NodeWxClass.insufficient);
    expect(classifyNodeWx(_wx(temp: null)), NodeWxClass.insufficient);
    expect(classifyNodeWx(_wx(gust: null)), NodeWxClass.insufficient);
    expect(classifyNodeWx(_wx()), NodeWxClass.calm);
  });

  test('阈值与 redesign-v2 出发窗口一致', () {
    expect(classifyNodeWx(_wx(gust: 17.2)), NodeWxClass.galeWind);
    expect(classifyNodeWx(_wx(gust: 13.9)), NodeWxClass.strongWind);
    expect(classifyNodeWx(_wx(gust: 13.8)), NodeWxClass.calm);
    expect(classifyNodeWx(_wx(precip: 2)), NodeWxClass.heavyPrecip);
    expect(classifyNodeWx(_wx(temp: -10)), NodeWxClass.severeCold);
    expect(classifyNodeWx(_wx(precip: 0.2)), NodeWxClass.precip);
    expect(classifyNodeWx(_wx(prob: 60)), NodeWxClass.precip);
    expect(classifyNodeWx(_wx(temp: 0)), NodeWxClass.freezing);
  });

  test('阵风缺失不能用持续风速冒充', () {
    // 持续风速低但阵风高：按阵风判定。
    expect(classifyNodeWx(_wx(wind: 5, gust: 18)), NodeWxClass.galeWind);
    expect(classifyNodeWx(_wx(wind: 14, gust: null)), NodeWxClass.insufficient);
    expect(classifyNodeWx(_wx(wind: 30, gust: null)), NodeWxClass.insufficient);
  });

  test('多项触发时取更严重的类别', () {
    expect(
      classifyNodeWx(_wx(temp: -12, precip: 3, gust: 15)),
      NodeWxClass.severeCold,
    );
    expect(classifyNodeWx(_wx(precip: 3, gust: 15)), NodeWxClass.heavyPrecip);
    expect(NodeWxClass.galeWind.level, NodeWxLevel.red);
    expect(NodeWxClass.insufficient.level, NodeWxLevel.unknown);
  });
}
