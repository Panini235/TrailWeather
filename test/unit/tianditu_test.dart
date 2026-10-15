import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trailweather/data/map/tianditu.dart';
import 'package:trailweather/ui/map/map_layers_ui.dart';
import 'package:trailweather/ui/strings.dart';

// 响应体照抄 2026-10-15 实测返回（docs/data-sources.md）；Key 均为假值，不访问网络。
const _body301001 = '{"resolve":"请到API控制台重新申请Key","code":301001,"msg":"非法key"}';
const _body301012 =
    '{"code":301012,"msg":"权限类型错误","resolve":"Key权限类型为:浏览器端，请使用浏览器访问！"}';
const _body301013 =
    '{"code":301013,"msg":"权限类型错误","resolve":"Key权限类型为:服务器端，请使用服务器端访问！"}';
const _body418 =
    '<!DOCTYPE html><html><head><title>访问被拦截！</title></head></html>';

Uri _tile([String tk = 'fake-key']) => Uri.parse(
  'https://t3.tianditu.gov.cn/DataServer?T=vec_w&x=843&y=388&l=10&tk=$tk',
);

TiandituTileError? _classify(int status, String body, {Uri? url}) =>
    classifyTiandituResponse(
      url: url ?? _tile(),
      statusCode: status,
      body: utf8.encode(body),
    );

void main() {
  group('classifyTiandituResponse', () {
    test('403 JSON 按 code 分类', () {
      expect(_classify(403, _body301001)!.kind, TiandituErrorKind.invalidKey);
      expect(
        _classify(403, _body301012)!.kind,
        TiandituErrorKind.browserKeyNotInBrowser,
      );
      final e = _classify(403, _body301013)!;
      expect(e.kind, TiandituErrorKind.serverKeyInBrowser);
      expect(e.code, 301013);
      expect(e.statusCode, 403);
    });

    test('记录出错请求的 tk（用于判断提示是否过期）', () {
      final e = _classify(403, _body301001, url: _tile('a b'))!;
      expect(e.key, 'a b');
    });

    test('418 拦截页（HTML）与无法识别的响应', () {
      final blocked = _classify(418, _body418)!;
      expect(blocked.kind, TiandituErrorKind.blocked);
      expect(blocked.code, isNull);
      final unknownCode = _classify(403, '{"code":309999,"msg":"x"}')!;
      expect(unknownCode.kind, TiandituErrorKind.other);
      expect(unknownCode.code, 309999);
      expect(_classify(500, '')!.kind, TiandituErrorKind.other);
      expect(
        _classify(403, '{"code":"301001"}')!.kind,
        TiandituErrorKind.other,
      );
    });

    test('成功响应与非天地图域名不算错误', () {
      expect(_classify(200, ''), isNull);
      expect(_classify(304, ''), isNull);
      expect(
        _classify(
          403,
          _body301001,
          url: Uri.parse('https://tile.openstreetmap.org/1/1/1.png'),
        ),
        isNull,
      );
      expect(isTiandituUrl(Uri.parse('https://t0.tianditu.gov.cn/x')), isTrue);
      expect(
        isTiandituUrl(Uri.parse('https://tianditu.gov.cn.evil.example/x')),
        isFalse,
      );
    });
  });

  group('TiandituErrorSniffingClient', () {
    test('天地图 403：上报错误码，并把相同字节交回调用方', () async {
      final reported = <TiandituTileError>[];
      final client = TiandituErrorSniffingClient(
        MockClient(
          (req) async => http.Response.bytes(
            utf8.encode(_body301012),
            403,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
        onError: reported.add,
      );
      final res = await client.get(_tile());
      expect(res.statusCode, 403);
      expect(res.body, _body301012);
      expect(res.bodyBytes, utf8.encode(_body301012));
      expect(reported.single.kind, TiandituErrorKind.browserKeyNotInBrowser);
      expect(reported.single.key, 'fake-key');
    });

    test('成功响应与其他图源的错误不读取、不上报', () async {
      final reported = <TiandituTileError>[];
      final client = TiandituErrorSniffingClient(
        MockClient(
          (req) async => req.url.host.contains('tianditu')
              ? http.Response.bytes([1, 2, 3], 200)
              : http.Response('nope', 403),
        ),
        onError: reported.add,
      );
      expect((await client.get(_tile())).bodyBytes, [1, 2, 3]);
      expect(
        (await client.get(Uri.parse('https://a.example.com/1/1/1.png')))
            .statusCode,
        403,
      );
      expect(reported, isEmpty);
    });
  });

  group('TiandituErrorNotifier', () {
    TiandituTileError err(TiandituErrorKind kind, String key) =>
        TiandituTileError(kind: kind, statusCode: 403, key: key);

    test('同类错误只上报一次；关闭后同 Key 同类不再提示，换 Key 再提示', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(tiandituErrorProvider.notifier);
      var notified = 0;
      c.listen(tiandituErrorProvider, (_, _) => notified++);

      n.report(err(TiandituErrorKind.invalidKey, 'k1'));
      n.report(err(TiandituErrorKind.invalidKey, 'k1'));
      expect(notified, 1);

      n.dismiss();
      expect(c.read(tiandituErrorProvider), isNull);
      n.report(err(TiandituErrorKind.invalidKey, 'k1'));
      expect(c.read(tiandituErrorProvider), isNull);

      n.report(err(TiandituErrorKind.invalidKey, 'k2'));
      expect(c.read(tiandituErrorProvider)!.key, 'k2');
      n.report(err(TiandituErrorKind.browserKeyNotInBrowser, 'k2'));
      expect(
        c.read(tiandituErrorProvider)!.kind,
        TiandituErrorKind.browserKeyNotInBrowser,
      );
    });
  });

  test('错误码 → 提示文案', () {
    String text(TiandituErrorKind kind, {int status = 403, int? code}) =>
        tiandituErrorText(
          TiandituTileError(kind: kind, statusCode: status, code: code),
        );
    expect(text(TiandituErrorKind.invalidKey), S.tiandituErrInvalidKey);
    expect(
      text(TiandituErrorKind.browserKeyNotInBrowser),
      S.tiandituErrBrowserKeyNotInBrowser,
    );
    expect(
      text(TiandituErrorKind.serverKeyInBrowser),
      S.tiandituErrServerKeyInBrowser,
    );
    expect(text(TiandituErrorKind.blocked, status: 418), S.tiandituErrBlocked);
    expect(
      text(TiandituErrorKind.other, status: 500),
      '${S.tiandituErrOther}（HTTP 500）',
    );
    expect(
      text(TiandituErrorKind.other, code: 309999),
      '${S.tiandituErrOther}（HTTP 403，code 309999）',
    );
  });
}
