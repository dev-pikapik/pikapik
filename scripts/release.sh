#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "Укажи версию: ./scripts/release.sh 1.0.1" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Сначала закоммить изменения." >&2; exit 1; }
command -v gh >/dev/null || { echo "Нужен gh: brew install gh" >&2; exit 1; }

PLIST="Sources/pikapik/Info.plist"
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"

./scripts/package.sh

SHA=$(shasum -a 256 build/pikapik.zip | cut -d' ' -f1)
sed -i '' \
    -e "s/^  version \".*\"/  version \"$VERSION\"/" \
    -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
    Casks/pikapik.rb

git add "$PLIST" Casks/pikapik.rb
git commit -q -m "Версия $VERSION"
git tag "v$VERSION"
git push -q origin HEAD "v$VERSION"

gh release create "v$VERSION" build/pikapik.zip build/pikapik.dmg \
    --title "pikapik $VERSION" \
    --generate-notes

echo "Вышла версия $VERSION. Приложения подтянут её сами, brew — через brew upgrade."
