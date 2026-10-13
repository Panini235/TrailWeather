import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../core/wx_http.dart';
import 'weather_models.dart';

/// 可注入的字符串抓取器：生产用 WxHttp，测试用 fixture。
typedef StringFetcher = Future<String> Function(
  Uri uri, {
  Map<String, String>? headers,
  CancelToken? cancelToken,
});

StringFetcher defaultFetcher() => (uri, {headers, cancelToken}) =>
    WxHttp().getText(uri, headers: headers, cancelToken: cancelToken);

/// 天气来源抽象。每个实现必须：
/// 1. 如实声明能力（ProviderCapabilities）；
/// 2. 返回带完整溯源（WxProvenance）的数据；
/// 3. 不虚构缺失字段（保持 null）；
/// 4. 不在日志/异常中携带坐标。
abstract class WeatherProvider {
  WeatherProvider({StringFetcher? fetcher}) : fetcher = fetcher ?? defaultFetcher();

  final StringFetcher fetcher;

  ProviderCapabilities get caps;

  /// 抓取多个坐标在 [startUtc, endUtc] 的逐时数据。
  /// 实现负责：分批、最小请求间隔、范围裁剪。
  Future<List<WxPointForecast>> fetchPoints({
    required List<LatLng> points,
    required DateTime startUtc,
    required DateTime endUtc,
    CancelToken? cancelToken,
  });
}

/// 范围外结果：请求时间超出来源真实支持的时间范围。
/// UI 显示“此来源暂无该日期数据”，不外推、不用历史值冒充。
class WxOutOfRange implements Exception {
  final String message;
  WxOutOfRange(this.message);
  @override
  String toString() => 'WxOutOfRange: $message';
}
