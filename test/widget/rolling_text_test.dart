import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/ui/strings.dart';
import 'package:trailweather/ui/widgets/rolling_text.dart';

void main() {
  testWidgets('单位分层排版仍完整切换真实读数，过渡中不混合新旧单位', (tester) async {
    Widget value(String text, {bool lowPower = false}) => MaterialApp(
      home: Scaffold(
        body: RollingText(
          text,
          style: const TextStyle(fontSize: 17),
          unitStyle: const TextStyle(fontSize: 12),
          lowPower: lowPower,
        ),
      ),
    );

    await tester.pumpWidget(value('36 km/h'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(value('10.0 m/s'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('36 km/h'), findsOneWidget);
    expect(find.text('10.0 m/s'), findsOneWidget);
    expect(find.text('36 m/s'), findsNothing);
    expect(find.text('10.0 km/h'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('36 km/h'), findsNothing);

    await tester.pumpWidget(value(S.notProvided, lowPower: true));
    expect(find.text(S.notProvided), findsOneWidget);
    expect(find.text('10.0 m/s'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
