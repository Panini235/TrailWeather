import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// WGS-84 ↔ GCJ-02 坐标转换。
///
/// 背景：高德等国内底图使用国测局 GCJ-02 加密坐标系，同一位置的瓦片内容
/// 相对 WGS-84（GPS/国际标准）存在约 100–700 米的非线性偏移。
///
/// 本 App 的原则（docs/architecture.md）：
/// - 业务数据（线路、节点、天气查询、导入导出）**始终使用 WGS-84**；
/// - 仅在“渲染到国内底图”时转换为 GCJ-02（显示层适配），地图交互返回的
///   坐标逆变换回 WGS-84 再交给业务层；
/// - 境外坐标恒等返回（不做转换）。
///
/// 算法为业内通用的近似实现，逆变换采用迭代法（误差米级），
/// 非官方精确算法——如实告知，不宣称厘米级。
class Gcj02 {
  static const double _a = 6378245.0; // 长半轴
  static const double _ee = 0.00669342162296594323; // 偏心率平方

  static bool outOfChina(double lat, double lon) =>
      lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271;

  static LatLng wgs84ToGcj02(LatLng p) {
    if (outOfChina(p.latitude, p.longitude)) return p;
    final d = _delta(p.latitude, p.longitude);
    return LatLng(p.latitude + d.$1, p.longitude + d.$2);
  }

  /// 迭代逆变换：一阶近似 + 三次修正，误差通常 < 1 m。
  static LatLng gcj02ToWgs84(LatLng p) {
    if (outOfChina(p.latitude, p.longitude)) return p;
    final d0 = _delta(p.latitude, p.longitude);
    var wgs = LatLng(p.latitude - d0.$1, p.longitude - d0.$2);
    for (var i = 0; i < 3; i++) {
      final g = wgs84ToGcj02(wgs);
      wgs = LatLng(wgs.latitude + (p.latitude - g.latitude),
          wgs.longitude + (p.longitude - g.longitude));
    }
    return wgs;
  }

  static (double, double) _delta(double lat, double lon) {
    var dLat = _transformLat(lon - 105.0, lat - 35.0);
    var dLon = _transformLon(lon - 105.0, lat - 35.0);
    final radLat = lat / 180.0 * math.pi;
    var magic = math.sin(radLat);
    magic = 1 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * math.pi);
    dLon = (dLon * 180.0) / (_a / sqrtMagic * math.cos(radLat) * math.pi);
    return (dLat, dLon);
  }

  static double _transformLat(double x, double y) {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 / 3.0;
    ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) *
        2.0 / 3.0;
    ret += (160.0 * math.sin(y / 12.0 * math.pi) +
            320 * math.sin(y * math.pi / 30.0)) *
        2.0 / 3.0;
    return ret;
  }

  static double _transformLon(double x, double y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y +
        0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 / 3.0;
    ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) *
        2.0 / 3.0;
    ret += (150.0 * math.sin(x / 12.0 * math.pi) +
            300.0 * math.sin(x / 30.0 * math.pi)) *
        2.0 / 3.0;
    return ret;
  }
}
