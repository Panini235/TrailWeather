import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/ui/strings.dart';
import 'package:trailweather/ui/widgets/common.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green)),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('MissingValueText：缺失显示“此来源未提供”，不为 0', (tester) async {
    await tester.pumpWidget(_wrap(const MissingValueText()));
    expect(find.text(S.notProvided), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('DemoBadge：演示标签可见', (tester) async {
    await tester.pumpWidget(_wrap(const DemoBadge()));
    expect(find.text(S.demoLabel), findsOneWidget);
  });

  testWidgets('GranularityNotice：展示颗粒度声明全文', (tester) async {
    const text = '所选坐标对应网格预报，非点位实测；来源未提供空间分辨率，位置颗粒度未确认';
    await tester.pumpWidget(_wrap(const GranularityNotice(text: text)));
    expect(find.text(text), findsOneWidget);
  });

  testWidgets('StaleDataBanner：显示旧数据状态与缓存时间', (tester) async {
    await tester.pumpWidget(_wrap(StaleDataBanner(
      cachedAtUtc: DateTime.now().toUtc().subtract(const Duration(minutes: 40)),
    )));
    expect(find.textContaining(S.staleData), findsOneWidget);
    expect(find.textContaining('40 分钟前'), findsOneWidget);
  });

  testWidgets('DataKindChip：预报类型标签', (tester) async {
    await tester.pumpWidget(_wrap(const DataKindChip(kind: WxDataKind.forecast)));
    expect(find.text('短期预报'), findsOneWidget);
  });

  testWidgets('ErrorCard：错误如实展示并可重试', (tester) async {
    var retried = false;
    await tester.pumpWidget(_wrap(ErrorCard(
      title: '来源请求失败',
      detail: 'HTTP 429',
      onRetry: () => retried = true,
    )));
    expect(find.text('来源请求失败'), findsOneWidget);
    expect(find.textContaining('HTTP 429'), findsOneWidget);
    await tester.tap(find.text(S.retry));
    await tester.pump();
    expect(retried, isTrue);
  });
}
