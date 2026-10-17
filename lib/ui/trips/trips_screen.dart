import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_providers.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/settings_repository.dart';
import '../detail/route_detail_screen.dart';
import '../strings.dart';
import '../widgets/common.dart';
import '../../core/features.dart';

/// 首页“我的行程”：用户导入、手绘、收藏的线路（docs/redesign-v2.md）。
///
/// 导入是第一入口；示例线路与徒步星球置底，仅供体验。
class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = ref.read(settingsProvider);
      if (!settings.hasCompletedOnboarding || !settings.privacyAccepted) {
        context.push('/onboarding');
      }
    });
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text(S.importRoute),
              subtitle: const Text(S.importTrackHint),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/import');
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_road),
              title: const Text(S.drawRoute),
              subtitle: const Text(S.drawRouteHint),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/planner');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(HikingRoute route) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除“${route.name}”？'),
        content: const Text(S.deleteTripDetail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.delete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(favoritesProvider.notifier).remove(route.id);
    }
  }

  void _open(HikingRoute route) {
    context.push('/route/${route.id}', extra: RouteDetailArgs(route: route));
  }

  @override
  Widget build(BuildContext context) {
    // 最近加入的在前。
    final trips = ref.watch(favoritesProvider).reversed.toList();
    final samples = ref.watch(sampleRoutesProvider).value ?? const [];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(S.myTrips),
        actions: [
          IconButton(
            tooltip: S.addTrip,
            icon: const Icon(Icons.add),
            onPressed: _showAddSheet,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.offline_pin_outlined),
              title: const Text('离线行程包'),
              subtitle: const Text('查看已保存的线路与预报'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/offline'),
            ),
          ),
          if (trips.isEmpty)
            _EmptyTrips(
              onImport: () => context.push('/import'),
              onDraw: () => context.push('/planner'),
            )
          else
            for (final r in trips)
              _TripCard(
                route: r,
                onTap: () => _open(r),
                onDelete: () => _confirmDelete(r),
              ),
          if (_supportsOpenWith && trips.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: GranularityNotice(text: S.openWithHint),
            ),
          const SizedBox(height: 16),
          Text(S.exampleRoutes, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final r in samples) _TripCard(route: r, onTap: () => _open(r)),
          // 徒步星球线路库：许可核实前测试版隐藏（B-011）。
          if (kPlanetTrailsEnabled)
            Card(
              child: ListTile(
                leading: const Icon(Icons.public),
                title: const Text(S.planetEntry),
                subtitle: const Text(S.planetEntryHint),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/planet'),
              ),
            ),
        ],
      ),
    );
  }
}

/// “用山晴打开”：Android 与 iOS 均已接入（Web 无此能力）。
bool get _supportsOpenWith =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

class _EmptyTrips extends StatelessWidget {
  const _EmptyTrips({required this.onImport, required this.onDraw});

  final VoidCallback onImport;
  final VoidCallback onDraw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.route, size: 36, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              S.emptyTripsTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              S.emptyTripsBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text(S.importRoute),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: onDraw,
              icon: const Icon(Icons.edit_road),
              label: const Text(S.drawRoute),
            ),
            if (_supportsOpenWith) ...[
              const SizedBox(height: 10),
              const Text(
                S.openWithHint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.route, required this.onTap, this.onDelete});

  final HikingRoute route;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final km = (route.totalDistanceM / 1000).toStringAsFixed(1);
    final ascent = route.totalAscentM;
    final facts = [
      '$km km',
      if (ascent != null) '↑${ascent.toStringAsFixed(0)} m',
      if (route.durationDesc != null) route.durationDesc!,
      routeOriginLabel(route.origin),
    ].join(' · ');
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.hiking),
        title: Row(
          children: [
            Flexible(child: Text(route.name, overflow: TextOverflow.ellipsis)),
            if (route.isDemo) ...[const SizedBox(width: 6), const DemoBadge()],
          ],
        ),
        subtitle: Text(
          facts,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: onDelete == null
            ? const Icon(Icons.chevron_right)
            : PopupMenuButton<String>(
                tooltip: S.more,
                onSelected: (_) => onDelete!(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text(S.delete)),
                ],
              ),
      ),
    );
  }
}
