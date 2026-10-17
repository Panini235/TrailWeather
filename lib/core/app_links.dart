/// 应用版本（与 pubspec.yaml 的 version 一致，由 test/unit/app_version_test.dart 保证）。
const String kAppVersion = '0.2.0-beta.2';

/// 分享图里“扫码下载”的地址：GitHub Releases 列表页。
///
/// 公开仓库的 Release 附件无需登录即可下载，也不会像 Actions 产物那样过期；
/// 列表页包含测试版（`releases/latest` 不含预发布版本，所以不用它）。
/// 上架商店后换成商店或固定下载页。
const String kDownloadUrl = String.fromEnvironment(
  'SHANQING_DOWNLOAD_URL',
  defaultValue: 'https://github.com/Panini235/TrailWeather/releases',
);

/// 分享图上的一句宣传语。
const String kShareSlogan = '山晴 · 出发前，看懂沿途天气';

/// 测试版问题反馈入口（公开仓库的 Issues，提交需登录 GitHub）。
const String kFeedbackUrl = 'https://github.com/Panini235/TrailWeather/issues';
