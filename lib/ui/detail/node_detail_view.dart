import 'package:flutter/material.dart';

import '../../core/geo.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/wx_importance.dart';
import '../strings.dart';
import '../widgets/common.dart';
import 'detail_state.dart';
import 'environment_cards.dart';
import 'meteogram.dart';
import 'node_detail_sheet.dart';
import 'node_photos.dart';
import 'weather_cells.dart';

/// 节点详情：到达时间、当前来源完整天气、未来 12 小时、标记操作、多来源对比。
///
/// 选中节点在地图标记 / 海拔剖面 / 时间线三处共享；在这里前后切换节点会通过
/// [onIndexChanged] 同步回详情页。
class NodeDetailView extends StatefulWidget {
  const NodeDetailView({
    super.key,
    required this.rows,
    required this.initialIndex,
    required this.tripMode,
    required this.fixedUtc,
    required this.settings,
    required this.onIndexChanged,
    required this.onMark,
    required this.onEditMark,
    required this.onRemoveMark,
    this.routeId,
  });

  final List<NodeWxRow> rows;
  final int initialIndex;
  final bool tripMode;
  final DateTime fixedUtc;
  final AppSettings settings;
  final ValueChanged<int> onIndexChanged;
  final void Function(RouteNodeRef node, WaypointType type) onMark;
  final void Function(RouteWaypoint waypoint) onEditMark;
  final void Function(RouteWaypoint waypoint) onRemoveMark;

  /// 线路 id；提供时显示节点图片区。
  final String? routeId;

  @override
  State<NodeDetailView> createState() => _NodeDetailViewState();
}

/// 标记操作只需要节点位置与名称，不依赖整个节点行。
typedef RouteNodeRef = ({int index, String label});

class _NodeDetailViewState extends State<NodeDetailView> {
  late int _idx = widget.initialIndex.clamp(0, widget.rows.length - 1);

