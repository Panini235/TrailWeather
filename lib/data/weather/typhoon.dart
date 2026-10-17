import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'weather_provider.dart';

/// 台风路径（D-035）：日本气象厅（WMO 区域专业气象中心 RSMC 东京）发布的
/// 西北太平洋与南海热带气旋实况与路径预报。
///
/// - 数据：www.jma.go.jp/bosai/typhoon/data/（气象厅网站所用 JSON；2026-10-17 实测国内直连可用）；
///   网站内容按“政府标准利用规约 2.0”可转载并须注明出处，与 CC BY 4.0 兼容；
/// - 风速为 10 分钟平均（JMA 标准），与中央气象台的 2 分钟平均不同，不能直接比较；
/// - 预报圆是 70% 概率圆：中心有 70% 可能落在圆内，不是风圈；
/// - 结构未公开说明、可能变化：解析失败时如实报错，不猜测。
class Typhoon {
  const Typhoon({
    required this.id,
    required this.number,
    required this.nameEn,
    required this.category,
    required this.issueUtc,
    required this.track,
    required this.center,
    required this.forecasts,
    this.pressureHpa,
    this.maxWindMs,
    this.gustMs,
    this.course,
    this.speedKmh,
    this.galeCenter,
    this.galeRadiusM,
    this.stormRadiusM,
    this.intensityJp,
  });

  final String id; // 如 TC2636
  final String number; // 如 2630（年份后两位 + 序号）
  final String? nameEn;
  final String category; // TY / STS / TS / TD
  final DateTime issueUtc;

  /// 过去路径（含热带低压阶段），按时间顺序。
  final List<LatLng> track;
  final LatLng center;
  final double? pressureHpa;
  final double? maxWindMs;
  final double? gustMs;

  /// 移动方向（已转为中文，如“西偏北”）与速度。
  final String? course;
  final double? speedKmh;

  /// 大风区（15 m/s 以上）近似圆与暴风区（25 m/s 以上）半径。
  final LatLng? galeCenter;
  final double? galeRadiusM;
  final double? stormRadiusM;
  final String? intensityJp;
  final List<TyphoonForecast> forecasts;

  String get categoryLabel => switch (category) {
    'TY' => '台风',
    'STS' => '强热带风暴',
    'TS' => '热带风暴',
    'TD' => '热带低压',
    _ => category,
  };

  /// 强度描述（JMA：強い / 非常に強い / 猛烈な）。
  String? get intensityLabel => switch (intensityJp) {
    '強い' => '强',
    '非常に強い' => '非常强',
    '猛烈な' => '猛烈',
    _ => null,
  };

  String get title => '${nameEn ?? '未命名'}（${number.isEmpty ? id : number}）';

  List<LatLng> get allPoints => [
    ...track,
    center,
    for (final f in forecasts) f.center,
  ];
}

class TyphoonForecast {
  const TyphoonForecast({
    required this.hours,
    required this.validUtc,
    required this.center,
    this.probabilityRadiusM,
    this.pressureHpa,
    this.maxWindMs,
  });

  final int hours;
  final DateTime validUtc;
  final LatLng center;

  /// 70% 概率圆半径（m）。
  final double? probabilityRadiusM;
  final double? pressureHpa;
  final double? maxWindMs;
}

/// JMA 十六方位（日文汉字）→ 中文。
String? typhoonCourseZh(String? jp) => switch (jp) {
  null => null,
  '北' => '北',
  '北北東' => '北偏东',
  '北東' => '东北',
  '東北東' => '东偏北',
  '東' => '东',
  '東南東' => '东偏南',
  '南東' => '东南',
  '南南東' => '南偏东',
  '南' => '南',
  '南南西' => '南偏西',
  '南西' => '西南',
  '西南西' => '西偏南',
  '西' => '西',
  '西北西' => '西偏北',
  '北西' => '西北',
  '北北西' => '北偏西',
  'ほとんど停滞' => '几乎停滞',
  _ => jp,
};

class TyphoonService {
  TyphoonService({StringFetcher? fetcher})
    : fetcher = fetcher ?? defaultFetcher();

  final StringFetcher fetcher;

