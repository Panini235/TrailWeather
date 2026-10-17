import 'weather_models.dart';

/// 天气现象粗分类（用于提示与着色）。
enum WxPhenomenonKind { clear, cloudy, haze, fog, rain, snow, mixed, thunder }

class WxPhenomenon {
  const WxPhenomenon(this.label, this.kind);
  final String label;
  final WxPhenomenonKind kind;
}

/// meteoblue 逐时（1h/3h）pictocode → 中文现象。
/// 依据 docs.meteoblue.com/en/meteo/variables/pictograms 的 Hourly 表（2026-10-15 核对，
/// 页面更新于 2026-05-05）。日数据使用另一套编码，不能混用。
const Map<int, WxPhenomenon> meteoblueHourlyPictocodes = {
  1: WxPhenomenon('晴朗无云', WxPhenomenonKind.clear),
  2: WxPhenomenon('晴，少量卷云', WxPhenomenonKind.clear),
  3: WxPhenomenon('晴，有卷云', WxPhenomenonKind.clear),
  4: WxPhenomenon('晴，少量低云', WxPhenomenonKind.clear),
  5: WxPhenomenon('晴，少量低云和卷云', WxPhenomenonKind.clear),
  6: WxPhenomenon('晴，有低云和卷云', WxPhenomenonKind.clear),
  7: WxPhenomenon('局部多云', WxPhenomenonKind.cloudy),
  8: WxPhenomenon('局部多云，少量卷云', WxPhenomenonKind.cloudy),
  9: WxPhenomenon('局部多云，有卷云', WxPhenomenonKind.cloudy),
  10: WxPhenomenon('云系混合，可能有雷暴云', WxPhenomenonKind.thunder),
  11: WxPhenomenon('云系混合（少量卷云），可能有雷暴云', WxPhenomenonKind.thunder),
  12: WxPhenomenon('云系混合（有卷云），可能有雷暴云', WxPhenomenonKind.thunder),
  13: WxPhenomenon('晴但有霾', WxPhenomenonKind.haze),
  14: WxPhenomenon('晴但有霾，少量卷云', WxPhenomenonKind.haze),
  15: WxPhenomenon('晴但有霾，有卷云', WxPhenomenonKind.haze),
  16: WxPhenomenon('雾/低层云', WxPhenomenonKind.fog),
  17: WxPhenomenon('雾/低层云，少量卷云', WxPhenomenonKind.fog),
  18: WxPhenomenon('雾/低层云，有卷云', WxPhenomenonKind.fog),
  19: WxPhenomenon('大部多云', WxPhenomenonKind.cloudy),
  20: WxPhenomenon('大部多云，少量卷云', WxPhenomenonKind.cloudy),
  21: WxPhenomenon('大部多云，有卷云', WxPhenomenonKind.cloudy),
  22: WxPhenomenon('阴', WxPhenomenonKind.cloudy),
  23: WxPhenomenon('阴有雨', WxPhenomenonKind.rain),
  24: WxPhenomenon('阴有雪', WxPhenomenonKind.snow),
  25: WxPhenomenon('阴有大雨', WxPhenomenonKind.rain),
  26: WxPhenomenon('阴有大雪', WxPhenomenonKind.snow),
  27: WxPhenomenon('有雨，可能雷暴', WxPhenomenonKind.thunder),
  28: WxPhenomenon('小雨，可能雷暴', WxPhenomenonKind.thunder),
  29: WxPhenomenon('大雪暴风', WxPhenomenonKind.snow),
  30: WxPhenomenon('大雨，可能雷暴', WxPhenomenonKind.thunder),
  31: WxPhenomenon('阵雨（云系混合）', WxPhenomenonKind.rain),
  32: WxPhenomenon('阵雪（云系混合）', WxPhenomenonKind.snow),
  33: WxPhenomenon('阴有小雨', WxPhenomenonKind.rain),
  34: WxPhenomenon('阴有小雪', WxPhenomenonKind.snow),
  35: WxPhenomenon('阴有雨夹雪', WxPhenomenonKind.mixed),
};

/// Open-Meteo weather_code（WMO 4677 子集）→ 中文现象。
/// 依据 open-meteo.com/en/docs 的 WMO 表（2026-10-15 核对）；96/99 仅部分模式（ICON/UKMO）给出。
const Map<int, WxPhenomenon> wmoWeatherCodes = {
  0: WxPhenomenon('晴', WxPhenomenonKind.clear),
  1: WxPhenomenon('大致晴', WxPhenomenonKind.clear),
  2: WxPhenomenon('局部多云', WxPhenomenonKind.cloudy),
  3: WxPhenomenon('阴', WxPhenomenonKind.cloudy),
  45: WxPhenomenon('雾', WxPhenomenonKind.fog),
  48: WxPhenomenon('雾凇雾（结霜）', WxPhenomenonKind.fog),
  51: WxPhenomenon('小毛毛雨', WxPhenomenonKind.rain),
  53: WxPhenomenon('毛毛雨', WxPhenomenonKind.rain),
  55: WxPhenomenon('大毛毛雨', WxPhenomenonKind.rain),
  56: WxPhenomenon('冻毛毛雨', WxPhenomenonKind.mixed),
  57: WxPhenomenon('强冻毛毛雨', WxPhenomenonKind.mixed),
  61: WxPhenomenon('小雨', WxPhenomenonKind.rain),
  63: WxPhenomenon('中雨', WxPhenomenonKind.rain),
  65: WxPhenomenon('大雨', WxPhenomenonKind.rain),
  66: WxPhenomenon('冻雨', WxPhenomenonKind.mixed),
  67: WxPhenomenon('强冻雨', WxPhenomenonKind.mixed),
  71: WxPhenomenon('小雪', WxPhenomenonKind.snow),
  73: WxPhenomenon('中雪', WxPhenomenonKind.snow),
  75: WxPhenomenon('大雪', WxPhenomenonKind.snow),
  77: WxPhenomenon('米雪', WxPhenomenonKind.snow),
  80: WxPhenomenon('小阵雨', WxPhenomenonKind.rain),
  81: WxPhenomenon('阵雨', WxPhenomenonKind.rain),
  82: WxPhenomenon('强阵雨', WxPhenomenonKind.rain),
  85: WxPhenomenon('小阵雪', WxPhenomenonKind.snow),
  86: WxPhenomenon('强阵雪', WxPhenomenonKind.snow),
  95: WxPhenomenon('雷暴', WxPhenomenonKind.thunder),
  96: WxPhenomenon('雷暴伴小冰雹', WxPhenomenonKind.thunder),
  97: WxPhenomenon('强雷暴', WxPhenomenonKind.thunder),
  99: WxPhenomenon('雷暴伴大冰雹', WxPhenomenonKind.thunder),
};

/// 某时次的天气现象（来源提供现象编码时）；未提供返回 null，不从其他变量推测。
WxPhenomenon? phenomenonOf(WxHourValue? h) {
  final mb = int.tryParse(h?.symbols?['mb_pictocode'] ?? '');
  if (mb != null) return meteoblueHourlyPictocodes[mb];
  final wmo = int.tryParse(h?.symbols?['wmo_code'] ?? '');
  if (wmo != null) return wmoWeatherCodes[wmo];
  return null;
}
