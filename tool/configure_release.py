#!/usr/bin/env python3
"""给 `flutter create` 生成的平台工程注入发布身份与签名（CI 使用，本地可重复运行）。

- Android：applicationId 改为 APP_ID（namespace / Kotlin 包路径保持 dev.trailweather.trailweather 不变）；
  若环境变量 ANDROID_KEYSTORE_PATH 指向的签名文件存在，release 构建使用该签名，
  密码与别名在 Gradle 执行时从环境变量读取，绝不写入任何文件；否则保留 debug 签名并明确告警。
  debug / profile 构建的应用 ID 加后缀 DEBUG_SUFFIX，与正式签名包在同一台手机上共存（签名不同不能互相覆盖）。
- iOS：PRODUCT_BUNDLE_IDENTIFIER 改为 APP_ID（RunnerTests 随之改为 APP_ID.RunnerTests）。

用法：python3 tool/configure_release.py --platform android|ios [--check]
"""

import argparse
import os
import pathlib
import re
import sys

APP_ID = 'app.shanqing.hiking'
OLD_ID = 'dev.trailweather.trailweather'
DEBUG_SUFFIX = '.dev'
DEV_MARK = 'shanqing-dev-suffix'
DEV_BLOCK = f'''        // {DEV_MARK}：debug / profile 构建与正式签名包共存
        debug {{
            applicationIdSuffix = "{DEBUG_SUFFIX}"
        }}
        // Flutter 插件在 android {{}} 之前就按 debug 复制出 profile，需单独设置
        getByName("profile") {{
            applicationIdSuffix = "{DEBUG_SUFFIX}"
        }}
'''
# 早先版本只给 debug 加了后缀，重新运行时替换掉
OLD_DEV_BLOCK = f'''        debug {{
            applicationIdSuffix = "{DEBUG_SUFFIX}"
        }}
'''
ROOT = pathlib.Path(__file__).resolve().parent.parent

SIGNING_BLOCK = '''
    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH"))
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            storeType = "pkcs12"
        }
    }
'''


def android(check: bool) -> bool:
    gradle = ROOT / 'android/app/build.gradle.kts'
    s = gradle.read_text(encoding='utf-8')
    if f'applicationId = "{OLD_ID}"' in s:
        s = s.replace(f'applicationId = "{OLD_ID}"', f'applicationId = "{APP_ID}"', 1)
    if f'applicationId = "{APP_ID}"' not in s:
        sys.exit('未找到 applicationId，模板可能已变化，请人工核对 build.gradle.kts')

    if DEV_MARK not in s:
        s = s.replace(OLD_DEV_BLOCK, '')
        if '    buildTypes {\n' not in s:
            sys.exit('未找到 buildTypes，模板可能已变化')
        s = s.replace('    buildTypes {\n', '    buildTypes {\n' + DEV_BLOCK, 1)

    keystore = os.environ.get('ANDROID_KEYSTORE_PATH', '')
    signed = bool(keystore) and pathlib.Path(keystore).is_file()
    if signed and 'signingConfigs {' not in s:
        s = s.replace('    buildTypes {', SIGNING_BLOCK.lstrip('\n') + '\n    buildTypes {', 1)
        s, n = re.subn(
            r'signingConfig = signingConfigs\.getByName\("debug"\)',
            'signingConfig = signingConfigs.getByName("release")',
            s,
            count=1,
        )
        if n != 1:
            sys.exit('未找到 release 的 debug 签名配置，模板可能已变化')
    if not check:
        gradle.write_text(s, encoding='utf-8')
    print(f'Android applicationId = {APP_ID}（debug / profile 构建为 {APP_ID}{DEBUG_SUFFIX}）')
    print('Android release 签名：' + ('正式签名（来自 Secrets）' if signed else 'debug 签名（未配置 Secrets，不可用于正式分发）'))
    return signed


def ios(check: bool) -> None:
    pbx = ROOT / 'ios/Runner.xcodeproj/project.pbxproj'
    s = pbx.read_text(encoding='utf-8')
    s = s.replace(f'PRODUCT_BUNDLE_IDENTIFIER = {OLD_ID}', f'PRODUCT_BUNDLE_IDENTIFIER = {APP_ID}')
    if f'PRODUCT_BUNDLE_IDENTIFIER = {APP_ID};' not in s:
        sys.exit('未找到 PRODUCT_BUNDLE_IDENTIFIER，模板可能已变化')
    if not check:
        pbx.write_text(s, encoding='utf-8')
    print(f'iOS Bundle ID = {APP_ID}')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--platform', choices=['android', 'ios'], required=True)
    parser.add_argument('--check', action='store_true', help='只检查不写入')
    args = parser.parse_args()
    if args.platform == 'android':
        android(args.check)
    else:
        ios(args.check)


if __name__ == '__main__':
    main()
