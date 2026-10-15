import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'geojson_import.dart';
import 'gpx_import.dart';
import 'kml_import.dart';
import 'route_models.dart';

/// 统一导入结果：线路 + 去重后的提示。
class RouteImportResult {
  const RouteImportResult({required this.route, required this.warnings});

  final HikingRoute route;
  final List<String> warnings;
}

class RouteImportException implements Exception {
  const RouteImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 本地轨迹文件统一导入入口（GPX / KML / KMZ / GeoJSON）。
///
/// 按文件内容嗅探格式，不依赖扩展名：移动端文件选择器不按扩展名过滤
/// （Android 无 GPX MIME 映射、iOS 需 UTI），文件名可能是“xxx.kml 2”之类。
/// 纯函数、可在后台 isolate 运行（见 [importRouteFile]）。
class RouteFileImport {
  static const maxInputBytes = 30 * 1024 * 1024; // 30 MB
  static const _maxWarnings = 8;

  static RouteImportResult fromBytes(Uint8List bytes, String fileName) {
    if (bytes.length > maxInputBytes) {
      throw const RouteImportException('文件超过 30 MB 大小限制');
    }
    if (bytes.isEmpty) {
      throw const RouteImportException('文件为空');
    }
    if (_isZip(bytes)) {
      return fromText(_extractKmlFromKmz(bytes), fileName);
    }
    return fromText(utf8.decode(bytes, allowMalformed: true), fileName);
  }

  static RouteImportResult fromText(String content, String fileName) {
    var text = content.trimLeft();
    if (text.startsWith('﻿')) text = text.substring(1).trimLeft();
    if (text.isEmpty) {
      throw const RouteImportException('内容为空');
    }

    try {
      if (text.startsWith('<')) {
        final head = (text.length > 2000 ? text.substring(0, 2000) : text)
            .toLowerCase();
        if (head.contains('<kml')) return _kml(text, fileName);
        if (head.contains('<gpx')) return _gpx(text, fileName);
        // 根元素在长注释/声明之后：GPX 失败再试 KML
        try {
          return _gpx(text, fileName);
        } on GpxImportException {
          return _kml(text, fileName);
        }
      }
      if (text.startsWith('{') || text.startsWith('[')) {
        final route = GeoJsonImport.toRoute(text, fileName: fileName);
        return RouteImportResult(route: route, warnings: const []);
      }
    } on GpxImportException catch (e) {
      throw RouteImportException(e.message);
    } on KmlImportException catch (e) {
      throw RouteImportException(e.message);
    } on GeoJsonImportException catch (e) {
      throw RouteImportException(e.message);
    }
    throw const RouteImportException(
      '无法识别的文件格式。请选择 GPX、KML、KMZ 或 GeoJSON 轨迹文件。',
    );
  }

  static RouteImportResult _gpx(String text, String fileName) {
    final parsed = GpxImport.parse(text);
    return RouteImportResult(
      route: GpxImport.toRoute(parsed, fileName: fileName),
      warnings: _dedupe(parsed.warnings),
    );
  }

  static RouteImportResult _kml(String text, String fileName) {
    final parsed = KmlImport.parse(text);
    return RouteImportResult(
      route: KmlImport.toRoute(parsed, fileName: fileName),
      warnings: _dedupe(parsed.warnings),
    );
  }

  static bool _isZip(Uint8List b) =>
      b.length >= 4 &&
      b[0] == 0x50 &&
      b[1] == 0x4B &&
      b[2] == 0x03 &&
      b[3] == 0x04;

  /// KMZ = zip(doc.kml + 资源)。优先根目录 doc.kml，否则取第一个 .kml。
  static String _extractKmlFromKmz(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw RouteImportException('压缩包解析失败（KMZ 已损坏或不是 zip）：$e');
    }
    final kmls = archive.files
        .where((f) => f.isFile && f.name.toLowerCase().endsWith('.kml'))
        .toList();
    if (kmls.isEmpty) {
      throw const RouteImportException('KMZ 中未找到 .kml 文件');
    }
    final doc = kmls.firstWhere(
      (f) => f.name.toLowerCase() == 'doc.kml',
      orElse: () => kmls.first,
    );
    final data = doc.readBytes();
    if (data == null || data.length > maxInputBytes) {
      throw const RouteImportException('KMZ 内 KML 为空或解压后超过 30 MB');
    }
    return utf8.decode(data, allowMalformed: true);
  }

  /// 逐点告警（如每个异常海拔一条）合并计数，避免刷屏。
  static List<String> _dedupe(List<String> warnings) {
    final counts = <String, int>{};
    for (final w in warnings) {
      counts[w] = (counts[w] ?? 0) + 1;
    }
    final out = [
      for (final e in counts.entries)
        e.value > 1 ? '${e.key}（共 ${e.value} 处）' : e.key,
    ];
    if (out.length > _maxWarnings) {
      final rest = out.length - _maxWarnings;
      return [...out.take(_maxWarnings), '另有 $rest 类提示未显示'];
    }
    return out;
  }
}

/// isolate 入口参数（compute 只接受单参数）。
typedef RouteFileInput = ({Uint8List bytes, String fileName});

RouteImportResult importRouteFile(RouteFileInput input) =>
    RouteFileImport.fromBytes(input.bytes, input.fileName);
