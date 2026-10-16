#!/usr/bin/env bash
# 生成山晴 Android 正式签名，并上传到 GitHub Secrets（由你本人在终端运行）。
#
# - 密码只在本终端输入（不回显），只经环境变量传给 keytool / gh，不写入任何文件或命令历史；
# - 签名文件默认保存为 ~/shanqing-release.jks，已存在则拒绝覆盖；
# - 结束时打印证书指纹（SHA-1 / SHA-256 / MD5）与公钥，供 App 备案、应用商店、地图 SDK 使用。
#
# 用法：bash tool/create_android_keystore.sh [签名文件路径]
set -euo pipefail

KS="${1:-$HOME/shanqing-release.jks}"
ALIAS="shanqing"
REPO="Panini235/TrailWeather"

if ! /usr/libexec/java_home >/dev/null 2>&1; then
  echo "需要先安装 JDK 17：brew install --cask temurin@17"
  exit 1
fi
command -v gh >/dev/null || { echo "需要 gh 命令行并已登录"; exit 1; }
if [ -e "$KS" ]; then
  echo "已存在 $KS ，为避免覆盖现有签名已退出。"
  exit 1
fi

read -r -s -p "设置签名密码（至少 8 位，输入时不显示）：" SQ_PASS; echo
read -r -s -p "再输入一次：" SQ_PASS2; echo
if [ "$SQ_PASS" != "$SQ_PASS2" ]; then echo "两次输入不一致"; exit 1; fi
if [ "${#SQ_PASS}" -lt 8 ]; then echo "密码太短（至少 8 位）"; exit 1; fi
unset SQ_PASS2
export SQ_PASS

keytool -genkeypair -storetype PKCS12 -keystore "$KS" -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Shanqing, OU=Mobile, O=Shanqing, C=CN" \
  -storepass:env SQ_PASS -keypass:env SQ_PASS
chmod 600 "$KS"
echo "已生成：$KS"

echo "上传到 GitHub Secrets（$REPO）…"
base64 -i "$KS" | gh secret set ANDROID_KEYSTORE_BASE64 --repo "$REPO"
printf '%s' "$SQ_PASS" | gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$REPO"
printf '%s' "$SQ_PASS" | gh secret set ANDROID_KEY_PASSWORD --repo "$REPO"
printf '%s' "$ALIAS" | gh secret set ANDROID_KEY_ALIAS --repo "$REPO"

echo
echo "证书指纹："
keytool -list -v -keystore "$KS" -alias "$ALIAS" -storepass:env SQ_PASS | grep -E "SHA1:|SHA256:" || true
CERT="$(keytool -exportcert -rfc -keystore "$KS" -alias "$ALIAS" -storepass:env SQ_PASS)"
echo "$CERT" | openssl x509 -noout -fingerprint -md5
echo "公钥（App 备案用）："
echo "$CERT" | openssl x509 -noout -pubkey
unset SQ_PASS

cat <<EOF

完成。请立即备份 $KS 到至少两个离线位置，并把密码存进密码管理器。
丢失签名文件或密码，已安装的用户将无法升级（只能卸载重装，本机数据会丢失）。
不要把签名文件放进代码仓库、公开网盘或任何聊天里。
EOF
