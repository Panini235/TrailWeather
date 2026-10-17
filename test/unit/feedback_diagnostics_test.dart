import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/core/app_links.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/ui/settings/feedback_sheet.dart';

void main() {
  test('反馈诊断信息含构建与平台，不含 Key 原文', () {
    const settings = AppSettings(
      qweatherApiHost: 'abc123.qweatherapi.com',
      qweatherApiKey: 'secret-key-value',
      tiandituServerKey: 'tdt-server-key',
    );
    final text = feedbackDiagnostics(
      settings,
      platform: TargetPlatform.android,
      isWeb: false,
    );
    expect(text, contains(kDownloadUrl));
    expect(text, contains('平台：android'));
    expect(text, contains('和风天气 Key：已配置'));
    expect(text, isNot(contains('secret-key-value')));
    expect(text, isNot(contains('abc123')));
    expect(text, isNot(contains('tdt-server-key')));
    expect(
      feedbackDiagnostics(const AppSettings(), isWeb: true),
      contains('平台：Web'),
    );
  });
}
