import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/dev_proxy.dart';
import 'data/settings/settings_repository.dart';
import 'ui/startup_error.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installDevProxy();
  final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    // 本地存储都打不开时 App 无法工作：显示原因与反馈途径，不停在启动画面。
    runApp(StartupErrorApp(error: e));
    return;
  }
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const TrailWeatherApp(),
    ),
  );
}
