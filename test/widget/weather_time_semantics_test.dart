import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/ui/detail/meteogram.dart';
import 'package:trailweather/ui/detail/weather_cells.dart';

import '../support/departure_fixtures.dart';

void main() {
  testWidgets('时间图和指标格显示同一区间的降水，文案明确起止', (tester) async {
    final p = departureBundle(
      providerId: 'open-meteo:best_match',
      hours: 3,
      values: (_, t) => {
        WxVar.temperature: 10,
        WxVar.precip: t == departureTestStart ? 0 : 8,
        WxVar.precipProb: 90,
        WxVar.windGust: 18,
      },
    ).result.points.first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                NodeMeteogram(
                  point: p,
                  arrivalUtc: departureTestStart,
                  settings: const AppSettings(),
                  hoursBefore: 0,
                ),
                WxVarGrid(
                  wx: p.hourAt(departureTestStart)!,
                  settings: const AppSettings(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('8.0 mm'), findsOneWidget);
    expect(find.textContaining('8.0 mm 90%'), findsOneWidget);
    expect(find.textContaining('未做小时内插值'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
