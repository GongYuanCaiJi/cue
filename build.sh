#!/bin/sh
# cue:半透明念稿浮窗。把稿(例如瀏覽器開的講稿)半透明疊在自拍畫面上念,面試/錄影用。
# 無完整 Xcode 也能編(用 swiftc + 系統 framework)。
#
# 簽章:若本機有固定自簽憑證(cue.keychain 裡的 CueStable)就用它簽 ——
# 這樣重編後不用每次重新授權「螢幕錄製」(TCC 認的是憑證身分,不是檔案雜湊)。
# 憑證是本機自簽、機器獨有,不進版控。keychain 若上鎖,先 export CUE_KEYCHAIN_PW=... 再跑。
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/pin-agent/Pin"
KCPATH="$HOME/Library/Keychains/cue.keychain-db"
APP=/Applications/cue.app
BIN=/tmp/cue.bin

cd "$SRC"
echo "== 編譯 =="
swiftc -O Sources/Core/*.swift Sources/App/*.swift -o "$BIN" \
  -framework AppKit -framework ScreenCaptureKit -framework AVFoundation \
  -framework CoreGraphics -framework QuartzCore -framework Foundation

echo "== 打包 =="
pkill -x cue 2>/dev/null || true
sleep 1
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/cue"
cp Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string cue "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string local.cue "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string cue "$APP/Contents/Info.plist"

echo "== 簽章 =="
if [ -f "$KCPATH" ]; then
  security unlock-keychain -p "${CUE_KEYCHAIN_PW:-}" "$KCPATH" 2>/dev/null || true
  codesign --force --deep --sign CueStable --keychain "$KCPATH" --identifier local.cue "$APP" \
    || codesign --force --deep --sign - --identifier local.cue "$APP"
else
  # 沒有固定憑證就用 ad-hoc(每次重編會要求重新授權螢幕錄製)
  codesign --force --deep --sign - --identifier local.cue "$APP"
fi
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

open "$APP"
echo "✅ 已安裝並啟動 /Applications/cue.app（選單列會出現圖釘圖示）"
