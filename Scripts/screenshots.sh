#!/bin/zsh
# screenshots.sh — App Store screenshots from the simulator, fully scripted.
# Builds Debug, seeds fictional data (DemoSeed, --demo-seed), navigates via the
# DEBUG deep links, and saves 6.9" PNGs (1320×2868) to Screenshots/.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=/Applications/Xcode.app
DEVICE="iPhone 17 Pro Max"
BUNDLE="com.maw.ember"
OUT="Screenshots"
DERIVED="build/DerivedData"

ANNA="DE300002-0000-4000-8000-000000000002"   # DemoSeed.annaID
PRIYA="DE300004-0000-4000-8000-000000000004"  # DemoSeed.priyaID

xcodebuild -project Ember.xcodeproj -scheme Ember \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DERIVED" build

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Ember.app"
UDID=$(xcrun simctl list devices available | grep "$DEVICE (" | head -1 | grep -oE '[0-9A-F-]{36}')

# Fresh boot: stale system dialogs (e.g. an old "Open in Ember?") survive app
# relaunches and would photobomb every shot.
xcrun simctl shutdown "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override --time "9:41" \
  --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$UDID" "$APP"
mkdir -p "$OUT"

# Fresh launch per shot: presentation state (sheets, pushes) can't be unwound
# from outside, and the seed is deterministic anyway. Navigation goes through
# --demo-link (simctl openurl would hit the un-tappable "Open in Ember?" dialog).
launch() {
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$UDID" "$BUNDLE" --demo-seed -hasCompletedOnboarding YES "$@"
  sleep 6
}
snap() { xcrun simctl io "$UDID" screenshot "$OUT/$1.png"; echo "📸 $1"; }

launch
snap 01-today

launch --demo-variant chips
snap 02-capture-chips

launch --demo-link "ember://person/$ANNA"
snap 03-person

launch --demo-link "ember://compose/$PRIYA"
snap 04-compose

launch --demo-link "ember://tab/journal"
snap 05-journal

launch --demo-link "ember://tab/people"
snap 06-people

launch --demo-link "ember://settings"
snap 07-settings

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear
echo "Done → $OUT/"
