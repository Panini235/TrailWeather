import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/routes/planet_trails_repository.dart';
import '../../data/routes/route_models.dart';
import '../detail/route_detail_screen.dart';
import '../strings.dart';

/// 徒步星球 · 全球经典徒步路线专区。
class PlanetTrailsScreen extends ConsumerStatefulWidget {
  const PlanetTrailsScreen({super.key});

  @override
  ConsumerState<PlanetTrailsScreen> createState() => _PlanetTrailsScreenState();
}

class _PlanetTrailsScreenState extends ConsumerState<PlanetTrailsScreen> {
  String _selectedCat = 'all';
  int _distFilterIndex =
      0; // 0: 全部, 1: ≤20km, 2: 20-50km, 3: 50-100km, 4: 100km+

  @override
  Widget build(BuildContext context) {
    final trailsAsync = ref.watch(planetTrailsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(S.planetTitle),
        actions: [
          IconButton(
            tooltip: S.planetRandomTooltip,
            icon: const Icon(Icons.shuffle),
            onPressed: () async {
              final repo = ref.read(planetTrailsRepositoryProvider);
              final r = await repo.getRandomRoute();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      S.planetRandomTeleported(r.name, r.region ?? ''),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
                unawaited(
                  context.push(
                    '/route/${r.id}',
                    extra: RouteDetailArgs(route: r),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. 地貌分类横向滚动条
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: TerrainCategory.all.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = TerrainCategory.all[index];
                final isSelected = _selectedCat == cat.key;
                return ChoiceChip(
                  label: Text('${cat.icon} ${cat.label}'),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => _selectedCat = cat.key);
                  },
                );
              },
            ),
          ),

          // 2. 里程区间筛选
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text(S.planetAllDistances)),
                  ButtonSegment(value: 1, label: Text('≤20km')),
                  ButtonSegment(value: 2, label: Text('20-50km')),
                  ButtonSegment(value: 3, label: Text('50-100km')),
                  ButtonSegment(value: 4, label: Text('100km+')),
                ],
                selected: {_distFilterIndex},
                onSelectionChanged: (set) {
                  setState(() => _distFilterIndex = set.first);
                },
              ),
            ),
          ),

          const Divider(height: 1),

          // 3. 路线卡片列表
          Expanded(
            child: trailsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text(S.planetLoadFailed('$err'))),
              data: (allRoutes) {
                // 客户端过滤
                final filtered = allRoutes.where((r) {
                  if (_selectedCat != 'all' && r.category != _selectedCat) {
                    return false;
                  }
                  final km = r.totalDistanceM / 1000.0;
                  return switch (_distFilterIndex) {
                    1 => km <= 20,
                    2 => km > 20 && km <= 50,
                    3 => km > 50 && km <= 100,
                    4 => km > 100,
                    _ => true,
                  };
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text(S.planetEmptyCategory));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (context, idx) {
                    final r = filtered[idx];
                    return _PlanetRouteCard(route: r);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanetRouteCard extends StatelessWidget {
  const _PlanetRouteCard({required this.route});

  final HikingRoute route;

  @override
  Widget build(BuildContext context) {
    final km = (route.totalDistanceM / 1000.0).toStringAsFixed(1);
    final ascent = route.totalAscentM != null
        ? '${route.totalAscentM!.round()} m'
        : S.unknown;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          unawaited(
            context.push(
              '/route/${route.id}',
              extra: RouteDetailArgs(route: route),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          route.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (route.region != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            route.region!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (route.category != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _catLabel(route.category!),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _InfoChip(icon: Icons.straighten, text: '$km km'),
                  const SizedBox(width: 12),
                  _InfoChip(
                    icon: Icons.trending_up,
                    text: S.planetAscent(ascent),
                  ),
                  if (route.durationDesc != null) ...[
                    const SizedBox(width: 12),
                    _InfoChip(icon: Icons.schedule, text: route.durationDesc!),
                  ],
                  if (route.seasonDesc != null) ...[
                    const SizedBox(width: 12),
                    _InfoChip(
                      icon: Icons.wb_sunny_outlined,
                      text: route.seasonDesc!,
                    ),
                  ],
                ],
              ),
              if (route.description != null &&
                  route.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  route.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _catLabel(String cat) {
    for (final c in TerrainCategory.all) {
      if (c.key == cat) return '${c.icon} ${c.label}';
    }
    return cat;
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 2),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
