import 'dart:io';

/// 所有经 dart:io HttpClient 的请求（dio、http、网络图片与地图瓦片）走 [proxy]。
void installDevProxy(String proxy) {
  HttpOverrides.global = _DevProxy(proxy);
}

class _DevProxy extends HttpOverrides {
  _DevProxy(this.proxy);

  final String proxy;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'PROXY $proxy';
}
