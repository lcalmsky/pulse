#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$root/build}"
app="$output/Pulse.app"
binary="$root/.build/release/pulse"

cd "$root"

build_args=(-c release)
if [[ "${SWIFT_BUILD_DISABLE_SANDBOX:-0}" == "1" ]]; then
    build_args+=(--disable-sandbox)
fi
swift build "${build_args[@]}"

version="$("$binary" --version | awk '{print $2}')"
if [[ -z "$version" ]]; then
    echo "pulse --version 에서 버전을 읽지 못했습니다" >&2
    exit 1
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/pulse"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.lcalmsky.pulse</string>
    <key>CFBundleName</key>
    <string>Pulse</string>
    <key>CFBundleDisplayName</key>
    <string>Pulse</string>
    <key>CFBundleExecutable</key>
    <string>pulse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$version</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$app"
echo "$app"
