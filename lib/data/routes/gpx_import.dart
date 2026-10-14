import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import '../../core/geo.dart';
import 'route_models.dart';

/// GPX 导入结果。
class GpxParseResult {
  const GpxParseResult({
    required this.segments,
    required this.elevations,
    required this.warnings,
    this.extractedName,
  });

  final List<List<LatLng>> segments;
  final List<double?> elevations;
  final List<String> warnings;
  final String? extractedName;
}

class GpxImport {
  static const maxInputBytes = 30 * 1024 * 1024; // 30 MB
  static const autoSimplifyThreshold = 3000; // 点数超过此阈值触发自适应抽稀

  /// 解析 GPX（XML）。
  ///
  /// 安全与容错说明：
  /// - 纯 Dart XML 解析器，防 XXE；
  /// - 自动过滤 UTF-8 BOM 字符；
  /// - 忽略 XML 命名空间前缀，兼容各家设备自定标签；
  /// - 坐标合法性校验（纬度 [-90,90]，经度 [-180,180]）；
  /// - 异常海拔不拒绝文件，置为 null 并提示（符合真实性红线）；
  /// - 大点数自动进行 Douglas-Peucker 自适应抽稀，保留峰顶、山谷及关键转向；
  /// - 支持 `<trk>`、`<rte>`，并在缺少连续轨迹时自动将 `<wpt>` 航点集合成为航线。
  static GpxParseResult parse(
    String input, {
    List<String> warnings = const [],
  }) {
    final warns = List<String>.of(warnings);
    if (input.length > maxInputBytes) {
      throw const GpxImportException('文件超过 30 MB 大小限制');
    }

    // 剔除前导空白与 UTF-8 BOM 头
    var cleanInput = input.trimLeft();
    if (cleanInput.startsWith('\uFEFF')) {
      cleanInput = cleanInput.substring(1).trimLeft();
    }

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(cleanInput);
    } on XmlException catch (e) {
      throw GpxImportException('XML 解析失败：${e.message}');
    }

    final root = doc.rootElement;
    if (root.name.local.toLowerCase() != 'gpx') {
      throw GpxImportException('不是 GPX 文件（根元素为 ${root.name.local}）');
    }

