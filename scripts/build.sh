#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/pikapik.app"
MIN_OS="14.0"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

rm -rf build
mkdir -p "$APP/Contents/MacOS"

SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find Sources -name '*.swift' -print0)

FLAGS=()
if [ -d Private/Sources ] && [ -n "$(find Private/Sources -name '*.swift' -print -quit)" ]; then
    while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find Private/Sources -name '*.swift' -print0)
    FLAGS+=(-D PIKA_PRIVATE)
    echo "Подключаю Private/Sources"
fi

for ARCH in arm64 x86_64; do
    echo "Собираю $ARCH"
    swiftc -O -whole-module-optimization \
        -module-name Pikapik \
        -target "$ARCH-apple-macos$MIN_OS" \
        ${FLAGS[@]+"${FLAGS[@]}"} \
        "${SOURCES[@]}" \
        -o "build/pikapik-$ARCH"
done

lipo -create build/pikapik-arm64 build/pikapik-x86_64 -output "$APP/Contents/MacOS/pikapik"
rm build/pikapik-arm64 build/pikapik-x86_64
cp Sources/pikapik/Info.plist "$APP/Contents/Info.plist"

if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

echo "Готово: $APP ($(lipo -archs "$APP/Contents/MacOS/pikapik"))"
