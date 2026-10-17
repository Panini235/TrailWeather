import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/core/coord_parse.dart';

void expectCoord(String input, double lat, double lon, {bool swapped = false}) {
  final c = parseCoordinate(input);
  expect(c, isNotNull, reason: input);
  expect(c!.point.latitude, closeTo(lat, 1e-6), reason: input);
  expect(c.point.longitude, closeTo(lon, 1e-6), reason: input);
  expect(c.swapped, swapped, reason: input);
}

void main() {
  test('十进制：逗号、空格、中文逗号', () {
    expectCoord('39.99, 116.17', 39.99, 116.17);
    expectCoord('39.99 116.17', 39.99, 116.17);
    expectCoord(' 39.99，116.17 ', 39.99, 116.17);
    expectCoord('-33.86, 151.21', -33.86, 151.21);
  });

  test('经度在前（如从高德复制）：第一个数超出 ±90 时交换并标注', () {
    expectCoord('116.17,39.99', 39.99, 116.17, swapped: true);
  });

  test('方位字母与中文方位', () {
    expectCoord('N39.99 E116.17', 39.99, 116.17);
    expectCoord('39.99N, 116.17E', 39.99, 116.17);
    expectCoord('E116.17 N39.99', 39.99, 116.17, swapped: true);
    expectCoord('北纬39.99 东经116.17', 39.99, 116.17);
    expectCoord('33.86S 151.21E', -33.86, 151.21);
    expectCoord('19.5N 155.6W', 19.5, -155.6);
  });

  test('度分秒', () {
    expectCoord('39°59\'24"N 116°10\'12"E', 39.99, 116.17);
    expectCoord('39度59分24秒 116度10分12秒', 39.99, 116.17);
    expectCoord('N39°59.4\' E116°10.2\'', 39.99, 116.17);
  });

  test('不是坐标时返回 null', () {
    for (final s in [
      '',
      '香山',
      '39.99',
      'G109 国道',
      '2026 五台山',
      '1 2',
      '39.99, 116.17 香山',
      '95.1, 200.2',
      '39.99N 40.00N',
      '39°75\' 116°10\'',
    ]) {
      expect(parseCoordinate(s), isNull, reason: s);
    }
  });
}
