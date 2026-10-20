import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/ui/detail/ridge_axis.dart';

void main() {
  test('手机5.5km剖面含1/2/3/4km，终点标签留出空间', () {
    expect(ridgeDistanceTicks(5500, 300), [1000, 2000, 3000, 4000]);
  });
  test('短长线路均使用有限递增刻度，窄图不挤标签', () {
    for (final length in [120.0, 24000.0, 800000.0]) {
      final ticks = ridgeDistanceTicks(length, 300);
      expect(ticks.length, inInclusiveRange(1, 6));
      expect(ticks, orderedEquals(ticks.toList()..sort()));
      expect(
        ticks.every(
          (d) => d > 0 && d < length && (length - d) * 300 / length >= 52,
        ),
        isTrue,
      );
    }
    expect(ridgeDistanceTicks(1000, 80), isEmpty);
    expect(ridgeDistanceTicks(double.nan, 300), isEmpty);
    expect(ridgeDistanceTicks(0, 300), isEmpty);
  });
}
