#!/bin/sh
# bundle.sh SRC_DIR OUT_APP: builds SRC_DIR's sources into OUT_APP (a JebDesktop.app, ad-hoc signed,
# LSUIElement, no Dock icon). JEB_STAMP is the build stamp (CFBundleVersion; default: now);
# JEB_PREBUILT is a binary to use instead of compiling (the updater ships the exact binary its
# gates ran); JebMod in Info.plist is JEB_BUNDLE_MOD when set, else JEB_MOD. Never touches src/JebDesktop: it builds under OUT_APP's own parent.
set -e
src=$(cd "$1" && pwd)
out=$2
stamp=${JEB_STAMP:-$(date -u +%Y%m%d-%H%M%S)}
# The mod folder the app reads its art from (JEB_BUNDLE_MOD when set, else JEB_MOD), kept in the bundle so an
# instance started by a hand-over, with no launchd environment, still finds it. JEB_BUNDLE_MOD is for a
# release build, whose JEB_MOD is a staging copy that is deleted after the update.
mod_xml=$(printf '%s' "${JEB_BUNDLE_MOD:-${JEB_MOD:-}}" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
mod_key=""
[ -n "$mod_xml" ] && mod_key="<key>JebMod</key><string>$mod_xml</string>"
rm -rf "$out"
mkdir -p "$out/Contents/MacOS"
if [ -n "$JEB_PREBUILT" ]; then
  cp "$JEB_PREBUILT" "$out/Contents/MacOS/JebDesktop"
else
  JEB_OUT="$out/Contents/MacOS/JebDesktop" sh "$src/build.sh"
fi
cat > "$out/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.jeb.desktop</string>
  <key>CFBundleName</key><string>JebDesktop</string>
  <key>CFBundleExecutable</key><string>JebDesktop</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$stamp</string>
  <key>CFBundleShortVersionString</key><string>$stamp</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSAppSleepDisabled</key><true/>
  $mod_key
</dict>
</plist>
PLIST
chmod 755 "$out/Contents/MacOS/JebDesktop"
codesign --force -s - "$out"
echo "$out $stamp"
