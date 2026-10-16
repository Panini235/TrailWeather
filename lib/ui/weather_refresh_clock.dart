import 'dart:async';

import 'package:flutter/widgets.dart';

/// 仅在前台检查当前时刻。跨小时、跨日或间隔 15 分钟通知页面重查缓存时效。
/// 不请求定位，也不直接请求天气；计费来源仍由用户主动触发。
class WeatherRefreshClock extends ValueNotifier<DateTime>
    with WidgetsBindingObserver {
  WeatherRefreshClock({required DateTime initialUtc, required this.nowUtc})
    : super(initialUtc.toUtc()) {
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) _start();
  }

  final DateTime Function() nowUtc;
  Timer? _timer;

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => check());
  }

  void check() {
    final now = nowUtc().toUtc();
    final age = now.difference(value);
    if (now.year != value.year ||
        now.month != value.month ||
        now.day != value.day ||
        now.hour != value.hour ||
        age >= const Duration(minutes: 15) ||
        age.isNegative) {
      value = now;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    if (state == AppLifecycleState.resumed) {
      check();
      _start();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
