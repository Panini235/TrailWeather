import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/routes/external_trail_search.dart';

void main() {
  test('外部攻略入口只生成用户主动打开的百度站点限定搜索', () {
    final targets = ExternalTrailSearch.targets(' 武功山穿越 ');

    expect(targets, hasLength(3));
    expect(targets.map((target) => target.id), [
      'xiaohongshu',
      '2bulu',
      'foooooot',
    ]);
    for (final target in targets) {
      expect(target.uri.scheme, 'https');
      expect(target.uri.host, 'www.baidu.com');
      expect(target.uri.path, '/s');
      expect(target.uri.queryParameters['wd'], contains('武功山穿越'));
      expect(target.uri.queryParameters['wd'], contains(target.siteHost));
      expect(target.uri.queryParameters['wd'], contains('徒步 路线'));
    }
  });

  test('空关键词不生成外部链接', () {
    expect(ExternalTrailSearch.targets('  '), isEmpty);
  });
}
