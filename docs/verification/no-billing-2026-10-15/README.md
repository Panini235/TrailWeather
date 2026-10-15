# 隐藏订阅的验收证据

代码：a699aca（包含18be281的界面改动）。

- 本地analyze无问题，171项测试通过；local-tests.log保留结果。
- GitHub Actions 38699456479：analyze/test/Web/APK成功。
- GitHub Actions 38699460743：iOS release --no-codesign成功。
- 使用上述CI的web-release产物，在390×844暗色浏览器核验：首次引导无Pro/试用，进入示例成功，设置上/下方无会员与PRO入口，直接访问旧/paywall回到首页。

截图是实际产物；没有访问真实用户位置、登录或支付。尚未完成真机手势、耗电和离线可靠性验收。
