import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/weather/meteoblue_provider.dart';
import 'package:trailweather/ui/map/point_weather_sheet.dart';
import 'package:trailweather/ui/strings.dart';

import '../integration/core_flow_test.dart' show IntegrationFakeProvider;

String _fixtureForToday() {
  final n = DateTime.now().toUtc();
  String hour(int h) =>
      DateTime.utc(n.year, n.month, n.day, h).toIso8601String();
  final hours = [for (var h = 0; h < 30; h++) hour(h)];
  return jsonEncode({
    'metadata': {'height': 1200, 'modelrun_utc': hours.first},
    'data_1h': {
      'time': hours,
      'temperature': [for (var _ in hours) 5.0],
      'pictocode': [for (var _ in hours) 16],
      'snowfraction': [for (var _ in hours) 0.0],
    },
  });
}

void main() {
  testWidgets('按次计费来源不自动请求；点击“查询此点”才请求一次并显示现象', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({
      'settings.v1': jsonEncode(
        const AppSettings()
            .copyWith(
              enabledProviderIds: [
                'fake:integration',
                MeteoblueProvider.providerIdValue,
              ],
            )
            .toJson(),
      ),
    });
    final prefs = await SharedPreferences.getInstance();
    var mbCalls = 0;
    final mb = MeteoblueProvider(
      apiKey: 'k',
      fetcher: (uri, {headers, cancelToken}) async {
        mbCalls++;
        return _fixtureForToday();
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          weatherProvidersProvider.overrideWithValue([
            IntegrationFakeProvider(),
            mb,
          ]),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PointWeatherSheet(
              point: const LatLng(39.08, 113.58),
              label: '测试点',
              requestedAtUtc: DateTime.now().toUtc(),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(mbCalls, 0);
    expect(find.text(S.onDemandQuery), findsOneWidget);

    await tester.tap(find.text(S.onDemandQuery));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(mbCalls, 1);
    expect(find.text(S.onDemandQuery), findsNothing);
  });
}
