import 'package:latlong2/latlong.dart';

/// 搜索框里识别出的经纬度。
class ParsedCoordinate {
  const ParsedCoordinate(this.point, {this.swapped = false});

  /// 按 WGS-84 解释的坐标。
  final LatLng point;

  /// 输入按“经度, 纬度”顺序识别（如从高德等地图复制的坐标）。
  final bool swapped;
}

/// 解析搜索框里的经纬度（地图搜索：经纬度直接查天气）。
///
/// 支持十进制（`39.99, 116.17`、空格或中文逗号分隔）、方位字母或中文方位
/// （`N39.99 E116.17`、`北纬39.99 东经116.17`、`39.99N 116.17E`）、度分秒
/// （`39°59'24"N 116°10'12"E`、`39度59分24秒`）。
/// 整个输入必须只由坐标组成，否则返回 null，避免把“G109 国道”之类当成坐标。
/// 无方位标记时默认“纬度, 经度”；第一个数超出 ±90 且第二个不超出时按“经度, 纬度”。
ParsedCoordinate? parseCoordinate(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  s = s
      .replaceAll('，', ',')
      .replaceAll('；', ',')
      .replaceAll(';', ',')
      .replaceAll('、', ',')
      .replaceAll('－', '-')
      .replaceAll('−', '-')
      .replaceAll('º', '°')
      .replaceAll('度', '°')
      .replaceAll('′', "'")
      .replaceAll('’', "'")
      .replaceAll('分', "'")
      .replaceAll('″', '"')
      .replaceAll('”', '"')
      .replaceAll("''", '"')
      .replaceAll('秒', '"')
      .replaceAll('北纬', 'N')
      .replaceAll('南纬', 'S')
      .replaceAll('东经', 'E')
      .replaceAll('西经', 'W')
      .toUpperCase();

  // 一个分量：数值（度[分[秒]]）加方位。按风格二选一：以方位字母开头的输入
  // 用前缀方位（N39.99 E116.17），否则用后缀方位（39.99N 116.17E）；
  // 同时允许前后缀会让第一个分量吞掉第二个分量的前缀。
  const number =
      r'''(-?\d+(?:\.\d+)?)\s*(?:°\s*(?:(\d+(?:\.\d+)?)\s*'\s*(?:(\d+(?:\.\d+)?)\s*"\s*)?)?)?''';
  final prefixStyle = RegExp(r'^[NSEW]').hasMatch(s);
  final part = prefixStyle
      ? RegExp(r'([NSEW])\s*' + number)
      : RegExp(number + r'\s*([NSEW])?');
  final matches = part.allMatches(s).toList();
  if (matches.length != 2) return null;
  // 去掉两个分量后只能剩分隔符，确保整个输入都是坐标。
  final rest = s.replaceAll(part, '').replaceAll(RegExp(r'[\s,/]'), '');
  if (rest.isNotEmpty) return null;

  (double, String?)? read(RegExpMatch m) {
    final o = prefixStyle ? 1 : 0;
    final hemi = prefixStyle ? m.group(1) : m.group(4);
    var v = double.parse(m.group(1 + o)!);
    final min = m.group(2 + o), sec = m.group(3 + o);
    if (min != null || sec != null) {
      final mm = min == null ? 0.0 : double.parse(min);
      final ss = sec == null ? 0.0 : double.parse(sec);
      if (mm >= 60 || ss >= 60) return null;
      final sign = v < 0 ? -1 : 1;
      v = sign * (v.abs() + mm / 60 + ss / 3600);
    }
    if (hemi == 'S' || hemi == 'W') v = -v.abs();
    return (v, hemi);
  }

  // 两个纯整数且没有方位/度分秒标记时不当坐标（如搜索“1 2”）：真实坐标几乎都带小数。
  final marked = RegExp(r'''[NSEW°'"]''').hasMatch(s);
  final numberGroup = prefixStyle ? 2 : 1;
  if (!marked && !matches.any((m) => m.group(numberGroup)!.contains('.'))) {
    return null;
  }

  final a = read(matches[0]), b = read(matches[1]);
  if (a == null || b == null) return null;
  final (va, ha) = a;
  final (vb, hb) = b;
  bool isLat(String? h) => h == 'N' || h == 'S';
  bool isLon(String? h) => h == 'E' || h == 'W';

  double lat, lon;
  var swapped = false;
  if (ha != null || hb != null) {
    if (isLat(ha) || isLon(hb)) {
      lat = va;
      lon = vb;
    } else if (isLon(ha) || isLat(hb)) {
      lat = vb;
      lon = va;
      swapped = true;
    } else {
      return null;
    }
    if ((isLat(ha) && isLat(hb)) || (isLon(ha) && isLon(hb))) return null;
  } else if (va.abs() > 90 && vb.abs() <= 90) {
    lat = vb;
    lon = va;
    swapped = true;
  } else {
    lat = va;
    lon = vb;
  }
  if (lat.abs() > 90 || lon.abs() > 180) return null;
  return ParsedCoordinate(LatLng(lat, lon), swapped: swapped);
}
