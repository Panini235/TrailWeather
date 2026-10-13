import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import 'route_models.dart';

/// GPX 导入结果。
class GpxParseResult {
  const GpxParseResult({required this.segments, required this.elevations, required this.warnings});

  final List<List<LatLng>> segments;
  final List<double?> elevations;
  final List<String> warnings;
}

class GpxImport {
  static const maxInputBytes = 2 * 1024 * 1024; // 2 MB
  static const maxPoints = 5000;

  /// 解析 GPX（XML）。
  ///
  /// 安全说明：使用纯 Dart xml 包，不启用 DTD 处理与外部实体解析
  /// （XmlDocument.parse 默认不解析外部实体），防 XXE。
  /// 校验：根元素、坐标范围、点数、输入大小；时间字段仅校验格式。
  static GpxParseResult parse(String input, {List<String> warnings = const []}) {
    final warns = List<String>.of(warnings);
    if (input.length > maxInputBytes) {
      throw const GpxImportException('文件超过 2 MB 限制');
    }
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(input);
    } on XmlException catch (e) {
      throw GpxImportException('XML 解析失败：${e.message}');
    }
    final root = doc.rootElement;
    if (root.name.local != 'gpx') {
      throw GpxImportException('不是 GPX 文件（根元素为 ${root.name.local}）');
    }

    final segments = <List<LatLng>>[];
    final elevations = <double?>[];

    void takePoints(Iterable<XmlElement> pts) {
      final seg = <LatLng>[];
      final segEle = <double?>[];
      for (final p in pts) {
        if (p.name.local != 'trkpt' && p.name.local != 'rtept') continue;
        final lat = double.tryParse(p.getAttribute('lat') ?? '');
        final lon = double.tryParse(p.getAttribute('lon') ?? '');
        if (lat == null || lon == null) continue;
        if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
          throw const GpxImportException('存在超出范围的坐标（纬度需在 [-90,90]，经度 [-180,180]）');
        }
        final eleChild = p.findElements('ele').firstOrNull;
        final ele = eleChild == null ? null : double.tryParse(eleChild.innerText);
        if (ele != null && (ele < -500 || ele > 10000)) {
          throw const GpxImportException('存在异常海拔值（需在 -500..10000 m）');
        }
        final timeChild = p.findElements('time').firstOrNull;
        if (timeChild != null && DateTime.tryParse(timeChild.innerText) == null) {
          warns.add('存在无法解析的时间字段，已忽略');
        }
        seg.add(LatLng(lat, lon));
        segEle.add(ele);
      }
      if (seg.length >= 2) {
        segments.add(seg);
        elevations.addAll(segEle);
      }
    }

    for (final trk in root.findElements('trk')) {
      for (final seg in trk.findElements('trkseg')) {
        takePoints(seg.findElements('trkpt'));
      }
    }
    final rteList = root.findElements('rte').toList();
    for (final rte in rteList) {
      takePoints(rte.findElements('rtept'));
    }

    final totalPoints =
        segments.fold<int>(0, (a, s) => a + s.length);
    if (segments.isEmpty || totalPoints < 2) {
      throw const GpxImportException('未找到有效轨迹点（trkpt/rtept 至少 2 个）');
    }
    if (totalPoints > maxPoints) {
      throw GpxImportException('轨迹点数 $totalPoints 超过上限 $maxPoints');
    }
    return GpxParseResult(segments: segments, elevations: elevations, warnings: warns);
  }

  /// 从解析结果构造 HikingRoute（用户导入）。
  static HikingRoute toRoute(GpxParseResult r, {required String fileName}) {
    return HikingRoute(
      id: 'import-${DateTime.now().millisecondsSinceEpoch}',
      name: _guessName(fileName),
      origin: RouteOrigin.import,
      segments: r.segments,
      elevationsM: r.elevations,
      sourceName: '用户导入 GPX：$fileName',
      importedAtUtc: DateTime.now().toUtc(),
    );
  }

  static String _guessName(String fileName) {
    final base = fileName.split('/').last;
    final noExt = base.endsWith('.gpx') ? base.substring(0, base.length - 4) : base;
    return noExt.isEmpty ? '导入线路' : noExt;
  }
}

class GpxImportException implements Exception {
  const GpxImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
