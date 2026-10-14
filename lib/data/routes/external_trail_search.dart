/// 外部攻略检索入口：只构造用户主动打开的网页搜索链接，不抓取、解析或缓存平台内容。
class ExternalTrailSearchTarget {
  const ExternalTrailSearchTarget({
    required this.id,
    required this.label,
    required this.siteHost,
    required this.uri,
  });

  final String id;
  final String label;
  final String siteHost;
  final Uri uri;
}

abstract final class ExternalTrailSearch {
  static List<ExternalTrailSearchTarget> targets(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) return const [];
    return [
      _target('xiaohongshu', '小红书攻略', 'xiaohongshu.com', query),
      _target('2bulu', '两步路轨迹', '2bulu.com', query),
      _target('foooooot', '六只脚线路', 'foooooot.com', query),
    ];
  }

  static ExternalTrailSearchTarget _target(
    String id,
    String label,
    String siteHost,
    String query,
  ) {
    return ExternalTrailSearchTarget(
      id: id,
      label: label,
      siteHost: siteHost,
      uri: Uri.https('www.baidu.com', '/s', {
        'wd': 'site:$siteHost $query 徒步 路线',
      }),
    );
  }
}
