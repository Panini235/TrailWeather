import 'dart:math' as math;

/// 单位制与换算。内部标准单位：°C、m/s、mm、km、m。
/// 展示时按用户设置换算；换算函数为纯函数，全部有测试。
class Units {
  static double cToF(double c) => c * 9 / 5 + 32;
  static double kmToMi(double km) => km / 1.609344;
  static double mmToIn(double mm) => mm / 25.4;
  static double msToKmh(double ms) => ms * 3.6;
  static double msToMph(double ms) => ms * 2.2369362920544;
  static double mToFt(double m) => m * 3.280839895;

  static String temp(double c, {required bool imperial, int digits = 0}) {
    final v = imperial ? cToF(c) : c;
    return '${v.toStringAsFixed(digits)}°${imperial ? 'F' : 'C'}';
  }

  static String windMs(double ms, {required String unit}) {
    switch (unit) {
      case 'km/h':
        return '${msToKmh(ms).toStringAsFixed(0)} km/h';
      case 'm/s':
        return '${ms.toStringAsFixed(1)} m/s';
      case 'mph':
        return '${msToMph(ms).toStringAsFixed(0)} mph';
      default:
        return '${msToKmh(ms).toStringAsFixed(0)} km/h';
    }
  }

  static String precipMm(double mm, {required bool imperial}) {
    if (imperial) {
      return '${mmToIn(mm).toStringAsFixed(2)} in';
    }
    return '${mm.toStringAsFixed(1)} mm';
  }

  static String distanceKm(double km, {required bool imperial}) {
    if (imperial) {
      final mi = kmToMi(km);
      if (mi < 0.1) return '${Units.mToFt(km * 1000).toStringAsFixed(0)} ft';
      return '${mi.toStringAsFixed(mi < 100 ? 1 : 0)} mi';
    }
    if (km < 1) return '${(km * 1000).toStringAsFixed(0)} m';
    return '${km.toStringAsFixed(km < 100 ? 1 : 0)} km';
  }

  static String elevationM(double m, {required bool imperial}) {
    if (imperial) return '${mToFt(m).toStringAsFixed(0)} ft';
    return '${m.toStringAsFixed(0)} m';
  }

  /// 风向（气象学“来向”，各来源均为 wind-from 方向）：八方位加“风”字并附度数，
  /// 如“东南风 123°”。国内预报通用八方位；十六方位的“东东南”“北西北”不常见、
  /// 易被误读成标错（用户反馈），也说不清是来向还是去向。
  static String windDirectionLabel(double degrees) {
    const names = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    final d = (degrees % 360 + 360) % 360;
    final idx = ((d + 22.5) ~/ 45) % 8;
    return '${names[idx]}风 ${d.round() % 360}°';
  }

  /// 蒲福风级（由 m/s 计算），用于户外提示。
  static int beaufort(double ms) {
    final bounds = [
      0.3,
      1.6,
      3.4,
      5.5,
      8.0,
      10.8,
      13.9,
      17.2,
      20.8,
      24.5,
      28.5,
      32.7,
    ];
    for (var i = 0; i < bounds.length; i++) {
      if (ms < bounds[i]) return i;
    }
    return 12;
  }

  static double roundTo(double v, int digits) {
    final f = math.pow(10, digits).toDouble();
    return (v * f).round() / f;
  }
}
