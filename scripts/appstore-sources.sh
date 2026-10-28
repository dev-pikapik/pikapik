#!/bin/bash
# Usage: scripts/appstore-sources.sh [--tests]
# Prints the Swift files of the App Store build, one per line; --tests leaves out main.swift and App.swift for the test lines in CONTRIBUTING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

{ find Sources -name '*.swift'; echo Extensions/Convert/ConvertFormats.swift; echo Extensions/Preview/ZipNames.swift; } | while IFS= read -r f; do
    case $f in
        */Tools/Uninstaller/AppIdentity.swift|*/Tools/Uninstaller/AppOwnerIndex.swift|*/Tools/Uninstaller/AppFootprint.swift) ;;
        */Core/Updater.swift|*/Permissions/LeftoverPermissions*.swift|*/Tools/Fans/*|*/Tools/Player/*|*/Tools/Animations/*|*/Tools/KeyRepeat/*|*/Tools/Mouse/PointerTool.swift|*/Tools/Mouse/MiddleClick*|*/Tools/Dock/DockDisplay*|*/Tools/DisplayScale/*|*/Tools/Uninstaller/*) continue ;;
        */main.swift|*/App.swift) [ "${1:-}" != --tests ] || continue ;;
    esac
    echo "$f"
done
