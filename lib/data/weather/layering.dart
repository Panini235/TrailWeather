import 'risk_rules.dart';
import 'weather_models.dart';
import 'weather_phenomena.dart';

/// 洋葱穿衣法建议（docs/data-hierarchy.md「穿衣建议」）。
///
/// 经验规则，不是安全保证：阈值全部写在这里并有单元测试；每条建议都带依据；
/// 输入缺失时如实说明哪一项没评估，不默认“够用”。
///
/// 三个场景对应洋葱法的核心——同一天身体产热差别很大：
/// - 出发：起点体感；爬升十几分钟后会热，出发时略凉为宜；
/// - 行进：沿途体感的中位数，持续产热；
/// - 停留：沿途最冷处（山顶、垭口、午饭、等人），几乎不产热，决定保暖层带多厚。
enum LayerScene { start, moving, stop }

String layerSceneLabel(LayerScene s) => switch (s) {
  LayerScene.start => '出发',
  LayerScene.moving => '行进',
  LayerScene.stop => '停留',
};

enum LayerKind { base, mid, shell, legs }

String layerKindLabel(LayerKind k) => switch (k) {
  LayerKind.base => '排汗层',
  LayerKind.mid => '保暖层',
  LayerKind.shell => '防护层',
  LayerKind.legs => '下装',
};

/// 某层在某场景：穿着 / 背包里备着 / 不需要。
enum Wear { worn, packed, none }

class LayerItem {
  const LayerItem({
    required this.kind,
    required this.name,
    required this.wear,
    required this.reason,
  });

  final LayerKind kind;
  final String name;
  final Map<LayerScene, Wear> wear;
  final String reason;
}

enum Accessory {
  sunscreen,
  sunHat,
  sunglasses,
  beanie,
  gloves,
  warmGloves,
  buff,
  headlamp,
  rainPants,
  packCover,
}

String accessoryLabel(Accessory a) => switch (a) {
  Accessory.sunscreen => '防晒霜',
  Accessory.sunHat => '遮阳帽',
  Accessory.sunglasses => '墨镜',
  Accessory.beanie => '保暖帽',
  Accessory.gloves => '手套',
  Accessory.warmGloves => '厚手套',
  Accessory.buff => '头巾',
  Accessory.headlamp => '头灯',
  Accessory.rainPants => '雨裤',
  Accessory.packCover => '背包防雨罩',
};

class AccessoryPick {
  const AccessoryPick(this.item, this.reason);
  final Accessory item;
  final String reason;
}

class LayerPlan {
  const LayerPlan({
    required this.feels,
    required this.layers,
    required this.accessories,
    required this.notes,
    required this.usedApparent,
  });

  /// 各场景的体感温度（已按个人偏好平移前的原值，供显示）。
  final Map<LayerScene, double> feels;
  final List<LayerItem> layers;
  final List<AccessoryPick> accessories;

  /// 没评估的项目（如“阵风未提供，防风判断不完整”）。
  final List<String> notes;

  /// true：按体感温度；false：来源没有体感温度，按气温。
  final bool usedApparent;

  LayerItem? layer(LayerKind k) {
    for (final l in layers) {
      if (l.kind == k) return l;
    }
    return null;
  }
}

/// 个人偏好对应的体感平移：怕冷按更冷处理。
double sensitivityOffset(int coldSensitivity) => switch (coldSensitivity) {
  < 0 => -3,
  > 0 => 3,
  _ => 0,
};

