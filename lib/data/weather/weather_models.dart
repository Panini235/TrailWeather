/// 天气统一数据模型：一切以“数据真实性 / 来源透明”为最高优先级。
///
/// 设计约束：
/// - 任何指标都可能缺失（null），UI 必须显示“此来源未提供”，不得显示 0；
/// - 降水概率（%）与降水量（mm）是不同变量，阵风与持续风速是不同变量；
/// - 每个点、每次返回都携带溯源元数据（WxProvenance）；
/// - 请求坐标 ≠ 数据实际对应坐标；网格中心不是气象站；
/// - 内部时间一律 UTC；来源时区偏移单独携带用于展示。
library;

/// 天气变量。键名即内部标准单位。
enum WxVar {
  temperature('°C'),
  apparentTemp('°C'),
  precip('mm'),
  precipProb('%'),
  windSpeed('m/s'),
  windGust('m/s'),
  windDir('°'),
  humidity('%'),
  cloudCover('%'),
  visibility('m'),
  pressure('hPa'),
  // 追加在末尾：缓存按枚举下标编码，不能改变已有成员顺序。
  /// 降水中降雪所占比例（meteoblue snowfraction），不是降雪量。
  snowFraction('%');

  const WxVar(this.stdUnit);
  final String stdUnit;

  String get label => switch (this) {
    temperature => '温度',
    apparentTemp => '体感温度',
    precip => '降水量',
    precipProb => '降水概率',
    windSpeed => '持续风速',
    windGust => '阵风',
    windDir => '风向',
    humidity => '湿度',
    cloudCover => '云量',
    visibility => '能见度',
    pressure => '气压',
    snowFraction => '降雪占比',
  };
}

/// 数据类型：观测 / 模型分析 / 预报 / 远期趋势。
enum WxDataKind { observation, modelAnalysis, forecast, trend }

String wxDataKindLabel(WxDataKind k) => switch (k) {
  WxDataKind.observation => '站点观测',
  WxDataKind.modelAnalysis => '模型估计（分析）',
  WxDataKind.forecast => '短期预报',
  WxDataKind.trend => '远期趋势',
};

/// 位置颗粒度：网格 / 站点 / 区域 / 城市 / 未知。
enum WxGranularity { grid, station, area, city, unknown }

String wxGranularityLabel(WxGranularity g) => switch (g) {
  WxGranularity.grid => '网格预报',
  WxGranularity.station => '站点观测',
  WxGranularity.area => '区域级',
  WxGranularity.city => '城市级',
  WxGranularity.unknown => '未知颗粒度',
};

/// 来源能力声明。接入任何新来源前必须如实填写并在 docs/data-sources.md 登记。
class ProviderCapabilities {
  const ProviderCapabilities({
    required this.providerId,
    required this.vendor,
    required this.displayName,
    required this.modelOrNetwork,
    required this.coverage,
    required this.forecastHorizonDays,
    required this.intervalHours,
    required this.batchCoordinates,
    required this.maxPointsPerRequest,
    required this.granularity,
    required this.dataKind,
    required this.requiresApiKey,
    required this.browserCorsOk,
    required this.browserNotes,
    required this.license,
    required this.attribution,
    required this.supportedVars,
    required this.minRequestIntervalMs,
    required this.recommendedCacheTtl,
    this.spatialResolutionNote,
    this.modelOverlapNote,
    this.onDemandOnly = false,
    this.usesElevation = false,
    this.quotaNote,
  });

  final String providerId; // 如 'open-meteo:best_match'
  final String vendor; // API 服务商
  final String displayName;
  final String modelOrNetwork; // 实际模型/观测网络；未知时写“未知”并说明
  final String coverage;
  final int forecastHorizonDays;
  final int intervalHours;
  final bool batchCoordinates;
  final int maxPointsPerRequest;
  final WxGranularity granularity;
  final WxDataKind dataKind;
  final bool requiresApiKey;
  final bool browserCorsOk;
  final String browserNotes; // Web 端限制（如无法自定义 User-Agent）
  final String license;
  final String attribution;
  final List<WxVar> supportedVars;
  final int minRequestIntervalMs;
  final Duration recommendedCacheTtl;

