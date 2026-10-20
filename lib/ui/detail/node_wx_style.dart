import 'package:flutter/material.dart';

import '../../data/weather/node_wx_class.dart';
import '../strings.dart';
import '../tokens.dart';

/// 颜色表示阈值级别（红/黄/提示/未触发/未知），图标表示天气类别。
Color nodeWxColor(NodeWxClass c) => switch (c.level) {
  NodeWxLevel.red => Semantic.danger,
  NodeWxLevel.yellow => Semantic.caution,
  NodeWxLevel.info => switch (c) {
    NodeWxClass.freezing => Semantic.ice,
    _ => Semantic.cold,
  },
  NodeWxLevel.none => Semantic.unknown,
  NodeWxLevel.unknown => Semantic.unknown,
};

IconData nodeWxIcon(NodeWxClass c) => switch (c) {
  NodeWxClass.galeWind || NodeWxClass.strongWind => Icons.air,
  NodeWxClass.severeCold || NodeWxClass.freezing => Icons.ac_unit,
  NodeWxClass.heavyPrecip => Icons.water_drop,
  NodeWxClass.precip => Icons.grain,
  NodeWxClass.calm => Icons.info_outline,
  NodeWxClass.insufficient => Icons.question_mark,
  NodeWxClass.noData => Icons.remove,
};

/// 地图上的天气节点：彩色圆点 + 类别图标。
class NodeWxMarker extends StatelessWidget {
  const NodeWxMarker({super.key, required this.cls, this.selected = false});

  final NodeWxClass cls;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 24.0 : 18.0;
    final color = nodeWxColor(cls);
    return Tooltip(
      message: cls.label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cls == NodeWxClass.noData ? Colors.white : color,
          shape: BoxShape.circle,
          border: Border.all(
            color: cls == NodeWxClass.noData ? color : Colors.white,
            width: 2,
          ),
          boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)],
        ),
        child: Icon(
          nodeWxIcon(cls),
          size: size * 0.6,
          color: cls == NodeWxClass.noData ? color : Colors.white,
        ),
      ),
    );
  }
}

/// 地图图例：只列出当前出现的类别。
class NodeWxLegend extends StatelessWidget {
  const NodeWxLegend({super.key, required this.classes});

  final Iterable<NodeWxClass> classes;

  @override
  Widget build(BuildContext context) {
    final present = NodeWxClass.values.where(classes.toSet().contains).toList();
    if (present.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              // 图例说明收进提示（长按/悬停），不再在地图下方多占一行。
              Tooltip(
                message: S.nodeWxLegendNote,
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              for (final c in present)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NodeWxMarker(cls: c),
                    const SizedBox(width: 4),
                    Text(c.label, style: const TextStyle(fontSize: 11)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
