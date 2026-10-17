import 'package:flutter/foundation.dart';

import 'dev_proxy_stub.dart' if (dart.library.io) 'dev_proxy_io.dart' as impl;

/// 真机调试用的 HTTP 代理（只在 debug / profile 构建生效，默认关闭）。
///
/// 调试手机没有网络时：`adb reverse tcp:7897 tcp:7897` 把手机上的 127.0.0.1:7897
/// 转到电脑上的代理，构建时传 `--dart-define=SHANQING_DEV_PROXY=127.0.0.1:7897`。
/// 只影响本 App 发出的请求，不改手机系统设置；release 构建忽略此项。
const String kDevProxy = String.fromEnvironment('SHANQING_DEV_PROXY');

void installDevProxy() {
  if (kDevProxy.isEmpty || kReleaseMode) return;
  impl.installDevProxy(kDevProxy);
}
