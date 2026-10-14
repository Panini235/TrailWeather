import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import '../../core/geo.dart';
import 'route_models.dart';

/// KML 导入结果。
class KmlParseResult {
  const KmlParseResult({
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

/// KML（Keyhole Markup Language，奥维互动地图、两步路、Google Earth 常用格式）解析器。
class KmlImport {
  static const maxInputBytes = 30 * 1024 * 1024; // 30 MB
  static const autoSimplifyThreshold = 3000;

  /// 解析 KML 文本内容。
  static KmlParseResult parse(
    String input, {
    List<String> warnings = const [],
  }) {
    final warns = List<String>.of(warnings);
    if (input.length > maxInputBytes) {
      throw const KmlImportException('文件超过 30 MB 大小限制');
    }

    var cleanInput = input.trimLeft();
    if (cleanInput.startsWith('\uFEFF')) {
      cleanInput = cleanInput.substring(1).trimLeft();
    }

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(cleanInput);
    } on XmlException catch (e) {
      throw KmlImportException('KML (XML) 解析失败：${e.message}');
    }

    final root = doc.rootElement;
    if (root.name.local.toLowerCase() != 'kml') {
      throw KmlImportException('不是 KML 文件（根元素为 ${root.name.local}）');
    }

    String? routeName;
    // 尝试从 Document 或 Folder 提取名称
    for (final docChild in root.descendants.whereType<XmlElement>()) {
      final local = docChild.name.local.toLowerCase();
      if ((local == 'document' || local == 'folder') && routeName == null) {
        final nameEl = docChild.children
            .whereType<XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'name')
            .firstOrNull;
        if (nameEl != null && nameEl.innerText.trim().isNotEmpty) {
          routeName = nameEl.innerText.trim();
        }
      }
    }

    final segments = <List<LatLng>>[];
    final elevations = <double?>[];

    // 辅助解析 coordinates 文本块（格式：lon,lat[,alt] 空白分隔）
    void parseCoordinatesText(String text) {
      final seg = <LatLng>[];
      final segEle = <double?>[];

      final tokens = text.trim().split(RegExp(r'\s+'));
      for (final t in tokens) {
        if (t.isEmpty) continue;
        final parts = t.split(',');
        if (parts.length < 2) continue;
        final lon = double.tryParse(parts[0].trim());
        final lat = double.tryParse(parts[1].trim());
        if (lon == null || lat == null) continue;
        if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
          warns.add('已跳过超出合法范围的坐标点 ($lat, $lon)');
          continue;
        }

        double? ele;
        if (parts.length >= 3) {
          final rawEle = double.tryParse(parts[2].trim());
          if (rawEle != null) {
            if (rawEle < -500 || rawEle > 10000) {
              warns.add('发现异常海拔数据 (${rawEle.toStringAsFixed(1)}m)，已自动过滤置空');
              ele = null;
            } else {
              ele = rawEle;
            }
          }
        }

        seg.add(LatLng(lat, lon));
        segEle.add(ele);
      }

      if (seg.length >= 2) {
        segments.add(seg);
        elevations.addAll(segEle);
      }
    }

    // 1. 查找所有 Placemark
    final placemarks = root.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'placemark')
        .toList();

    for (final pm in placemarks) {
      if (routeName == null) {
        final nameEl = pm.children
            .whereType<XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'name')
            .firstOrNull;
        if (nameEl != null && nameEl.innerText.trim().isNotEmpty) {
          routeName = nameEl.innerText.trim();
        }
      }

      // LineString
      final lineStrings = pm.descendants.whereType<XmlElement>().where(
        (e) => e.name.local.toLowerCase() == 'linestring',
      );
      for (final ls in lineStrings) {
        final coordEl = ls.children
            .whereType<XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'coordinates')
            .firstOrNull;
        if (coordEl != null) {
          parseCoordinatesText(coordEl.innerText);
        }
      }

      // gx:Track (Google Earth / 奥维扩展格式)
      final tracks = pm.descendants.whereType<XmlElement>().where(
        (e) => e.name.local.toLowerCase() == 'track',
      );
      for (final trk in tracks) {
        final seg = <LatLng>[];
        final segEle = <double?>[];
        for (final coordEl in trk.children.whereType<XmlElement>().where(
          (e) => e.name.local.toLowerCase() == 'coord',
        )) {
          final parts = coordEl.innerText.trim().split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final lon = double.tryParse(parts[0]);
            final lat = double.tryParse(parts[1]);
            final ele = parts.length >= 3 ? double.tryParse(parts[2]) : null;
            if (lat != null &&
                lon != null &&
                lat >= -90 &&
                lat <= 90 &&
                lon >= -180 &&
                lon <= 180) {
              seg.add(LatLng(lat, lon));
              segEle.add(
                ele != null && ele >= -500 && ele <= 10000 ? ele : null,
              );
            }
          }
        }
        if (seg.length >= 2) {
          segments.add(seg);
          elevations.addAll(segEle);
        }
      }
    }

    // 2. 容错：如果未在 Placemark 中找到，全局查找所有 coordinates 元素
    if (segments.isEmpty) {
      final allCoords = root.descendants.whereType<XmlElement>().where(
        (e) => e.name.local.toLowerCase() == 'coordinates',
      );
      for (final c in allCoords) {
        parseCoordinatesText(c.innerText);
      }
    }

    final totalPoints = segments.fold<int>(0, (a, s) => a + s.length);
    if (segments.isEmpty || totalPoints < 2) {
      throw const KmlImportException('未在 KML 文件中找到有效线段轨迹（至少需要 2 个有效坐标点）');
    }

    // 3. 自适应抽稀
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
        '原始 KML 轨迹含 $totalPoints 个点，已自适应优化至 $newTotal 点（保留峰顶与关键转折），保障流畅显示与气象推演',
      );
      finalSegments = newSegs;
      finalElevations = newEles;
    }

    return KmlParseResult(
      segments: finalSegments,
      elevations: finalElevations,
      warnings: warns,
      extractedName: routeName,
    );
  }

  /// 从解析结果构造 HikingRoute。
  static HikingRoute toRoute(KmlParseResult r, {required String fileName}) {
    return HikingRoute(
      id: 'import-${DateTime.now().millisecondsSinceEpoch}',
      name: r.extractedName ?? _guessName(fileName),
      origin: RouteOrigin.import,
      segments: r.segments,
      elevationsM: r.elevations,
      sourceName: '用户导入 KML：$fileName',
      importedAtUtc: DateTime.now().toUtc(),
    );
  }

  static String _guessName(String fileName) {
    final base = fileName.split('/').last.split(r'\').last;
    final dotIdx = base.lastIndexOf('.');
    final noExt = dotIdx > 0 ? base.substring(0, dotIdx) : base;
    return noExt.isEmpty ? '导入 KML 线路' : noExt;
  }
}

class KmlImportException implements Exception {
  const KmlImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
