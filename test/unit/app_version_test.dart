import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/core/app_links.dart';

void main() {
  test('kAppVersion 与 pubspec.yaml 的 version 一致', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final version = line.substring('version:'.length).trim().split('+').first;
    expect(kAppVersion, version);
  });

  test('下载地址是公开的 Releases 列表页（含测试版，无需登录）', () {
    expect(kDownloadUrl, 'https://github.com/Panini235/TrailWeather/releases');
  });
}
