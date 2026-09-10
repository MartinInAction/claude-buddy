#!/usr/bin/env bash
# Builds ClaudeBuddy.app into ~/Applications, merges the hooks into ~/.claude/settings.json,
# and optionally installs a LaunchAgent so it starts at login.
# Usage: tools/install.sh [--login]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HOME/Applications/ClaudeBuddy.app"
SETTINGS="$HOME/.claude/settings.json"

echo "▸ building (release)"
( cd "$ROOT" && python3 tools/gen_sprites.py >/dev/null && swift build -c release 2>&1 | tail -1 )
BIN="$ROOT/.build/release/ClaudeBuddy"
RES="$ROOT/.build/release/ClaudeBuddy_ClaudeBuddy.bundle"

echo "▸ assembling $APP"
pkill -x ClaudeBuddy 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeBuddy"
cp "$ROOT"/Sources/ClaudeBuddy/Resources/*.png "$APP/Contents/Resources/"
[[ -d "$RES" ]] && cp -R "$RES" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Claude Buddy</string>
  <key>CFBundleDisplayName</key><string>Claude Buddy</string>
  <key>CFBundleIdentifier</key><string>com.local.claude-buddy</string>
  <key>CFBundleExecutable</key><string>ClaudeBuddy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "▸ merging hooks into $SETTINGS"
mkdir -p "$(dirname "$SETTINGS")"
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
python3 - "$SETTINGS" "$ROOT/hooks/settings.hooks.json" <<'PY'
import json, sys
settings_path, hooks_path = sys.argv[1], sys.argv[2]
settings = json.load(open(settings_path))
new = json.load(open(hooks_path))["hooks"]
hooks = settings.setdefault("hooks", {})
def is_buddy(entry):
    return any(h.get("type") == "http" and "127.0.0.1:4789" in h.get("url", "") for h in entry.get("hooks", []))
for event, entries in new.items():
    existing = [e for e in hooks.get(event, []) if not is_buddy(e)]   # replace any older buddy entry
    hooks[event] = existing + entries
json.dump(settings, open(settings_path, "w"), indent=2)
print("   hooks registered for:", ", ".join(new))
PY

if [[ "${1:-}" == "--login" ]]; then
  PLIST="$HOME/Library/LaunchAgents/com.local.claude-buddy.plist"
  echo "▸ installing LaunchAgent $PLIST"
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.local.claude-buddy</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/ClaudeBuddy</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict></plist>
PL
  launchctl bootout "gui/$(id -u)/com.local.claude-buddy" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
fi

echo "▸ launching"
open "$APP"
echo "done. Start a Claude Code session and watch the corner of your screen."
