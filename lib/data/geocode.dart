import 'dart:convert';

import '../core/wx_http.dart';

/// 地点搜索结果（Open-Meteo Geocoding API）。
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.name,
    required this.admin,
    required this.country,
    required this.lat,
    required this.lon,
    required this.timezone,
  });

  final String name;
  final String? admin;
  final String? country;
  final double lat;
  final double lon;

  /// 该地点的 IANA 时区（来自地理编码数据库），用于展示“线路当地时区”。
  final String? timezone;

  String get displayName =>
      [name, admin, country].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
}

/// 地点搜索：Open-Meteo Geocoding（免费、无密钥、CORS 开放；实测 2026-10-13）。
/// 返回结果的 timezone 字段是地理数据库属性，不代表天气数据分辨率。
class GeocodeService {
  GeocodeService({WxHttp? http}) : _http = http ?? WxHttp(maxRetries: 1);

  final WxHttp _http;

  Future<List<PlaceSuggestion>> search(String query,
      {String language = 'zh', int count = 8}) async {
    if (query.trim().isEmpty) return const [];
    final uri = Uri(
      scheme: 'https',
      host: 'geocoding-api.open-meteo.com',
      path: '/v1/search',
      queryParameters: {
        'name': query.trim(),
        'count': '$count',
        'language': language,
      },
    );
    final body = await _http.getText(uri);
    final m = jsonDecode(body) as Map<String, dynamic>;
    final results = (m['results'] as List? ?? const []);
    return [
      for (final r in results)
        if (r is Map<String, dynamic>)
          PlaceSuggestion(
            name: r['name'] as String? ?? '',
            admin: r['admin1'] as String?,
            country: r['country'] as String?,
            lat: (r['latitude'] as num).toDouble(),
            lon: (r['longitude'] as num).toDouble(),
            timezone: r['timezone'] as String?,
          ),
    ];
  }
}