/// [entries] 按线路顺序、对齐到到达时刻；[labels] 与之对应（用于依据里点名最冷处）。
/// 全部节点都没有气温/体感时返回 null（信息不足，不给建议）。
LayerPlan? planLayers({
  required List<NodeWeatherEntry> entries,
  List<String>? labels,
  DateTime? sunriseUtc,
  DateTime? sunsetUtc,
  int coldSensitivity = 0,
}) {
  final feels = <(int, double)>[];
  var anyApparent = false;
  for (var i = 0; i < entries.length; i++) {
    final v = entries[i].weather?.values;
    final a = v?[WxVar.apparentTemp];
    final t = v?[WxVar.temperature];
    if (a != null) anyApparent = true;
    final f = a ?? t;
    if (f != null) feels.add((i, f));
  }
  if (feels.isEmpty) return null;

  final off = sensitivityOffset(coldSensitivity);
  final sorted = [for (final (_, f) in feels) f]..sort();
  final startFeel = feels.first.$2;
  final movingFeel = sorted[sorted.length ~/ 2];
  final (coldIdx, stopFeel) = feels.reduce((a, b) => b.$2 < a.$2 ? b : a);
  final hotFeel = sorted.last;
  // 判断用平移后的值，显示用原值。
  final s = startFeel + off, m = movingFeel + off, c = stopFeel + off;
  final h = hotFeel + off;

  String where(int i) {
    final label = labels != null && i < labels.length ? labels[i] : null;
    final ele = entries[i].elevationM;
    final t = entries[i].validUtc.toLocal();
    final hh =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return [?label, if (ele != null) '${ele.round()} m', hh].join(' · ');
  }

  String deg(double x) => '${x.round()}°';

  // ---- 降水 / 风 / 紫外线 / 雪 汇总 ----
  double? maxProb, maxGust, maxUv, firstPrecip, firstProb, firstGust;
  var anyPrecipVal = false, wetPhenomenon = false, snowy = false;
  final first = entries.first.weather?.values;
  firstPrecip = first?[WxVar.precip];
  firstProb = first?[WxVar.precipProb];
  firstGust = first?[WxVar.windGust];
  for (final e in entries) {
    final w = e.weather;
    if (w == null) continue;
    final v = w.values;
    double? mx(double? cur, double? x) =>
        x == null ? cur : (cur == null || x > cur ? x : cur);
    maxProb = mx(maxProb, v[WxVar.precipProb]);
    maxGust = mx(maxGust, v[WxVar.windGust]);
    maxUv = mx(maxUv, v[WxVar.uvIndex]);
    if (v[WxVar.precip] != null) anyPrecipVal = true;
    final kind = phenomenonOf(w)?.kind;
    if (kind == WxPhenomenonKind.rain ||
        kind == WxPhenomenonKind.snow ||
        kind == WxPhenomenonKind.mixed ||
        kind == WxPhenomenonKind.thunder) {
      wetPhenomenon = true;
    }
    final depth = v[WxVar.snowDepth];
    final fall = v[WxVar.snowfall];
    if ((depth != null && depth >= 0.01) || (fall != null && fall >= 0.5)) {
      snowy = true;
    }
  }
  final routeMm = routePrecipMm([
    for (final e in entries) (e.validUtc, e.weather?.values[WxVar.precip]),
  ]);
  final wet =
      (maxProb != null && maxProb >= 40) ||
      (routeMm != null && routeMm >= 0.5) ||
      wetPhenomenon;
  final notes = <String>[
    if (!anyApparent) '此来源没有体感温度，按气温估计（风寒未计入）。',
    if (maxGust == null) '此来源没有阵风，防风判断不完整。',
    if (!anyPrecipVal && maxProb == null) '此来源没有降水数据，防雨判断不完整。',
    if (maxUv == null) '此来源没有紫外线预报，防晒未评估。',
  ];

  // ---- 排汗层：全程穿着 ----
  final baseName = h >= 22 && m >= 16
      ? '短袖速干'
      : m >= 8
      ? '长袖速干'
      : '保暖排汗长袖';
  final layers = <LayerItem>[
    LayerItem(
      kind: LayerKind.base,
      name: baseName,
      wear: const {
        LayerScene.start: Wear.worn,
        LayerScene.moving: Wear.worn,
        LayerScene.stop: Wear.worn,
      },
      reason: '行进体感约 ${deg(movingFeel)}；速干或羊毛材质，不穿棉。',
    ),
  ];

  // ---- 保暖层：按停留（最冷处）选厚度 ----
  final midName = c >= 18
      ? null
      : c >= 12
      ? '薄抓绒'
      : c >= 5
      ? '抓绒衣'
      : c >= -5
      ? '薄羽绒或厚抓绒'
      : '厚羽绒';
  if (midName != null) {
    layers.add(
      LayerItem(
        kind: LayerKind.mid,
        name: midName,
        wear: {
          LayerScene.start: s < 5 ? Wear.worn : Wear.packed,
          LayerScene.moving: m < -3 ? Wear.worn : Wear.packed,
          LayerScene.stop: Wear.worn,
        },
        reason: '最冷处体感约 ${deg(stopFeel)}（${where(coldIdx)}），停下来几乎不产热。',
      ),
    );
  }

  // ---- 防护层：雨优先，其次风 ----
  final windy = maxGust != null && maxGust >= 10.8;
  final breezy = maxGust != null && maxGust >= 5.5 && c < 15;
  final shellName = wet
      ? '防水硬壳'
      : windy
      ? '软壳或防风外套'
      : breezy
      ? '轻薄防风衣'
      : null;
  if (shellName != null) {
    final rainyStart =
        (firstPrecip != null && firstPrecip >= 0.1) ||
        (firstProb != null && firstProb >= 60);
    final gustyStart = firstGust != null && firstGust >= 10.8;
    final reasons = <String>[
      if (wet)
        [
          if (maxProb != null) '降水概率最高 ${maxProb.round()}%',
          if (routeMm != null && routeMm > 0)
            '沿途约 ${routeMm.toStringAsFixed(1)} mm',
          if (wetPhenomenon && maxProb == null && (routeMm ?? 0) == 0)
            '预报有降水天气',
        ].join('，'),
      if (maxGust != null && maxGust >= 5.5)
        '阵风最大 ${maxGust.toStringAsFixed(0)} m/s',
    ];
    layers.add(
      LayerItem(
        kind: LayerKind.shell,
        name: shellName,
        wear: {
          LayerScene.start: rainyStart || gustyStart || s < 0
              ? Wear.worn
              : Wear.packed,
          LayerScene.moving:
              (wet && routeMm != null && routeMm >= 2) ||
                  (maxGust != null && maxGust >= 13.9)
              ? Wear.worn
              : Wear.packed,
          LayerScene.stop: wet || windy || c < 5 ? Wear.worn : Wear.packed,
        },
        reason: '${reasons.where((r) => r.isNotEmpty).join('；')}。',
      ),
    );
  }

  // ---- 下装 ----
  final legsName = h >= 24 && m >= 18 && !wet
      ? '速干短裤'
      : m < 0
      ? '软壳长裤'
      : '速干长裤';
  layers.add(
    LayerItem(
      kind: LayerKind.legs,
      name: legsName,
      wear: const {
        LayerScene.start: Wear.worn,
        LayerScene.moving: Wear.worn,
        LayerScene.stop: Wear.worn,
      },
      reason: '行进体感约 ${deg(movingFeel)}，最高约 ${deg(hotFeel)}。',
    ),
  );

  // ---- 配件 ----
  final acc = <AccessoryPick>[];
  if (maxUv != null && maxUv >= 3) {
    acc.add(
      AccessoryPick(Accessory.sunscreen, '紫外线最高约 ${maxUv.round()}（≥ 3 需防护）。'),
    );
    if (h >= 10) {
      acc.add(const AccessoryPick(Accessory.sunHat, '紫外线 ≥ 3。'));
    }
  }
  if ((maxUv != null && maxUv >= 6) || (snowy && maxUv != null && maxUv >= 2)) {
    acc.add(
      AccessoryPick(
        Accessory.sunglasses,
        snowy ? '有积雪或降雪，雪面反光易致雪盲。' : '紫外线 ≥ 6。',
      ),
    );
  }
  if (c <= 5) {
    acc.add(AccessoryPick(Accessory.beanie, '最冷处体感约 ${deg(stopFeel)}。'));
    acc.add(
      AccessoryPick(
        c <= -8 ? Accessory.warmGloves : Accessory.gloves,
        '最冷处体感约 ${deg(stopFeel)}。',
      ),
    );
  }
  if ((maxGust != null && maxGust >= 13.9) || c <= -5) {
    acc.add(const AccessoryPick(Accessory.buff, '大风或严寒时护住口鼻和脖子。'));
  }
  final finish = entries.last.validUtc;
  final start = entries.first.validUtc;
  if ((sunsetUtc != null && finish.isAfter(sunsetUtc)) ||
      (sunriseUtc != null && start.isBefore(sunriseUtc))) {
    acc.add(const AccessoryPick(Accessory.headlamp, '行程有一段在日出前或日落后。'));
  }
  if (wet && routeMm != null && routeMm >= 2) {
    acc.add(
      AccessoryPick(
        Accessory.rainPants,
        '沿途降水约 ${routeMm.toStringAsFixed(1)} mm。',
      ),
    );
  }
  if (wet) {
    acc.add(const AccessoryPick(Accessory.packCover, '预报有降水。'));
  }

  return LayerPlan(
    feels: {
      LayerScene.start: startFeel,
      LayerScene.moving: movingFeel,
      LayerScene.stop: stopFeel,
    },
    layers: layers,
    accessories: acc,
    notes: notes,
    usedApparent: anyApparent,
  );
}