  static const _base = 'https://www.jma.go.jp/bosai/typhoon/data';

  /// 当前活跃的热带气旋；没有时返回空列表。
  Future<List<Typhoon>> active() async {
    final list = jsonDecode(await fetcher(Uri.parse('$_base/targetTc.json')));
    if (list is! List) throw const FormatException('台风列表格式无法识别');
    final out = <Typhoon>[];
    for (final item in list) {
      final id = (item as Map<String, dynamic>)['tropicalCyclone'] as String?;
      if (id == null) continue;
      final f = await fetcher(Uri.parse('$_base/$id/forecast.json'));
      final s = await fetcher(Uri.parse('$_base/$id/specifications.json'));
      out.add(parse(id: id, forecastJson: f, specificationsJson: s));
    }
    return out;
  }

  static double? _num(Object? v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  static LatLng? _ll(Object? v) => v is List && v.length >= 2
      ? LatLng((v[0] as num).toDouble(), (v[1] as num).toDouble())
      : null;

  static Typhoon parse({
    required String id,
    required String forecastJson,
    required String specificationsJson,
  }) {
    final f = (jsonDecode(forecastJson) as List).cast<Map<String, dynamic>>();
    final s = (jsonDecode(specificationsJson) as List)
        .cast<Map<String, dynamic>>();
    final title = s.firstWhere((p) => p['part'] == 'title');
    final specs = {
      for (final p in s)
        if (p['advancedHours'] is num) (p['advancedHours'] as num).toInt(): p,
    };
    final now = f.firstWhere(
      (p) => p['advancedHours'] == 0,
      orElse: () => throw const FormatException('缺少实况'),
    );
    final track = <LatLng>[
      for (final key in const ['preTyphoon', 'typhoon'])
        for (final pt in (now['track']?[key] as List? ?? const [])) ?_ll(pt),
    ];
    final center = _ll(now['center']);
    if (center == null) throw const FormatException('缺少台风中心');
    final spec0 = specs[0] ?? const <String, dynamic>{};
    final gale = now['galeWarningArea'] as Map<String, dynamic>?;
    // 暴风区：取各段圆弧中最大的半径（近似为圆）。
    double? storm;
    for (final arc in (now['stormWarningArea']?['arc'] as List? ?? const [])) {
      final r = _num((arc as List)[1]);
      if (r != null && (storm == null || r > storm)) storm = r;
    }
    double? wind(Map<String, dynamic>? p, String k) =>
        _num(p?['maximumWind']?[k]?['m/s']);
    return Typhoon(
      id: id,
      number: '${title['typhoonNumber'] ?? ''}',
      nameEn: (title['name'] as Map?)?['en'] as String?,
      category:
          '${(spec0['category'] as Map?)?['en'] ?? (title['category'] as Map?)?['en'] ?? ''}',
      issueUtc: DateTime.parse((title['issue'] as Map)['UTC'] as String),
      track: track,
      center: center,
      pressureHpa: _num(spec0['pressure']),
      maxWindMs: wind(spec0, 'sustained'),
      gustMs: wind(spec0, 'gust'),
      course: typhoonCourseZh(spec0['course'] as String?),
      speedKmh: _num((spec0['speed'] as Map?)?['km/h']),
      intensityJp: spec0['intensity'] as String?,
      galeCenter: _ll(gale?['center']),
      galeRadiusM: _num(gale?['radius']),
      stormRadiusM: storm,
      forecasts: [
        for (final p in f)
          if (p['advancedHours'] is num && (p['advancedHours'] as num) > 0)
            if (_ll(p['center']) case final c?)
              TyphoonForecast(
                hours: (p['advancedHours'] as num).toInt(),
                validUtc: DateTime.parse(
                  (p['validtime'] as Map)['UTC'] as String,
                ),
                center: c,
                probabilityRadiusM: _num(p['probabilityCircle']?['radius']),
                pressureHpa: _num(
                  specs[(p['advancedHours'] as num).toInt()]?['pressure'],
                ),
                maxWindMs: wind(
                  specs[(p['advancedHours'] as num).toInt()],
                  'sustained',
                ),
              ),
      ],
    );
  }
}
