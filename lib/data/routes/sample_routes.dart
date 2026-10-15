import 'package:flutter/services.dart' show rootBundle;

import 'gpx_import.dart';
import 'route_models.dart';

/// 内置示例线路（assets/routes/*.gpx）。
///
/// 这些是演示数据：真实地理区域的“走向示意”轨迹，几何与海拔均为演示。
/// isDemo=true，UI 必须持续显示“演示”标签，不得与真实数据混淆。
class SampleRoutes {
  static const assets = [
    'assets/routes/demo_beijing_xiangshan.gpx',
    'assets/routes/demo_hangzhou_westlake.gpx',
    'assets/routes/demo_shenzhen_dapeng.gpx',
  ];

  Future<List<HikingRoute>> loadAll() async {
    final out = <HikingRoute>[];
    for (var i = 0; i < assets.length; i++) {
      try {
        final raw = await rootBundle.loadString(assets[i]);
        final parsed = GpxImport.parse(raw);
        final route = GpxImport.toRoute(parsed, fileName: assets[i]);
        final descName = _demoName(i);
        out.add(
          HikingRoute(
            id: 'demo-$i',
            name: descName,
            origin: RouteOrigin.demo,
            segments: route.segments,
            elevationsM: route.elevationsM,
            sourceName: '内置示例（演示数据，非实测线路）',
            isDemo: true,
          ),
        );
      } catch (_) {
        // 单个演示资源损坏不影响其余加载。
      }
    }
    return out;
  }

  String _demoName(int i) => switch (i) {
    0 => '香山—八大处穿越（示例）',
    1 => '西湖群山环线（示例）',
    2 => '大鹏半岛海岸线（示例）',
    _ => '示例线路 $i',
  };
}
