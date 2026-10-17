/// 发布开关（编译期）。
///
/// 徒步星球线路库（B-011）：来源仓库未声明许可，正式分发前需拿到作者与上游数据的授权。
/// 测试版默认关闭：入口隐藏，`assets/planet/` 也不列入 pubspec，数据不打包进安装包。
/// 拿到授权后：在 pubspec.yaml 的 assets 里加上 `assets/planet/`，并以
/// `--dart-define=SHANQING_PLANET_TRAILS=true` 构建（或改默认值）。
const bool kPlanetTrailsEnabled = bool.fromEnvironment(
  'SHANQING_PLANET_TRAILS',
);
