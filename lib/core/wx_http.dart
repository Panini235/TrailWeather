import 'dart:math' as math;

import 'package:dio/dio.dart';

/// 数据源 HTTP 异常：携带状态码，供 UI 如实展示“来源失败/限流”。
class SourceHttpException implements Exception {
  final int? statusCode;
  final String message;
  final String endpoint; // 仅记录端点主机+路径，不记录坐标等敏感查询参数

  SourceHttpException(this.statusCode, this.message, this.endpoint);

  @override
  String toString() => 'SourceHttpException($statusCode, $message, $endpoint)';
}

/// 统一 HTTP 客户端：
/// - 超时控制；
/// - 429/5xx 指数退避重试（尊重 Retry-After，不换端点规避配额）；
/// - CancelToken 取消；
/// - 异常中不携带坐标查询串，避免把用户浏览位置写进日志。
class WxHttp {
  WxHttp({Dio? dio, this.maxRetries = 2})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              sendTimeout: const Duration(seconds: 15),
              validateStatus: (_) => true, // 统一自行判断状态码
              responseType: ResponseType.plain,
            ),
          );

  final Dio _dio;
  final int maxRetries;

  Future<String> getText(
    Uri uri, {
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      final resp = await _dio.getUri<String>(
        uri,
        options: Options(headers: headers, responseType: ResponseType.plain),
        cancelToken: cancelToken,
      );
      final code = resp.statusCode ?? 0;
      if (code >= 200 && code < 300) {
        return resp.data ?? '';
      }
      final retriable =
          code == 429 || code == 502 || code == 503 || code == 504;
      if (retriable && attempt <= maxRetries) {
        var delayMs = 500 * math.pow(2, attempt - 1).toDouble();
        final retryAfter = resp.headers.value('retry-after');
        final ra = retryAfter == null ? null : int.tryParse(retryAfter);
        if (ra != null && ra > 0) delayMs = (ra * 1000).toDouble();
        await Future<void>.delayed(Duration(milliseconds: delayMs.toInt()));
        continue;
      }
      throw SourceHttpException(code, 'HTTP $code', '${uri.host}${uri.path}');
    }
  }
}
