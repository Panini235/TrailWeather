import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/routes/planet_trails_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlanetTrailsRepository', () {
    test('成功加载 44 条全球经典徒步路线', () async {
      final repo = PlanetTrailsRepository();
      final trails = await repo.loadAll();

      expect(trails, hasLength(44));
      final tmb = trails.firstWhere((r) => r.id == 'planet-tmb');
      expect(tmb.name, '环勃朗峰');
      expect(tmb.region, contains('法国'));
      expect(tmb.category, 'snow');
      expect(tmb.flatPoints.length, greaterThan(100));
      expect(tmb.elevationsM.length, tmb.flatPoints.length);
      expect(tmb.totalDistanceM / 1000, greaterThan(100));
    });

    test('地貌类别与里程区间筛选功能正常', () async {
      final repo = PlanetTrailsRepository();
      final snowTrails = await repo.filter(category: 'snow');
      expect(snowTrails.every((r) => r.category == 'snow'), isTrue);
      expect(snowTrails.length, greaterThan(0));

      final shortTrails = await repo.filter(maxKm: 20);
      expect(shortTrails.every((r) => r.totalDistanceM / 1000 <= 20), isTrue);
    });

    test('随机探索能返回路线', () async {
      final repo = PlanetTrailsRepository();
      final r = await repo.getRandomRoute();
      expect(r.name.isNotEmpty, isTrue);
      expect(r.flatPoints.isNotEmpty, isTrue);
    });
  });
}
