import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/routes/route_models.dart';
import '../../data/settings/favorites_repository.dart';
import '../detail/route_detail_screen.dart';
import '../strings.dart';

/// 导入确认 → 保存到“我的行程” → 打开详情。
///
/// 导入页与“用山晴打开”（外部应用传入文件）共用同一流程，
/// 保证两条入口的摘要、隐私提示和保存行为一致。返回是否已保存。
Future<bool> confirmAndSaveImportedRoute(
  BuildContext context,
  WidgetRef ref,
  HikingRoute route, {
  List<String> warnings = const [],
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dCtx) => AlertDialog(
      title: Text(S.importConfirmTitle(route.name)),
      content: SingleChildScrollView(
        child: Text(
          S.importConfirmSummary(
            segments: route.segments.length,
            points: route.flatPoints.length,
            lengthKm: (route.totalDistanceM / 1000).toStringAsFixed(1),
            ascent: route.totalAscentM == null
                ? S.unknown
                : '${route.totalAscentM!.toStringAsFixed(0)} m',
            warnings: warnings,
          ),
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dCtx, false),
          child: const Text(S.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dCtx, true),
          child: const Text(S.saveToTrips),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  await ref.read(favoritesProvider.notifier).add(route);
  if (context.mounted) {
    await context.push(
      '/route/${route.id}',
      extra: RouteDetailArgs(route: route),
    );
  }
  return true;
}
