import 'package:dio/dio.dart';

/// 探测一个地址是否可用：返回 HTTP 状态码，网络错误返回 0。
typedef UriProbe = Future<int> Function(Uri uri);

UriProbe defaultProbe() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      validateStatus: (_) => true,
    ),
  );
  return (uri) async {
    try {
      final r = await dio.headUri<void>(uri);
      return r.statusCode ?? 0;
    } catch (_) {
      return 0;
    }
  };
}

/// 卫星云图（观测，D-035）：日本 Himawari-9 红外 13 通道（10.4 µm），经 NASA GIBS 提供。
///
/// - 2026-10-17 实测国内直连可用（单块瓦片约 0.7 s）；最大原生级别 6（约 2 km）；
/// - 约 10 分钟一张，有 20–40 分钟延迟，偶有缺失时次（返回 404）；
/// - 用法要求：注明 NASA GIBS；Himawari 数据来自日本气象厅。
class SatelliteFrameService {
  SatelliteFrameService({UriProbe? probe, DateTime Function()? now})
    : _probe = probe ?? defaultProbe(),
      _now = now ?? (() => DateTime.now().toUtc());

  final UriProbe _probe;
  final DateTime Function() _now;

  static const layer = 'Himawari_AHI_Band13_Clean_Infrared';
  static const maxNativeZoom = 6;

  /// 回看 2 小时内的全部时次（约 10 分钟一张，最多 13 帧）：相邻两帧只差 10 分钟，
  /// 播放时交叉淡入才连贯。
  static const lookback = Duration(hours: 2);

  static String _iso(DateTime t) =>
      '${t.toUtc().toIso8601String().substring(0, 19)}Z';

  static String tileTemplate(DateTime t) =>
      'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/$layer/default/'
      '${_iso(t)}/GoogleMapsCompatible_Level6/{z}/{y}/{x}.png';

  /// 探测用瓦片：z2 覆盖东亚（经度 90–180°，纬度 0–66°）。
  static Uri probeUri(DateTime t) =>
      Uri.parse(tileTemplate(t).replaceFirst('{z}/{y}/{x}', '2/1/3'));

  /// 最近可用的若干帧（升序）。并行探测每 10 分钟的时次（多探 30 分钟，
  /// 因为最新时次常有 20–40 分钟延迟），只返回真实存在的时次；缺失的时次直接跳过，
  /// 不拿相邻时次顶替。一张都没有时返回空列表。
  Future<List<DateTime>> recentFrames() async {
    final now = _now();
    final end = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute - now.minute % 10,
    ).subtract(const Duration(minutes: 10));
    final slots = [
      for (var m = 0; m <= lookback.inMinutes + 30; m += 10)
        end.subtract(Duration(minutes: m)),
    ];
    final codes = await Future.wait(slots.map((t) => _probe(probeUri(t))));
    final ok = [
      for (var i = 0; i < slots.length; i++)
        if (codes[i] == 200) slots[i],
    ];
    if (ok.isEmpty) return const [];
    final latest = ok.first;
    return [
      for (final t in ok.reversed)
        if (latest.difference(t) <= lookback) t,
    ];
  }
}
