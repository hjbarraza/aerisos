#!/bin/bash
# Build Keysheet, the ⌘K shortcut cheat sheet, into ~/Applications/Keysheet.app.
# skhd opens it (`cmd - k` in skhdrc); it lists the hotkeys in ~/.config/skhd/skhdrc.
# Söhne is licensed, so it is not in this repo: the fonts are copied from ~/Library/Fonts
# when present, and the app falls back to SF Mono and the system font otherwise.

set -euo pipefail

app=$HOME/Applications/Keysheet.app/Contents
mkdir -p "$app/MacOS" "$app/Resources"
swiftc -O "$(dirname "$0")/main.swift" -o "$app/MacOS/Keysheet"

cat > "$app/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Keysheet</string>
<key>CFBundleIdentifier</key><string>local.keysheet</string>
<key>CFBundleName</key><string>Keysheet</string>
<key>LSUIElement</key><true/>
<key>ATSApplicationFontsPath</key><string>.</string>
</dict></plist>
EOF

for font in SohneMono-Buch SohneMono-Kraftig Sohne-Buch Sohne-Kraftig; do
  if [[ -f "$HOME/Library/Fonts/$font.otf" ]]; then
    cp "$HOME/Library/Fonts/$font.otf" "$app/Resources/"
  else
    echo "missing $font.otf, using the system font"
  fi
done

pkill -x Keysheet || true
echo "built $app"
