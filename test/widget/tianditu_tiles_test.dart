import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/map/tianditu.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/ui/map/basemap.dart';
import 'package:trailweather/ui/map/map_layers_ui.dart';
import 'package:trailweather/ui/strings.dart';

// 2026-10-15 实测的 301012 响应体；Key 为假值，瓦片请求由 MockClient 应答，不访问网络。
const _body301012 =
    '{"code":301012,"msg":"权限类型错误","resolve":"Key权限类型为:浏览器端，请使用浏览器访问！"}';

void main() {
  testWidgets('天地图瓦片 403：经 TileLayer 识别错误码并在地图上提示', (tester) async {
    // flutter_map 内置瓦片缓存需要缓存目录；测试中指向临时目录。
    final tmp = Directory.systemTemp.createTempSync('tw_tile_cache');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // 缓存 worker 可能仍持有文件，留给系统清理。
      }
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final requests = <Uri>[];
    final c = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        tiandituTileClientProvider.overrideWith(
          (ref) => TiandituErrorSniffingClient(
            MockClient((req) async {
              requests.add(req.url);
              return http.Response.bytes(
                utf8.encode(_body301012),
                403,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
            onError: (e) => ref.read(tiandituErrorProvider.notifier).report(e),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    final n = c.read(settingsProvider.notifier);
    await n.setBaseLayer('tianditu_vec');
    await n.setTiandituKeys(server: 'fake-server', browser: 'fake-browser');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              final basemap = Basemap.fromSettings(
                ref.watch(settingsProvider),
                tiandituClient: ref.watch(tiandituTileClientProvider),
              );
              return Scaffold(
                body: Stack(
                  children: [
                    FlutterMap(
                      options: const MapOptions(
                        initialCenter: LatLng(39.9, 116.4),
                        initialZoom: 10,
                      ),
                      children: basemap.tileLayers(),
                    ),
                    const TiandituErrorBanner(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    // 缓存初始化与瓦片请求是真实异步（文件 IO / isolate），在 runAsync 中等待。
    // flutter_map 对每张失败瓦片 debugPrint 一行，等待期间静音。
    final print = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    try {
      for (var i = 0; i < 20 && c.read(tiandituErrorProvider) == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      await tester.pump();
    } finally {
      debugPrint = print;
    }

    expect(requests, isNotEmpty);
    // 测试运行在 VM 上（非 Web）：用服务端 Key。
    expect(
      requests.every((u) => u.queryParameters['tk'] == 'fake-server'),
      isTrue,
    );
    expect(
      c.read(tiandituErrorProvider)?.kind,
      TiandituErrorKind.browserKeyNotInBrowser,
    );
    expect(
      find.textContaining(S.tiandituErrBrowserKeyNotInBrowser),
      findsOneWidget,
    );
  });
}
