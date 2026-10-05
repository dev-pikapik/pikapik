#!/bin/bash
set -euo pipefail

DEST="/Applications/pikapik.app"
BUNDLE_ID="com.pikapik.app.direct"

say() { printf '\033[1m→ %s\033[0m\n' "$1"; }

if [ -d "$DEST" ]; then
    say "Removing from login items"
    pkill -x pikapik 2>/dev/null || true
    sleep 1
    open -W -n "$DEST" --args --uninstall 2>/dev/null || true
fi

pkill -x pikapik 2>/dev/null || true

say "Deleting the app"
if [ -d "$DEST" ]; then
    SUDO=""
    [ -w /Applications ] || SUDO="sudo"
    $SUDO rm -rf "$DEST"
fi

say "Resetting permissions and settings"
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "pikapik is uninstalled."