    // 提取全局线路名称
    String? trackName;
    for (final child in root.children.whereType<XmlElement>()) {
      if (child.name.local == 'metadata') {
        final nameEl = child.children
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'name')
            .firstOrNull;
        if (nameEl != null && nameEl.innerText.trim().isNotEmpty) {
          trackName = nameEl.innerText.trim();
        }
      }
    }

    final segments = <List<LatLng>>[];
    final elevations = <double?>[];

    void takePoints(Iterable<XmlElement> pts) {
      final seg = <LatLng>[];
      final segEle = <double?>[];
      for (final p in pts) {
        final local = p.name.local.toLowerCase();
        if (local != 'trkpt' && local != 'rtept' && local != 'wpt') continue;
        final lat = double.tryParse(p.getAttribute('lat') ?? '');
        final lon = double.tryParse(p.getAttribute('lon') ?? '');
        if (lat == null || lon == null) continue;
        if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
          warns.add('已跳过超出合法范围的坐标点 ($lat, $lon)');
          continue;
        }

        final eleChild = p.children
            .whereType<XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'ele')
            .firstOrNull;
        final ele = eleChild == null
            ? null
            : double.tryParse(eleChild.innerText.trim());
        if (ele != null && (ele < -500 || ele > 10000)) {
          warns.add('发现异常海拔数据 (${ele.toStringAsFixed(1)}m)，已自动过滤置空');
          segEle.add(null);
        } else {
          segEle.add(ele);
        }

        final timeChild = p.children
            .whereType<XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'time')
            .firstOrNull;
        if (timeChild != null &&
            DateTime.tryParse(timeChild.innerText.trim()) == null) {
          warns.add('存在无法解析的时间字段，已忽略');
        }

        seg.add(LatLng(lat, lon));
      }

      if (seg.length >= 2) {
        segments.add(seg);
        elevations.addAll(segEle);
      }
    }

    // 1. 尝试读取 <trk><trkseg><trkpt>
    for (final trk in root.children.whereType<XmlElement>().where(
      (e) => e.name.local == 'trk',
    )) {
      if (trackName == null) {
        final nameEl = trk.children
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'name')
            .firstOrNull;
        if (nameEl != null && nameEl.innerText.trim().isNotEmpty) {
          trackName = nameEl.innerText.trim();
        }
      }
      for (final seg in trk.children.whereType<XmlElement>().where(
        (e) => e.name.local == 'trkseg',
      )) {
        takePoints(seg.children.whereType<XmlElement>());
      }
    }

    // 2. 尝试读取 <rte><rtept>
    if (segments.isEmpty) {
      for (final rte in root.children.whereType<XmlElement>().where(
        (e) => e.name.local == 'rte',
      )) {
        if (trackName == null) {
          final nameEl = rte.children
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'name')
              .firstOrNull;
          if (nameEl != null && nameEl.innerText.trim().isNotEmpty) {
            trackName = nameEl.innerText.trim();
          }
        }
        takePoints(rte.children.whereType<XmlElement>());
      }
    }

    // 3. 容错尝试读取分散的 <wpt>
    if (segments.isEmpty) {
      final wpts = root.children
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'wpt')
          .toList();
      if (wpts.length >= 2) {
        takePoints(wpts);
        if (segments.isNotEmpty) {
          warns.add('文件中未发现轨迹段，已将 ${wpts.length} 个航点 (wpt) 合成为路线');
        }
      }
    }

    var totalPoints = segments.fold<int>(0, (a, s) => a + s.length);
    if (segments.isEmpty || totalPoints < 2) {
      throw const GpxImportException('未找到有效轨迹点（trkpt/rtept/wpt 至少需要 2 个有效点）');
    }

    // 4. 自适应抽稀（若点数超大，自动优化以保障渲染流畅与气象推演）
    var finalSegments = segments;
    var finalElevations = elevations;
    if (totalPoints > autoSimplifyThreshold) {
      final newSegs = <List<LatLng>>[];
      final newEles = <double?>[];
      var eleOffset = 0;
      for (final seg in segments) {
        final segElevations = elevations.sublist(
          eleOffset,
          eleOffset + seg.length,
        );
        eleOffset += seg.length;
        if (seg.length > 500) {
          final targetPts = (seg.length / totalPoints * autoSimplifyThreshold)
              .round()
              .clamp(300, 3000);
          final (simpPts, simpEles) = Geo.simplifyTrack(
            seg,
            segElevations,
            targetMaxPoints: targetPts,
          );
          newSegs.add(simpPts);
          newEles.addAll(simpEles);
        } else {
          newSegs.add(seg);
          newEles.addAll(segElevations);
        }
      }
      final newTotal = newSegs.fold<int>(0, (a, s) => a + s.length);
      warns.add(
        '原始轨迹含 $totalPoints 个点，已自适应优化至 $newTotal 点（保留峰顶与关键转折），保障流畅显示与气象推演',
      );
      finalSegments = newSegs;
      finalElevations = newEles;
    }

    return GpxParseResult(
      segments: finalSegments,
      elevations: finalElevations,
      warnings: warns,
      extractedName: trackName,
    );
  }

  /// 从解析结果构造 HikingRoute（用户导入）。
  static HikingRoute toRoute(GpxParseResult r, {required String fileName}) {
    return HikingRoute(
      id: 'import-${DateTime.now().millisecondsSinceEpoch}',
      name: r.extractedName ?? _guessName(fileName),
      origin: RouteOrigin.import,
      segments: r.segments,
      elevationsM: r.elevations,
      sourceName: '用户导入 GPX：$fileName',
      importedAtUtc: DateTime.now().toUtc(),
    );
  }

  static String _guessName(String fileName) {
    final base = fileName.split('/').last.split(r'\').last;
    final dotIdx = base.lastIndexOf('.');
    final noExt = dotIdx > 0 ? base.substring(0, dotIdx) : base;
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
