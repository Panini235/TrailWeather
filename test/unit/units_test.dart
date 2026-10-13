import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/core/units.dart';

void main() {
  test('温度换算', () {
    expect(Units.cToF(0), 32);
    expect(Units.cToF(100), 212);
    expect(Units.cToF(-40), -40);
    expect(Units.temp(25.4, imperial: false), '25°C');
    expect(Units.temp(25.4, imperial: true), '78°F');
  });

  test('风速换算', () {
    expect(Units.msToKmh(10), 36);
    expect(Units.msToMph(10), closeTo(22.37, 0.01));
    expect(Units.windMs(10, unit: 'm/s'), '10.0 m/s');
    expect(Units.windMs(10, unit: 'km/h'), '36 km/h');
    expect(Units.windMs(10, unit: 'mph'), '22 mph');
  });

  test('降水与距离换算', () {
    expect(Units.mmToIn(25.4), closeTo(1.0, 0.001));
    expect(Units.kmToMi(10), closeTo(6.2137, 0.001));
    expect(Units.precipMm(2.5, imperial: false), '2.5 mm');
    expect(Units.distanceKm(0.5, imperial: false), '500 m');
    expect(Units.distanceKm(12.34, imperial: false), '12.3 km');
    expect(Units.distanceKm(12.34, imperial: true), '7.7 mi');
    expect(Units.elevationM(1500, imperial: true), '4921 ft');
  });

  test('风向十六方位', () {
    expect(Units.windDirectionLabel(0), '北');
    expect(Units.windDirectionLabel(90), '东');
    expect(Units.windDirectionLabel(180), '南');
    expect(Units.windDirectionLabel(270), '西');
    expect(Units.windDirectionLabel(45), '东北');
    expect(Units.windDirectionLabel(360), '北');
  });

  test('蒲福风级', () {
    expect(Units.beaufort(0.1), 0);
    expect(Units.beaufort(5.0), 3);
    expect(Units.beaufort(17.2), 8);
    expect(Units.beaufort(33), 12);
  });
}
