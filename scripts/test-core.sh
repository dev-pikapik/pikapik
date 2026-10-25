#!/bin/bash
# Usage: swiftc -parse-as-library $(./scripts/test-core.sh [swiftc flags] files…) scripts/test-X.swift -o build/test-X
# Builds the app files that many test lines in CONTRIBUTING.md share once, as the module PikaCore in build/test-core, and prints the flags that let a test
# use them as if it were built together with them. The module is built again only when one of its files, a flag, this script or swiftc changes.
set -uo pipefail
cd "$(dirname "$0")/.."
hash=$({ cat scripts/test-core.sh; swiftc --version; swiftc -print-target-info; printf '%s\n' "$@"; for arg in "$@"; do [ ! -f "$arg" ] || cat "$arg"; done; } 2>&1 | shasum | cut -c1-12)
dir=build/test-core/$hash
if [ ! -f "$dir/built" ]; then
    rm -rf "$dir" && mkdir -p "$dir"
    swiftc -swift-version 5 -parse-as-library -enable-testing -module-name PikaCore -emit-module -emit-module-path "$dir/PikaCore.swiftmodule" -emit-library -static -o "$dir/libPikaCore.a" "$@" >&2 && touch "$dir/built"
fi
touch "$dir"
ls -t build/test-core | tail -n +5 | while IFS= read -r old; do rm -rf "build/test-core/$old"; done
echo "-I $dir -Xfrontend -testable-import-module -Xfrontend PikaCore -Xlinker -force_load -Xlinker $dir/libPikaCore.a"
[ -f "$dir/built" ]
