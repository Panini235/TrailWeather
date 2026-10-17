import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_providers.dart';
import '../../data/settings/settings_repository.dart';
import '../motion.dart';
import '../strings.dart';
import 'splash_art.dart';

/// 冷启动开屏：盖在路由之上，首页同时在下面加载，播完从树上移除（之后零帧）。
///
/// 系统启动页只铺同一底色（tool/apply_branding.py），所以首帧无缝衔接。
/// 当天第一次完整播放并可跳过；当天再次启动只快速淡入；系统减少动效或
/// 低耗电时显示静态图标。从后台切回不会重建本组件，因此不会重播。Web 不播。
class SplashOverlay extends ConsumerStatefulWidget {
  const SplashOverlay({super.key, required this.child});

  final Widget child;

  static const lastFullDayKey = 'splash.lastFullDay';

  @override
  ConsumerState<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends ConsumerState<SplashOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _build = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _leave();
    });
  late final AnimationController _exit = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
      }
    });
  late final _word = CurvedAnimation(
    parent: _build,
    curve: const Interval(850 / 1100, 1, curve: Curves.easeOutCubic),
  );
  late final _fadeIn = CurvedAnimation(parent: _build, curve: Motion.enter);
  late final _exitCurve = CurvedAnimation(parent: _exit, curve: Motion.exit);
  bool _done = kIsWeb;
  SplashMode? _mode;
  late SplashSky _sky;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done || _mode != null) return;
    final local = ref.read(weatherNowProvider)().toLocal();
    final prefs = ref.read(prefsProvider);
    _sky = SplashSky.at(local);
    _mode = splashModeFor(
      local: local,
      lastFullDay: prefs.getString(SplashOverlay.lastFullDayKey),
      reduced: Motion.reduced(
        context,
        lowPower: ref.read(settingsProvider).lowPower,
      ),
    );
    _build.duration = switch (_mode!) {
      SplashMode.full => SplashArt.fullDuration,
      SplashMode.short => SplashArt.shortDuration,
      SplashMode.still => SplashArt.stillHold,
    };
    if (_mode == SplashMode.full) {
      unawaited(
        prefs.setString(SplashOverlay.lastFullDayKey, splashDayKey(local)),
      );
    }
    _build.forward();
  }

  @override
  void dispose() {
    _word.dispose();
    _fadeIn.dispose();
    _exitCurve.dispose();
    _build.dispose();
    _exit.dispose();
    super.dispose();
  }

  void _skip() {
    if (_build.isAnimating) _build.value = 1; // 状态变为 completed → _leave
  }

  void _leave() {
    if (_done || _exit.isAnimating || _exit.isCompleted) return;
    _exit.duration = _mode == SplashMode.still
        ? const Duration(milliseconds: 150)
        : const Duration(milliseconds: 220);
    _exit.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark
        ? SplashArt.darkBackground
        : SplashArt.lightBackground;
    final ink = dark ? SplashArt.cream : SplashArt.mountain;
    final full = _mode == SplashMode.full;
    const shown = AlwaysStoppedAnimation<double>(1);
    final Animation<double> art = full ? _build : shown;
    final Animation<double> word = full ? _word : shown;
    Widget logo = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: S.appTitle,
          image: true,
          child: SizedBox.square(
            dimension: 168,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: SplashPainter(
                  progress: art,
                  sky: _sky,
                  background: background,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        FadeTransition(
          opacity: word,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(word),
            child: ExcludeSemantics(
              child: Column(
                children: [
                  Text(
                    S.appTitle,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 6,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    S.splashTagline,
                    style: TextStyle(
                      fontSize: 13,
                      color: dark
                          ? const Color(0xFFB9C4B9)
                          : const Color(0xFF4E5D52),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    if (_mode == SplashMode.short) {
      logo = FadeTransition(
        opacity: _fadeIn,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(_fadeIn),
          child: logo,
        ),
      );
    }
    final exit = _exitCurve;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: FadeTransition(
            opacity: ReverseAnimation(exit),
            child: BlockSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _skip,
                // 开屏盖在路由之上，没有 Scaffold：用 Material 提供文字样式与按钮墨水，
                // 否则 Text 会落到 WidgetsApp 的报错样式（黄色双下划线，真机发现）。
                child: Material(
                  color: background,
                  child: SafeArea(
                    child: Stack(
                      children: [
                        Center(
                          child: _mode == SplashMode.still
                              ? logo
                              : ScaleTransition(
                                  scale: Tween(
                                    begin: 1.0,
                                    end: 1.04,
                                  ).animate(exit),
                                  child: logo,
                                ),
                        ),
                        if (full)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: TextButton(
                              onPressed: _skip,
                              style: TextButton.styleFrom(foregroundColor: ink),
                              child: const Text(S.splashSkip),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