  /// 空间分辨率说明及依据；无法确定时以 spatialResolutionNote 为 null
  /// 并在 UI 显示“来源未提供空间分辨率，位置颗粒度未确认”。
  final String? spatialResolutionNote;

  /// 与其他来源可能共享底层模型的说明。
  final String? modelOverlapNote;

  /// 按次计费/额度很少的来源：只在用户点击时单点查询，不参与线路自动请求。
  final bool onDemandOnly;

  /// 是否使用请求点海拔（如 meteoblue asl）；为真时缓存键包含海拔。
  final bool usesElevation;

  /// 额度说明（展示给用户）。
  final String? quotaNote;

  bool supports(WxVar v) => supportedVars.contains(v);
}

/// 单次返回的溯源元数据。
class WxProvenance {
  const WxProvenance({
    required this.providerId,
    required this.vendor,
    required this.modelOrNetwork,
    required this.modelKnown,
    required this.requestLat,
    required this.requestLon,
    required this.returnedLat,
    required this.returnedLon,
    required this.locationDetail,
    required this.elevationUsedM,
    required this.granularity,
    required this.spatialResolutionNote,
    required this.dataKind,
    required this.fetchedAtUtc,
    required this.modelRunUtc,
    required this.utcOffsetSeconds,
    required this.license,
    required this.attribution,
    required this.interpolationNote,
    required this.elevationAdjustNote,
    required this.traceNote,
  });

  final String providerId;
  final String vendor;

  /// 实际模型/观测网络名称；modelKnown=false 时 UI 显示“模型未知”。
  final String modelOrNetwork;
  final bool modelKnown;

  // 用户请求的坐标与来源返回的坐标是两回事，必须分开保存。
  final double requestLat;
  final double requestLon;
  final double? returnedLat;
  final double? returnedLon;

  /// 网格中心 / 站点 / 行政区等说明（如来源提供）。
  final String? locationDetail;

  /// 来源计算时使用的海拔（如提供）。
  final double? elevationUsedM;

  final WxGranularity granularity;
  final String? spatialResolutionNote;
  final WxDataKind dataKind;

  final DateTime fetchedAtUtc; // 获取时间
  final DateTime? modelRunUtc; // 模型起报/发布时间（如可获得）

  /// 来源时区偏移（秒）；内部时间一律 UTC。
  final int utcOffsetSeconds;

  final String license;
  final String attribution;

  /// 是否插值、是否海拔修正及其方法说明。
  final String? interpolationNote;
  final String? elevationAdjustNote;

  /// 原始响应追踪：端点+状态摘要，不含坐标（避免敏感位置进入日志）。
  final String? traceNote;

  /// 面向用户的颗粒度声明（如实、不夸大精度）。
  String granularityStatement() {
    final b = StringBuffer();
    switch (granularity) {
      case WxGranularity.grid:
        b.write('所选坐标对应网格预报，非点位实测');
      case WxGranularity.station:
        b.write('附近气象站观测');
      case WxGranularity.area:
        b.write('该来源仅提供区域级天气');
      case WxGranularity.city:
        b.write('该来源仅提供城市级天气，非所选山路点位天气');
      case WxGranularity.unknown:
        b.write('来源未提供位置颗粒度，位置颗粒度未确认');
    }
    if (spatialResolutionNote == null) {
      b.write('；来源未提供空间分辨率，位置颗粒度未确认');
    } else {
      b.write('；$spatialResolutionNote');
    }
    return b.toString();
  }