  void _go(int i) {
    setState(() => _idx = i);
    widget.onIndexChanged(i);
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.rows[_idx];
    final node = row.node;
    final wp = node.waypoint;
    final theme = Theme.of(context);
    final wx = row.wx;
    final label = node.label ?? S.detailNodeFallback(_idx + 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (wp != null) ...[
              WaypointMarker(type: wp.type, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: S.nodePrevious,
              icon: const Icon(Icons.chevron_left),
              onPressed: _idx > 0 ? () => _go(_idx - 1) : null,
            ),
            Text('${_idx + 1}/${widget.rows.length}'),
            IconButton(
              tooltip: S.nodeNext,
              icon: const Icon(Icons.chevron_right),
              onPressed: _idx < widget.rows.length - 1
                  ? () => _go(_idx + 1)
                  : null,
            ),
          ],
        ),
        Text(
          '${S.nodeDistFromStartKm((node.distFromStartM / 1000).toStringAsFixed(1))}'
          '${node.elevationM == null ? '' : ' · ${node.elevationM!.toStringAsFixed(0)} m'}'
          ' · ${widget.tripMode ? S.arrivalEstimate : S.fixedMoment} ${_fmtLocal(row.validUtc)}',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (wp != null) _markedRow(wp),
        if (node.nearbyWaypoints.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            S.nearbyMarksTitle,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final n in node.nearbyWaypoints)
            _markedRow(n, offsetM: Geo.distanceM(node.pos, n.point)),
        ],
        const SizedBox(height: 10),
        // 先回答“到这里时天气怎样”：4 个关键值放大，其余指标收进“更多指标”。
        if (wx == null)
          const GranularityNotice(text: S.nodeNoDataAtTime)
        else ...[
          KeyWeatherValues(wx: wx, settings: widget.settings),
          WeatherHourNotice(wx: wx),
          // 准备层只在触发时升上来（紫外线很高、高于 0℃ 层、低云……）。
          if (signalsFor(wx, elevationM: node.elevationM) case final sig
              when sig.isNotEmpty) ...[
            const SizedBox(height: 6),
            WxSignalChips(signals: sig),
          ],
        ],
        if (row.point case final point?) ...[
          const SizedBox(height: 14),
          Text(
            S.meteogramTitle,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          NodeMeteogram(
            key: ValueKey('mg-$_idx-${row.validUtc}'),
            point: point,
            arrivalUtc: row.validUtc,
            settings: widget.settings,
          ),
        ],
        const SizedBox(height: 10),
        AltitudeWeatherCard(
          key: ValueKey('alt-$_idx-${row.validUtc}'),
          point: node.pos,
          atUtc: row.validUtc,
          nodeElevationM: node.elevationM,
          routeMinM: _routeMinMax().$1,
          routeMaxM: _routeMinMax().$2,
        ),
        const SizedBox(height: 4),
        if (wx != null)
          _fold(
            S.moreMetrics,
            WxVarGrid(
              wx: wx,
              settings: widget.settings,
              exclude: const {
                WxVar.temperature,
                WxVar.apparentTemp,
                WxVar.precip,
                WxVar.precipProb,
                WxVar.windGust,
              },
            ),
          ),
        _fold(
          S.airQualityTitle,
          AirQualityCard(
            key: ValueKey('aq-$_idx'),
            point: node.pos,
            atUtc: row.validUtc,
          ),
        ),
        _fold(
          S.multiSourceCompare,
          NodeComparePanel(
            key: ValueKey('compare-$_idx'),
            rows: widget.rows,
            initialIndex: _idx,
            fixedUtc: widget.tripMode ? null : widget.fixedUtc,
          ),
        ),
        if (widget.routeId != null)
          _fold(
            S.nodePhotos,
            NodePhotosSection(routeId: widget.routeId!, pos: node.pos),
          ),
        if (wp == null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text(S.markAs),
            onPressed: () => _pickMarkType(label),
          ),
        ],
      ],
    );
  }

  /// 次要内容默认收起：标题一行，点开才构建（空气质量、多来源对比此时才发请求）。
  Widget _fold(String title, Widget child) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    dense: true,
    title: Text(title, style: const TextStyle(fontSize: 14)),
    childrenPadding: const EdgeInsets.only(bottom: 8),
    children: [child],
  );

  /// [offsetM]：普通航点与本节点的直线距离（挂在节点上的航点才有）。
  Widget _markedRow(RouteWaypoint wp, {double? offsetM}) => Row(
    children: [
      WaypointMarker(type: wp.type, size: 14),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          '${_shortLabel(wp.type)} · ${wp.name}'
          '${wp.stopMinutes == null ? '' : ' · ${S.detailStopMinutes(wp.stopMinutes!)}'}'
          '${offsetM == null ? '' : ' · ${S.nearbyOffset(offsetM)}'}',
          style: const TextStyle(fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      IconButton(
        tooltip: S.editMark,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.edit_outlined, size: 18),
        onPressed: () => widget.onEditMark(wp),
      ),
      IconButton(
        tooltip: S.removeMark,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: () => widget.onRemoveMark(wp),
      ),
    ],
  );

  /// 8 种标记类型放进二级面板，节点详情里只留一个“标记为”按钮。
  void _pickMarkType(String label) {
    const types = [
      WaypointType.camp,
      WaypointType.rest,
      WaypointType.water,
      WaypointType.supply,
      WaypointType.danger,
      WaypointType.pass,
      WaypointType.exit,
      WaypointType.poi,
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in types)
                ActionChip(
                  avatar: Icon(waypointStyle(t).$1, size: 16),
                  label: Text(_shortLabel(t)),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    widget.onMark((index: _idx, label: label), t);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 线路（采样节点）海拔范围；无海拔时为 (null, null)。
  (double?, double?) _routeMinMax() {
    final eles = widget.rows
        .map((r) => r.node.elevationM)
        .whereType<double>()
        .toList();
    if (eles.isEmpty) return (null, null);
    eles.sort();
    return (eles.first, eles.last);
  }

  static String _fmtLocal(DateTime utc) {
    final t = utc.toLocal();
    return S.nodeLocalTime(
      t.month,
      t.day,
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
    );
  }
}

/// 类型名去掉表情符号，用作按钮与默认名称。
String _shortLabel(WaypointType t) => waypointTypeLabel(t).split(' ').first;

/// 默认标记名称（用户可改）。
String defaultWaypointName(WaypointType t) => _shortLabel(t);
