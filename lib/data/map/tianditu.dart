/// 天地图瓦片错误识别。
///
/// flutter_map 8 的 `errorTileCallback` 只拿到 `NetworkImageLoadException`
/// （状态码 + URL），拿不到响应体；天地图把“Key 无效 / Key 类型不符”都放在
/// 403 的 JSON 里。因此给天地图图层的 `NetworkTileProvider` 传入
/// [TiandituErrorSniffingClient]：只在天地图域名的错误响应上读取响应体、按
/// code 分类并上报，再把同样的字节原样交回 flutter_map。
///
/// 2026-10-15 实测（docs/data-sources.md「天地图」）：
/// - 301001 非法 key；
/// - 301012 浏览器端 Key 被非浏览器请求使用（UA 不含 Mozilla）；
/// - 301013 服务端 Key 被浏览器请求使用（UA 含 Mozilla）；
/// - Key 格式异常时返回 418 防火墙拦截页（HTML，不是 JSON）。
/// 403 响应带 `Access-Control-Allow-Origin: *`，Web 端也能读到响应体。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

enum TiandituErrorKind {
  /// 301001：Key 不存在或已失效。
  invalidKey,

  /// 301012：浏览器端 Key 用在了非浏览器请求（原生 App）。
  browserKeyNotInBrowser,

  /// 301013：服务端 Key 用在了浏览器请求（Web / WebView）。
  serverKeyInBrowser,

  /// 418 防火墙拦截页。
  blocked,

  /// 其他错误状态或无法识别的响应体。
  other,
}

class TiandituTileError {
  const TiandituTileError({
    required this.kind,
    required this.statusCode,
    this.code,
    this.key = '',
  });

  final TiandituErrorKind kind;
  final int statusCode;

  /// 响应 JSON 中的 code；非 JSON 时为 null。
  final int? code;

  /// 出错请求所带的 tk。仅在内存中用于判断提示是否已过期（用户改了 Key），
  /// 不持久化、不展示。
  final String key;
}

bool isTiandituUrl(Uri url) =>
    url.host == 'tianditu.gov.cn' || url.host.endsWith('.tianditu.gov.cn');

/// 把天地图响应分类；不是天地图请求或不是错误状态（如 200/304）时返回 null。
TiandituTileError? classifyTiandituResponse({
  required Uri url,
  required int statusCode,
  required List<int> body,
}) {
  if (statusCode < 400 || !isTiandituUrl(url)) return null;
  final key = url.queryParameters['tk'] ?? '';
  int? code;
  try {
    final json = jsonDecode(utf8.decode(body, allowMalformed: true));
    final c = json is Map<String, dynamic> ? json['code'] : null;
    if (c is num) code = c.toInt();
  } on FormatException {
    // 非 JSON（如 418 拦截页 HTML），按状态码分类。
  }
  final kind = switch (code) {
    301001 => TiandituErrorKind.invalidKey,
    301012 => TiandituErrorKind.browserKeyNotInBrowser,
    301013 => TiandituErrorKind.serverKeyInBrowser,
    _ when statusCode == 418 => TiandituErrorKind.blocked,
    _ => TiandituErrorKind.other,
  };
  return TiandituTileError(
    kind: kind,
    statusCode: statusCode,
    code: code,
    key: key,
  );
}

/// 只读取天地图错误响应体的 http client 包装；其余响应原样透传（流式，不缓冲）。
class TiandituErrorSniffingClient extends http.BaseClient {
  TiandituErrorSniffingClient(this._inner, {required this.onError});

  final http.Client _inner;
  final void Function(TiandituTileError error) onError;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = await _inner.send(request);
    if (res.statusCode < 400 || !isTiandituUrl(request.url)) return res;
    final bytes = await res.stream.toBytes();
    final error = classifyTiandituResponse(
      url: request.url,
      statusCode: res.statusCode,
      body: bytes,
    );
    if (error != null) onError(error);
    return http.StreamedResponse(
      http.ByteStream.fromBytes(bytes),
      res.statusCode,
      contentLength: bytes.length,
      request: res.request,
      headers: res.headers,
      isRedirect: res.isRedirect,
      persistentConnection: res.persistentConnection,
      reasonPhrase: res.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

/// 最近一次天地图瓦片错误（仅内存）。同一错误只上报一次；用户关闭提示后，
/// 同一 Key 的同类错误不再弹出，换 Key 或出现新类型错误时再提示。
class TiandituErrorNotifier extends Notifier<TiandituTileError?> {
  ({TiandituErrorKind kind, String key})? _dismissed;

  @override
  TiandituTileError? build() => null;

  void report(TiandituTileError e) {
    final id = (kind: e.kind, key: e.key);
    if (id == _dismissed) return;
    final cur = state;
    if (cur != null && cur.kind == e.kind && cur.key == e.key) return;
    state = e;
  }

  void dismiss() {
    final cur = state;
    if (cur != null) _dismissed = (kind: cur.kind, key: cur.key);
    state = null;
  }
}

final tiandituErrorProvider =
    NotifierProvider<TiandituErrorNotifier, TiandituTileError?>(
      TiandituErrorNotifier.new,
    );

/// 天地图图层共用的 http client（与 flutter_map 默认一样外包 [RetryClient]）。
/// 由 flutter_map 外部传入的 client 不会被 TileLayer 关闭，生命周期跟随此 provider。
final tiandituTileClientProvider = Provider<http.Client>((ref) {
  final client = TiandituErrorSniffingClient(
    RetryClient(http.Client()),
    onError: (e) {
      if (ref.mounted) ref.read(tiandituErrorProvider.notifier).report(e);
    },
  );
  ref.onDispose(client.close);
  return client;
});
