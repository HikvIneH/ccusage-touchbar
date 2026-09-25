#!/bin/zsh
# Builds CCUsageBar.app next to this script. Local build: no quarantine, no Gatekeeper prompt.
set -e
cd "${0:A:h}"
APP=CCUsageBar.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O main.swift notch.swift details.swift usage.swift alerts.swift bridge.swift prompt.swift -o $APP/Contents/MacOS/CCUsageBar
cp ccusage-line.sh $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.hikvineh.ccusagebar</string>
  <key>CFBundleName</key><string>CCUsageBar</string>
  <key>CFBundleExecutable</key><string>CCUsageBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - $APP
echo built $PWD/$APP