  Map<String, dynamic> toDisplayMap() => {
    'API 服务商': vendor,
    '模型/原始机构': modelKnown ? modelOrNetwork : '未知（$modelOrNetwork）',
    '数据类型': wxDataKindLabel(dataKind),
    '请求坐标':
        '${requestLat.toStringAsFixed(4)}, ${requestLon.toStringAsFixed(4)}',
    '来源返回坐标': returnedLat == null
        ? '未提供（返回坐标为请求原样）'
        : '${returnedLat!.toStringAsFixed(4)}, ${returnedLon!.toStringAsFixed(4)}',
    '位置详情': locationDetail ?? '未提供',
    '来源使用海拔': elevationUsedM == null
        ? '未提供'
        : '${elevationUsedM!.toStringAsFixed(0)} m（模型地形）',
    '位置颗粒度': wxGranularityLabel(granularity),
    '空间分辨率': spatialResolutionNote ?? '来源未提供',
    '数据有效时间': '见各时段标注（UTC）',
    '获取时间': fetchedAtUtc.toIso8601String(),
    '起报/发布时间': modelRunUtc == null ? '未提供' : modelRunUtc!.toIso8601String(),
    '来源时区偏移':
        'UTC${utcOffsetSeconds >= 0 ? '+' : ''}${(utcOffsetSeconds / 3600).toStringAsFixed(1)}',
    '插值说明': interpolationNote ?? '未插值',
    '海拔修正': elevationAdjustNote ?? '未修正',
    '数据授权': license,
    '署名要求': attribution,
  };
}

/// 一个有效时刻的一组变量值。缺失为 null，绝不用 0 冒充。
class WxHourValue {
  const WxHourValue({
    required this.validFromUtc,
    required this.values,
    this.symbols,
  });

  /// 该小时起有效（UTC 整点）。
  final DateTime validFromUtc;
  final Map<WxVar, double?> values;

  /// 来源专属符号（如 MET symbol_code / WMO code），仅用于图标。
  final Map<String, String>? symbols;

  /// 天气现象粗略图标编码（供 UI 使用，未识别返回 null）。
  String? get iconCode => symbols?['met_symbol'] ?? symbols?['wmo_code'];
}

/// 单点（一个查询坐标）的整段时间序列。
class WxPointForecast {
  const WxPointForecast({
    required this.lat,
    required this.lon,
    required this.hours,
    required this.provenance,
    this.dailySunsetsUtc = const [],
  });

  final double lat;
  final double lon;
  final List<WxHourValue> hours;
  final WxProvenance provenance;

  /// 逐日日落（UTC，升序；Open-Meteo daily sunset，MET 未提供 → 空）。
  final List<DateTime> dailySunsetsUtc;

  /// [utc] 之后的第一次日落（如出发后的当天日落）；来源未提供则 null。
  DateTime? nextSunsetAfter(DateTime utc) {
    for (final s in dailySunsetsUtc) {
      if (s.isAfter(utc)) return s;
    }
    return null;
  }

  DateTime? get firstValidUtc =>
      hours.isEmpty ? null : hours.first.validFromUtc;
  DateTime? get lastValidUtc => hours.isEmpty
      ? null
      : hours.last.validFromUtc.add(const Duration(hours: 1));

  /// 取某个 UTC 时刻所在小时的值；越界返回 null。
  /// 注意：不做任何时间插值，避免制造虚假精度。
  WxHourValue? hourAt(DateTime utc) {
    final t = DateTime.utc(utc.year, utc.month, utc.day, utc.hour);
    for (final h in hours) {
      if (h.validFromUtc == t) return h;
    }
    return null;
  }
}

/// 一个来源对一条线路（多个点）的一次完整结果。
class WxSourceResult {
  const WxSourceResult({
    required this.providerId,
    required this.points,
    required this.fromCache,
    required this.stale,
    required this.cachedAtUtc,
    required this.fetchedAtUtc,
  });

  final String providerId;
  final List<WxPointForecast> points;

  final bool fromCache;
  final bool stale; // 过期缓存（stale-while-revalidate 期间读取）

  /// 缓存写入时间（fromCache 时有值）。
  final DateTime? cachedAtUtc;

  /// 数据获取时间（最新一次真实请求时间）。
  final DateTime fetchedAtUtc;
}
