import 'package:flutter/material.dart';

import '../../data/routes/route_models.dart';
import '../../data/weather/weather_models.dart';
import '../strings.dart';

/// “演示数据”标签：演示内容必须一直可见地标注，不得混入真实数据不说明。
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange),
      ),
      child: const Text(
        S.demoLabel,
        style: TextStyle(
          fontSize: 10,
          color: Colors.orange,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 来源徽章：显示服务商与模型，缺失能力如实说明。
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.caps, this.compact = false});

  final ProviderCapabilities caps;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        compact
            ? caps.displayName
            : '${caps.displayName} · ${caps.modelOrNetwork}',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 缺失值单元格：绝不显示 0，显示“此来源未提供”。
class MissingValueText extends StatelessWidget {
  const MissingValueText({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label ?? S.notProvided,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).disabledColor,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

/// 颗粒度/透明度提示条。
class GranularityNotice extends StatelessWidget {
  const GranularityNotice({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ?? Icons.info_outline,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 过期缓存提示（stale-while-revalidate 状态必须可见）。
class StaleDataBanner extends StatelessWidget {
  const StaleDataBanner({super.key, required this.cachedAtUtc});

  final DateTime cachedAtUtc;

  @override
  Widget build(BuildContext context) {
    final age = DateTime.now().toUtc().difference(cachedAtUtc);
    final mins = age.inMinutes;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        border: Border.all(color: Colors.amber.shade700),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: 16, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${S.staleData}（${S.cachedAt} $mins 分钟前）：${S.staleDataDetail}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// 线路来源行：区分已有徒步路线 / 路径数据 / 用户导入，并展示许可。
class RouteSourceLine extends StatelessWidget {
  const RouteSourceLine({super.key, required this.route});

  final HikingRoute route;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (route.isDemo) const DemoBadge(),
        Text(
          '${S.dataSourceLabel}：${routeOriginLabel(route.origin)} · ${route.sourceName}'
          '${route.sourceLicense == null ? '' : '（${route.sourceLicense}）'}',
          style: style,
        ),
      ],
    );
  }
}

/// 错误状态卡（来源失败/网络不可用）：如实显示，不静默吞掉。
class ErrorCard extends StatelessWidget {
  const ErrorCard({
    super.key,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(fontSize: 12, height: 1.4)),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(S.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 数据类型徽章（观测/模型估计/预报/趋势）。
class DataKindChip extends StatelessWidget {
  const DataKindChip({super.key, required this.kind});

  final WxDataKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(wxDataKindLabel(kind), style: const TextStyle(fontSize: 10)),
    );
  }
}

/// 航点类型的图标与颜色（规划工坊、线路详情、地图共用）。
(IconData, Color) waypointStyle(WaypointType type) => switch (type) {
  WaypointType.camp => (Icons.cabin, Colors.amber.shade800),
  WaypointType.water => (Icons.water_drop, Colors.blue),
  WaypointType.danger => (Icons.warning, Colors.red),
  WaypointType.pass => (Icons.landscape, Colors.deepPurple),
  WaypointType.exit => (Icons.exit_to_app, Colors.teal),
  WaypointType.poi => (Icons.place, Colors.orange),
  WaypointType.rest => (Icons.coffee, Colors.brown),
  WaypointType.supply => (Icons.storefront, Colors.green.shade700),
};

/// 地图上的航点圆形标记。
class WaypointMarker extends StatelessWidget {
  const WaypointMarker({super.key, required this.type, this.size = 20});

  final WaypointType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, col) = waypointStyle(type);
    return Container(
      decoration: BoxDecoration(
        color: col,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: Icon(icon, color: Colors.white, size: size * 0.8),
    );
  }
}

/// 按次计费来源（如 meteoblue）的查询入口：不自动请求，点击后才查询并消耗额度。
class OnDemandQueryPrompt extends StatelessWidget {
  const OnDemandQueryPrompt({
    super.key,
    required this.caps,
    required this.onQuery,
  });

  final ProviderCapabilities caps;
  final VoidCallback onQuery;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caps.quotaNote != null)
          Text(
            caps.quotaNote!,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 6),
        FilledButton.tonalIcon(
          onPressed: onQuery,
          icon: const Icon(Icons.cloud_download_outlined, size: 18),
          label: const Text(S.onDemandQuery),
        ),
      ],
    );
  }
}
