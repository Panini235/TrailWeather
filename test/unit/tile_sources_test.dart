import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/map/tile_sources.dart';
import 'package:trailweather/data/settings/settings_repository.dart';

TileSourceDef _src(String id) =>
    builtInTileSources.firstWhere((s) => s.id == id);

// 假 Key（不是真实 Key），测试不访问网络。
const _server = 'fake-server-key';
const _browser = 'fake-browser-key';
const _both = TiandituKeys(server: _server, browser: _browser);
const _none = TiandituKeys();
const _native = TileRequester.nativeApp;

void main() {
  group('resolveMapStyle', () {
    test('天地图缺 Key 时回退默认底图并说明缺哪一种 Key', () {
      final style = resolveMapStyle(
        baseLayerId: 'tianditu_img',
        overlays: const [],
        custom: const [],
        tiandituKeys: _none,
        requester: _native,
      );
      expect(style.base.id, defaultBaseLayerId);
      expect(style.baseFallbackReason, contains('天地图服务端 Key'));
      expect(style.usesTianditu, isFalse);
    });

    test('只填了另一端的 Key 也算缺失（不跨端借用）', () {
      final nativeOnlyBrowser = resolveMapStyle(
        baseLayerId: 'tianditu_vec',
        overlays: const [],
        custom: const [],
        tiandituKeys: const TiandituKeys(browser: _browser),
        requester: TileRequester.nativeApp,
      );
      expect(nativeOnlyBrowser.base.id, defaultBaseLayerId);
      expect(nativeOnlyBrowser.baseFallbackReason, contains('服务端'));

      final webOnlyServer = resolveMapStyle(
        baseLayerId: 'tianditu_vec',
        overlays: const [],
        custom: const [],
        tiandituKeys: const TiandituKeys(server: _server),
        requester: TileRequester.browser,
      );
      expect(webOnlyServer.base.id, defaultBaseLayerId);
      expect(webOnlyServer.baseFallbackReason, contains('浏览器端'));
    });

    test('按发起方选 Key：原生用服务端，浏览器用浏览器端', () {
      String template(TileRequester r) => resolveMapStyle(
        baseLayerId: 'tianditu_vec',
        overlays: const [OverlaySelection('tianditu_cva')],
        custom: const [],
        tiandituKeys: _both,
        requester: r,
      ).overlays.single.$2;
      expect(template(TileRequester.nativeApp), contains('tk=$_server'));
      expect(template(TileRequester.browser), contains('tk=$_browser'));
    });

    test('填写 Key 后模板替换 {tk}，并保留叠加顺序与透明度', () {
      final style = resolveMapStyle(
        baseLayerId: 'tianditu_img',
        overlays: const [
          OverlaySelection('tianditu_cia', opacity: 0.8),
          OverlaySelection('opentopomap', opacity: 0.4),
        ],
        custom: const [],
        tiandituKeys: const TiandituKeys(server: ' abc 123 '),
        requester: _native,
      );
      expect(style.base.id, 'tianditu_img');
      expect(style.baseFallbackReason, isNull);
      expect(style.usesTianditu, isTrue);
      expect(style.baseTemplate, contains('tk=abc+123'));
      expect(style.baseTemplate, isNot(contains('{tk}')));
      expect(
        [for (final o in style.overlays) o.$1.id],
        ['tianditu_cia', 'opentopomap'],
      );
      expect(style.overlays.last.$3, 0.4);
    });

    test('坐标系不同的叠加层被丢弃（不静默错位）', () {
      final style = resolveMapStyle(
        baseLayerId: 'amap_satellite',
        overlays: const [
          OverlaySelection('amap_labels'),
          OverlaySelection('opentopomap'),
        ],
        custom: const [],
        tiandituKeys: _none,
        requester: _native,
      );
      expect([for (final o in style.overlays) o.$1.id], ['amap_labels']);
    });

    test('注记层与已删除来源不能作底图', () {
      expect(
        resolveMapStyle(
          baseLayerId: 'amap_labels',
          overlays: const [],
          custom: const [],
          tiandituKeys: _none,
          requester: _native,
        ).base.id,
        defaultBaseLayerId,
      );
      expect(
        resolveMapStyle(
          baseLayerId: 'custom_gone',
          overlays: const [],
          custom: const [],
          tiandituKeys: _none,
          requester: _native,
        ).baseFallbackReason,
        isNotNull,
      );
    });
  });

  test('overlayBlockReason', () {
    final amap = _src('amap');
    String? reason(
      TileSourceDef base,
      TileSourceDef overlay, {
      TiandituKeys keys = _none,
      TileRequester requester = _native,
    }) => overlayBlockReason(
      base,
      overlay,
      tiandituKeys: keys,
      requester: requester,
    );
    expect(reason(amap, _src('opentopomap')), contains('坐标系'));
    expect(reason(_src('osm'), _src('tianditu_cva')), contains('天地图服务端 Key'));
    expect(
      reason(
        _src('osm'),
        _src('tianditu_cva'),
        requester: TileRequester.browser,
      ),
      contains('天地图浏览器端 Key'),
    );
    expect(reason(_src('osm'), _src('tianditu_cva'), keys: _both), isNull);
    expect(reason(amap, amap), isNotNull);
  });

  group('TiandituKeys', () {
    test('forRequester 去空白，未填返回空串', () {
      const keys = TiandituKeys(server: ' s ', browser: '');
      expect(keys.forRequester(TileRequester.nativeApp), 's');
      expect(keys.forRequester(TileRequester.browser), '');
    });

    test('两栏相同时提示（天地图 Key 只有一种应用类型）', () {
      expect(
        const TiandituKeys(server: 'k', browser: ' k').sameValueInBoth,
        isTrue,
      );
      expect(_both.sameValueInBoth, isFalse);
      expect(_none.sameValueInBoth, isFalse);
    });

    test('Web 平台判断在数据层：测试（VM）上为原生', () {
      expect(flutterMapRequester, TileRequester.nativeApp);
    });
  });

  group('validateCustomTemplate', () {
    test('合法模板', () {
      expect(
        validateCustomTemplate(
          'https://{s}.tile.example.com/{z}/{x}/{y}.png',
          subdomains: ['a', 'b'],
        ),
        isNull,
      );
      expect(
        validateCustomTemplate('https://t.example.com/{z}/{x}/{-y}.png'),
        isNull,
      );
    });

    test('非法模板给出原因', () {
      expect(validateCustomTemplate(''), isNotNull);
      expect(
        validateCustomTemplate('ftp://a.com/{z}/{x}/{y}'),
        contains('http'),
      );
      expect(
        validateCustomTemplate('https://a.com/{z}/{x}.png'),
        contains('{y}'),
      );
      expect(
        validateCustomTemplate('https://{s}.a.com/{z}/{x}/{y}'),
        contains('子域名'),
      );
      expect(
        validateCustomTemplate('https://a.com/{z}/{x}/{y}?k={key}'),
        contains('{key}'),
      );
    });
  });

  group('AppSettings 图层持久化', () {
    test('旧版 basemap 字段迁移为 baseLayerId', () {
      expect(AppSettings.fromJson({'basemap': 'osm'}).baseLayerId, 'osm');
      expect(AppSettings.fromJson({}).baseLayerId, defaultBaseLayerId);
    });

    test('旧版单一 tiandituKey 迁移到两栏', () {
      final s = AppSettings.fromJson({'tiandituKey': 'legacy-fake'});
      expect(s.tiandituServerKey, 'legacy-fake');
      expect(s.tiandituBrowserKey, 'legacy-fake');
      expect(s.tiandituKeys.sameValueInBoth, isTrue);
      // 迁移后保存不再写出旧字段；再读取以新字段为准。
      final json = s.copyWith(tiandituBrowserKey: '').toJson();
      expect(json.containsKey('tiandituKey'), isFalse);
      final back = AppSettings.fromJson(json);
      expect(back.tiandituServerKey, 'legacy-fake');
      expect(back.tiandituBrowserKey, '');
    });

    test('已有新字段时忽略残留的旧字段', () {
      final s = AppSettings.fromJson({
        'tiandituKey': 'legacy-fake',
        'tiandituServerKey': _server,
      });
      expect(s.tiandituServerKey, _server);
      expect(s.tiandituBrowserKey, '');
      expect(AppSettings.fromJson({}).tiandituKeys.forRequester(_native), '');
    });

    test('叠加层、自定义来源与天地图 Key 往返', () {
      const custom = TileSourceDef(
        id: 'custom_1',
        name: '我的图源',
        category: TileCategory.custom,
        urlTemplate: 'https://{s}.example.com/{z}/{x}/{y}.png',
        subdomains: ['a', 'b'],
        datum: TileDatum.gcj02,
        attribution: '© me',
        maxNativeZoom: 16,
        overlayOnly: true,
        builtIn: false,
      );
      final s = const AppSettings().copyWith(
        baseLayerId: 'osm',
        overlayLayers: const [OverlaySelection('custom_1', opacity: 0.5)],
        customTileSources: const [custom],
        tiandituServerKey: _server,
        tiandituBrowserKey: _browser,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.baseLayerId, 'osm');
      expect(back.overlayLayers, const [
        OverlaySelection('custom_1', opacity: 0.5),
      ]);
      expect(back.tiandituServerKey, _server);
      expect(back.tiandituBrowserKey, _browser);
      final c = back.customTileSources.single;
      expect(c.datum, TileDatum.gcj02);
      expect(c.subdomains, ['a', 'b']);
      expect(c.maxNativeZoom, 16);
      expect(c.overlayOnly, isTrue);
      expect(c.builtIn, isFalse);
    });
  });
}
