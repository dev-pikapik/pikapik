#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "Usage: ./scripts/release.sh 1.3.0" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first." >&2; exit 1; }
git fetch -q origin main
SHA=$(git rev-parse HEAD)
[ "$(git branch --show-current)" = main ] && [ "$SHA" = "$(git rev-parse origin/main)" ] || { echo "Release from main exactly as it is on GitHub: switch to main and push or pull first." >&2; exit 1; }
RUNS=$(mktemp)
RESULT=$(curl -fsS "https://api.github.com/repos/dev-pikapik/pikapik/actions/workflows/build.yml/runs?head_sha=$SHA&event=push&per_page=1" -o "$RUNS" && /usr/bin/plutil -extract workflow_runs.0.conclusion raw -o - "$RUNS" 2>/dev/null || true)
rm -f "$RUNS"
[ "$RESULT" = success ] || { echo "Build hasn’t passed for $SHA on main (${RESULT:-no finished run}). Release once it’s green: https://github.com/dev-pikapik/pikapik/actions/workflows/build.yml" >&2; exit 1; }
MISSING=$(grep -LF "id=\"v$VERSION\"" docs/whats-new/README*.md || true)
[ -z "$MISSING" ] || { echo "Write the What’s new post for $VERSION first. It’s missing in:" >&2; echo "$MISSING" >&2; exit 1; }
grep -qxF "## [$VERSION] - Unreleased" CHANGELOG.md || { echo "Add “## [$VERSION] - Unreleased” to CHANGELOG.md first." >&2; exit 1; }
FORM=".github/ISSUE_TEMPLATE/bug_report.yml"
grep -qxF "        - Latest version" "$FORM" || { echo "“- Latest version” is missing in $FORM." >&2; exit 1; }
./scripts/feature-form.sh --check

PLIST="Sources/pikapik/Info.plist"
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST") + 1 ))
sed -i '' -e "/<key>CFBundleShortVersionString<\/key>/{n;s|<string>.*</string>|<string>$VERSION</string>|;}" -e "/<key>CFBundleVersion<\/key>/{n;s|<string>.*</string>|<string>$BUILD</string>|;}" "$PLIST"

sed -i '' "s/^## \[${VERSION//./\\.}\] - Unreleased$/## [$VERSION] - $(date +%F)/" CHANGELOG.md
REF="[$VERSION]: https://github.com/dev-pikapik/pikapik/releases/tag/v$VERSION"
grep -qxF "$REF" CHANGELOG.md || { awk -v ref="$REF" '!done && /^\[[0-9]/ { print ref; done = 1 } 1' CHANGELOG.md > CHANGELOG.md.new && mv CHANGELOG.md.new CHANGELOG.md; }

grep -qxF "        - \"$VERSION\"" "$FORM" || { awk -v v="        - \"$VERSION\"" '{ print } $0 == "        - Latest version" { print v }' "$FORM" > "$FORM.new" && mv "$FORM.new" "$FORM"; }

git add "$PLIST" CHANGELOG.md "$FORM"
git commit -q -m "Version $VERSION"
git tag "v$VERSION"
git push -q origin HEAD "v$VERSION"

echo "Pushed v$VERSION. GitHub Actions will build, publish and update the Homebrew tap:"
echo "https://github.com/dev-pikapik/pikapik/actions"
