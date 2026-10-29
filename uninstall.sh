#!/bin/bash
set -euo pipefail

DEST="/Applications/pikapik.app"
BUNDLE_ID="com.pikapik.app.direct"

say() { printf '\033[1m→ %s\033[0m\n' "$1"; }
ours() { [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null)" = "$BUNDLE_ID" ]; }
# The App Store version runs under the same process name, so quit only what runs from our copy.
quit_ours() { if ours "$DEST"; then pkill -f "^$DEST/" 2>/dev/null || true; fi; }

if ours "$DEST"; then
    say "Removing from login items"
    quit_ours
    sleep 1
    open -W -n "$DEST" --args --uninstall 2>/dev/null || true
fi

quit_ours

say "Deleting the app"
SUDO=""
[ -w /Applications ] || SUDO="sudo"
if ours "$DEST"; then
    $SUDO rm -rf "$DEST"
elif [ -e "$DEST" ]; then
    say "Leaving $DEST in place: it isn't the GitHub version (for example, pikapik from the App Store)"
fi

FANS="/Library/PrivilegedHelperTools/$BUNDLE_ID.fans"
if [ -e "$FANS" ]; then
    say "Removing fan control"
    sudo launchctl bootout "system/$BUNDLE_ID.fans" >/dev/null 2>&1 || true
    [ ! -e "$FANS.turned-off" ] || sudo /bin/sh -c '"$1" --restore >/dev/null 2>&1 & p=$!; (sleep 30; kill $p) >/dev/null 2>&1 & w=$!; wait $p; kill $w 2>/dev/null' sh "$FANS" || true
    # The monitor sizes the helper added: only files carrying pikapik's mark, then the folders left empty.
    sudo /bin/sh -c 'for f in "$1"/Contents/Resources/Overrides/DisplayVendorID-*/DisplayProductID-*; do [ -f "$f" ] && [ ! -L "$f" ] && /usr/bin/grep -q "<key>pikapik</key>" "$f" && /bin/rm -f "$f"; done; /bin/rmdir "$1"/Contents/Resources/Overrides/DisplayVendorID-* "$1"/Contents/Resources/Overrides "$1"/Contents/Resources "$1"/Contents "$1" 2>/dev/null; true' sh /Library/Displays || true
    sudo rm -f "$FANS" "$FANS.new" "$FANS.turned-off" "/Library/LaunchDaemons/$BUNDLE_ID.fans.plist"
fi

say "Resetting permissions and settings"
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"

echo "pikapik is uninstalled."
