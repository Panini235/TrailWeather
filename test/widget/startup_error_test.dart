import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/core/app_links.dart';
import 'package:trailweather/ui/startup_error.dart';
import 'package:trailweather/ui/strings.dart';

void main() {
  testWidgets('启动失败：显示原因、版本与反馈地址，可复制诊断信息', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await tester.pumpWidget(
      StartupErrorApp(error: Exception('NoSuchMethodError: getAll')),
    );
    expect(find.text(S.startupFailedTitle), findsOneWidget);
    expect(find.textContaining('NoSuchMethodError'), findsOneWidget);
    expect(find.text(kFeedbackUrl), findsOneWidget);
    await tester.tap(find.text(S.startupCopyDiagnostics));
    await tester.pump();
    expect(copied, contains(kAppVersion));
    expect(copied, contains('NoSuchMethodError'));
  });
}
