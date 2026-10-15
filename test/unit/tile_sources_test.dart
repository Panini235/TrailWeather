import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/map/tile_sources.dart';
import 'package:trailweather/data/settings/settings_repository.dart';

TileSourceDef _src(String id) =>
    builtInTileSources.firstWhere((s) => s.id == id);

void main() {
  group('resolveMapStyle', () {
    test('天地图缺 Key 时回退默认底图并说明原因', () {
      final style = resolveMapStyle(
        baseLayerId: 'tianditu_img',
        overlays: const [],
        custom: const [],
        tiandituKey: '',
      );
      expect(style.base.id, defaultBaseLayerId);
      expect(style.baseFallbackReason, contains('天地图 Key'));
    });

    test('填写 Key 后模板替换 {tk}，并保留叠加顺序与透明度', () {
      final style = resolveMapStyle(
        baseLayerId: 'tianditu_img',
        overlays: const [
          OverlaySelection('tianditu_cia', opacity: 0.8),
          OverlaySelection('opentopomap', opacity: 0.4),
        ],
        custom: const [],
        tiandituKey: 'abc 123',
      );
      expect(style.base.id, 'tianditu_img');
      expect(style.baseFallbackReason, isNull);
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
        tiandituKey: '',
      );
      expect([for (final o in style.overlays) o.$1.id], ['amap_labels']);
    });

    test('注记层与已删除来源不能作底图', () {
      expect(
        resolveMapStyle(
          baseLayerId: 'amap_labels',
          overlays: const [],
          custom: const [],
          tiandituKey: '',
        ).base.id,
        defaultBaseLayerId,
      );
      expect(
        resolveMapStyle(
          baseLayerId: 'custom_gone',
          overlays: const [],
          custom: const [],
          tiandituKey: '',
        ).baseFallbackReason,
        isNotNull,
      );
    });
  });

  test('overlayBlockReason', () {
    final amap = _src('amap');
    expect(
      overlayBlockReason(amap, _src('opentopomap'), tiandituKey: ''),
      contains('坐标系'),
    );
    expect(
      overlayBlockReason(_src('osm'), _src('tianditu_cva'), tiandituKey: ''),
      contains('天地图 Key'),
    );
    expect(
      overlayBlockReason(_src('osm'), _src('tianditu_cva'), tiandituKey: 'k'),
      isNull,
    );
    expect(overlayBlockReason(amap, amap, tiandituKey: ''), isNotNull);
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
        tiandituKey: 'k',
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.baseLayerId, 'osm');
      expect(back.overlayLayers, const [
        OverlaySelection('custom_1', opacity: 0.5),
      ]);
      expect(back.tiandituKey, 'k');
      final c = back.customTileSources.single;
      expect(c.datum, TileDatum.gcj02);
      expect(c.subdomains, ['a', 'b']);
      expect(c.maxNativeZoom, 16);
      expect(c.overlayOnly, isTrue);
      expect(c.builtIn, isFalse);
    });
  });
}
