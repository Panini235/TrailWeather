import 'package:flutter/material.dart';

import '../../core/units.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/weather_models.dart';
import '../strings.dart';
import '../widgets/common.dart';
import 'detail_state.dart';
import 'environment_cards.dart';
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
    final label = node.label ?? '节点 ${_idx + 1}';

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
              tooltip: '上一个节点',
              icon: const Icon(Icons.chevron_left),
              onPressed: _idx > 0 ? () => _go(_idx - 1) : null,
            ),
            Text('${_idx + 1}/${widget.rows.length}'),
            IconButton(
              tooltip: '下一个节点',
              icon: const Icon(Icons.chevron_right),
              onPressed: _idx < widget.rows.length - 1
                  ? () => _go(_idx + 1)
                  : null,
            ),
          ],
        ),
        Text(
          '距起点 ${(node.distFromStartM / 1000).toStringAsFixed(1)} km'
          '${node.elevationM == null ? '' : ' · 轨迹海拔 ${node.elevationM!.toStringAsFixed(0)} m'}',
          style: const TextStyle(fontSize: 13),
        ),
        Text(
          '${widget.tripMode ? S.arrivalEstimate : S.fixedMoment}：'
          '${_fmtLocal(row.validUtc)}',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        _markSection(context, wp, label),
        if (widget.routeId != null) ...[
          const SizedBox(height: 10),
          NodePhotosSection(routeId: widget.routeId!, pos: node.pos),
        ],
        const SizedBox(height: 10),
        if (wx == null)
          const GranularityNotice(text: '此来源在该时刻没有数据（超出预报范围或来源未提供）。')
        else
          WxVarGrid(wx: wx, settings: widget.settings),
        if (_freezingNote(wx, node.elevationM) case final note?)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(note, style: const TextStyle(fontSize: 12)),
          ),
        const SizedBox(height: 10),
        AltitudeWeatherCard(
          key: ValueKey('alt-$_idx-${row.validUtc}'),
          point: node.pos,
          atUtc: row.validUtc,
          nodeElevationM: node.elevationM,
          routeMinM: _routeMinMax().$1,
          routeMaxM: _routeMinMax().$2,
        ),
        const SizedBox(height: 8),
        AirQualityCard(
          key: ValueKey('aq-$_idx'),
          point: node.pos,
          atUtc: row.validUtc,
        ),
        const SizedBox(height: 10),
        Text(S.next12h, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        _NextHours(row: row, settings: widget.settings),
        const SizedBox(height: 6),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(S.multiSourceCompare),
          children: [
            NodeComparePanel(
              key: ValueKey('compare-$_idx'),
              rows: widget.rows,
              initialIndex: _idx,
              fixedUtc: widget.tripMode ? null : widget.fixedUtc,
            ),
          ],
        ),
      ],
    );
  }

  Widget _markSection(BuildContext context, RouteWaypoint? wp, String label) {
    if (wp != null) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          dense: true,
          title: Text('${waypointTypeLabel(wp.type)} · ${wp.name}'),
          subtitle: wp.stopMinutes == null
              ? null
              : Text('停留 ${wp.stopMinutes} 分钟（已计入后续到达时间）'),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                tooltip: S.editMark,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => widget.onEditMark(wp),
              ),
              IconButton(
                tooltip: S.removeMark,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => widget.onRemoveMark(wp),
              ),
            ],
          ),
        ),
      );
    }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(S.markAs, style: TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final t in types)
              ActionChip(
                avatar: Icon(waypointStyle(t).$1, size: 16),
                label: Text(_shortLabel(t)),
                onPressed: () => widget.onMark((index: _idx, label: label), t),
              ),
          ],
        ),
      ],
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

  /// 节点海拔与来源 0℃ 层高度的关系（来源提供时才给出）。
  static String? _freezingNote(WxHourValue? wx, double? nodeEle) {
    final fz = wx?.values[WxVar.freezingLevel];
    if (fz == null || nodeEle == null) return null;
    final diff = nodeEle - fz;
    return diff >= 0
        ? '本节点（${nodeEle.toStringAsFixed(0)} m）高于 0℃ 层约 ${diff.toStringAsFixed(0)} m：可能结冰或降雪（0℃ 层为模型估计）。'
        : '本节点（${nodeEle.toStringAsFixed(0)} m）低于 0℃ 层约 ${(-diff).toStringAsFixed(0)} m（0℃ 层为模型估计）。';
  }

  static String _fmtLocal(DateTime utc) {
    final t = utc.toLocal();
    return '${t.month}月${t.day}日 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

/// 类型名去掉表情符号，用作按钮与默认名称。
String _shortLabel(WaypointType t) => waypointTypeLabel(t).split(' ').first;

/// 默认标记名称（用户可改）。
String defaultWaypointName(WaypointType t) => _shortLabel(t);

class _NextHours extends StatelessWidget {
  const _NextHours({required this.row, required this.settings});

  final NodeWxRow row;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final point = row.point;
    final from = DateTime.utc(
      row.validUtc.year,
      row.validUtc.month,
      row.validUtc.day,
      row.validUtc.hour,
    );
    final hours = point == null
        ? const <WxHourValue>[]
        : point.hours
              .where((h) => !h.validFromUtc.isBefore(from))
              .take(12)
              .toList();
    if (hours.isEmpty) {
      return const Text('此来源没有该时段之后的逐时数据。', style: TextStyle(fontSize: 12));
    }
    String fmt(double? v, String Function(double) f) => v == null ? '—' : f(v);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 28,
        dataRowMinHeight: 26,
        dataRowMaxHeight: 30,
        columnSpacing: 14,
        horizontalMargin: 4,
        columns: [
          const DataColumn(label: Text('')),
          for (final h in hours)
            DataColumn(
              label: Text(
                '${h.validFromUtc.toLocal().hour.toString().padLeft(2, '0')}时',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
        rows: [
          _row('温度', hours, (h) {
            return fmt(
              h.values[WxVar.temperature],
              (x) => Units.temp(x, imperial: settings.imperial),
            );
          }),
          _row('降水', hours, (h) {
            return fmt(
              h.values[WxVar.precip],
              (x) => Units.precipMm(x, imperial: settings.imperial),
            );
          }),
          _row('阵风', hours, (h) {
            return fmt(
              h.values[WxVar.windGust],
              (x) => Units.windMs(x, unit: settings.windUnit),
            );
          }),
        ],
      ),
    );
  }

  DataRow _row(
    String name,
    List<WxHourValue> hours,
    String Function(WxHourValue) cell,
  ) => DataRow(
    cells: [
      DataCell(Text(name, style: const TextStyle(fontSize: 11))),
      for (final h in hours)
        DataCell(Text(cell(h), style: const TextStyle(fontSize: 11))),
    ],
  );
}
