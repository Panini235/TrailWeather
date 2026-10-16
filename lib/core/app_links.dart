/// 分享图里“扫码下载”的地址。
///
/// CI 构建时注入本次工作流运行页：
/// `--dart-define=SHANQING_DOWNLOAD_URL=<server>/<repo>/actions/runs/<run_id>`；
/// 本地构建回退到 CI 工作流列表页（长期有效）。
/// 注意：GitHub Actions 产物需登录 GitHub 才能下载，且有保留期限；正式分发前应换成商店或固定下载页。
const String kDownloadUrl = String.fromEnvironment(
  'SHANQING_DOWNLOAD_URL',
  defaultValue:
      'https://github.com/Panini235/TrailWeather/actions/workflows/ci.yml',
);

/// 分享图上的一句宣传语。
const String kShareSlogan = '山晴 · 出发前，看懂沿途天气';
