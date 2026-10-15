# 2026-10-15 审计证据

基线业务提交：b00d707；Web 产物来源：GitHub Actions 38681970611。

- baseline-tests.log：原有 169 项测试全部通过。
- cache-identity-probes.log：4 项独立诊断复现成功；通过代表发现问题，不代表修复。
- cache-identity-probes.dart.txt：历史诊断源码，避免纳入正式回归测试。需要复现时复制到项目 test/audit_probe_test.dart，再用 `flutter test --no-pub test/audit_probe_test.dart` 运行。后续修复后这些“当前缺陷存在”的断言应失败。
- PNG：同一 CI Web 产物在 390×844、暗色模式下的实际截图；未使用真实用户位置。

截图覆盖引导、行程首页、线路详情、离线说明和 Pro 方案预览。天气来源/地图在当前桌面网络下可用不代表大陆移动网络或真实手机已验收。完整边界与缺陷条件见 ../../maturity-audit-2026-10-15.md。
