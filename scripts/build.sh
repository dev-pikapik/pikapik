#!/bin/bash
# Usage: scripts/build.sh
# Builds build/pikapik.app for Apple silicon and Intel at the same time and keeps the debug symbols of each of its programs in build/dSYM.
# APPSTORE=1 builds the App Store version.
# FAST=1 builds only the app itself, for Apple silicon and without optimization, to try a change quickly: without the fan helper, the player, the extensions and the strings check.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/pikapik.app"
EXTENSIONS="NewFile Compress Convert Archive Preview"
MEDIA_EXTENSIONS="MediaReader MediaDecoder"
PLAYER="$APP/Contents/Helpers/pikapik Player.app"
PLAYER_SOURCES=(Helper/Player/*.swift Extensions/MediaReader/{Demuxer,Formats,Codecs,AudioDecoder}.swift Sources/pikapik/Tools/Player/{PlayerLogic,ImageLogic,PlayerMarks,PlayerOutput,SubtitleParser}.swift Sources/pikapik/Core/Symbol.swift Sources/pikapik/UI/SymbolImage.swift)
MIN_OS="14.0"
ARCHS=(arm64 x86_64)
HELPERS=$([ -n "${APPSTORE:-}" ] || echo 1)
[ -z "${FAST:-}" ] || { ARCHS=(arm64); HELPERS=; EXTENSIONS=; MEDIA_EXTENSIONS=; }
DEV_IDENTITY="pikapik Dev"
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY=-
    security unlock-keychain -p "" "$HOME/Library/Keychains/pikapik-dev.keychain-db" 2>/dev/null || true
    security find-certificate -c "$DEV_IDENTITY" >/dev/null 2>&1 && SIGN_IDENTITY="$DEV_IDENTITY"
fi
DEV=$([ "$SIGN_IDENTITY" = - ] || [ "$SIGN_IDENTITY" = "$DEV_IDENTITY" ] && echo 1 || true)

if [ -n "${APPSTORE:-}" ]; then
    MEDIA_EXTENSIONS=""
elif [ -z "$DEV" ]; then
    for EXT in $MEDIA_EXTENSIONS; do
        NAME="$(echo "$EXT" | tr a-z A-Z)_PROFILE"
        [ -f "${!NAME:-}" ] || { echo "$NAME is not set: leaving the media extensions out." >&2; MEDIA_EXTENSIONS=""; break; }
    done
fi

APPSTORE_ID=com.pikapik.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" build/strings build/dSYM
[ -z "$HELPERS" ] || mkdir -p "$APP/Contents/Library/LaunchServices"
[ -n "${APPSTORE:-}" ] || ./scripts/fetch-7zip.sh
[ -z "$HELPERS" ] || ./scripts/fetch-ffmpeg.sh
[ -z "$HELPERS" ] || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Sources/pikapik/Info.plist)" build/fan-helper.plist >/dev/null
for EXT in $EXTENSIONS; do mkdir -p "$APP/Contents/PlugIns/$EXT.appex/Contents/MacOS"; done
for EXT in $MEDIA_EXTENSIONS; do mkdir -p "$APP/Contents/Extensions/$EXT.appex/Contents/MacOS"; done
[ -z "$HELPERS" ] || mkdir -p "$PLAYER/Contents/MacOS" "$PLAYER/Contents/Resources"

SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find Sources -name '*.swift' -print0)
SOURCES+=(Extensions/Convert/ConvertFormats.swift)
SOURCES+=(Extensions/Preview/ZipNames.swift)

FLAGS=()
[ -z "${DEBUG:-}" ] || FLAGS+=(-D DEBUG)
if [ -n "${APPSTORE:-}" ]; then
    FLAGS+=(-D APPSTORE)
    SOURCES=()
    while IFS= read -r f; do SOURCES+=("$f"); done < <(./scripts/appstore-sources.sh)
    echo "App Store build"
elif [ -d Private/Sources ] && [ -n "$(find Private/Sources -name '*.swift' -print -quit)" ]; then
    while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find Private/Sources -name '*.swift' -print0)
    FLAGS+=(-D PIKA_PRIVATE)
    echo "Including Private/Sources"
fi

SWIFTC=(swiftc -O -whole-module-optimization -num-threads "$(sysctl -n hw.ncpu)")
if [ -n "${FAST:-}" ]; then
    mkdir -p build/arm64
    { echo '{'; for F in "${SOURCES[@]}"; do printf '"%s": {"object": "build/arm64/%s.o"},\n' "$F" "${F##*/}"; done; echo '"": {}}'; } > build/arm64/files.json
    SWIFTC=(swiftc -Onone -enable-batch-mode -j "$(sysctl -n hw.ncpu)" -output-file-map build/arm64/files.json)
fi
SWIFTC+=(-emit-executable -g -swift-version 5 ${FLAGS[@]+"${FLAGS[@]}"})
module() { echo "-module-name $1 -emit-module-path build/$ARCH/$1.swiftmodule"; }
emit() { [ "$ARCH" != arm64 ] || [ -n "${FAST:-}" ] || echo "-Xfrontend -emit-localized-strings -Xfrontend -emit-localized-strings-path -Xfrontend build/strings/$1"; }
descendants() { local P; for P in $(pgrep -P "$1"); do echo "$P"; descendants "$P"; done; }
trap 'kill $(descendants $$) 2>/dev/null || true' EXIT

compile() {
    "${SWIFTC[@]}" \
        $(module Pikapik) \
        -target "$ARCH-apple-macos$MIN_OS" \
        $(emit Pikapik) \
        "${SOURCES[@]}" \
        -o "build/$ARCH/pikapik"
    [ -z "$HELPERS" ] || "${SWIFTC[@]}" \
        $(module FanHelper) \
        -target "$ARCH-apple-macos$MIN_OS" \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker build/fan-helper.plist \
        Helper/FanHelper/main.swift Sources/pikapik/Tools/Fans/SMC.swift Sources/pikapik/Tools/Fans/FanHelperProtocol.swift \
        -o "build/$ARCH/fan-helper"
    [ -z "$HELPERS" ] || "${SWIFTC[@]}" \
        $(module Player) \
        -target "$ARCH-apple-macos$MIN_OS" \
        $(emit Player) \
        -import-objc-header Helper/Player/Player.h -I Vendor/ffmpeg/include \
        Vendor/ffmpeg/lib/*.dylib Vendor/ffmpeg/lib/libass.a -lc++ -liconv -framework CoreText -Xlinker -dead_strip_dylibs \
        -Xlinker -rpath -Xlinker @executable_path/../../../../Frameworks \
        "${PLAYER_SOURCES[@]}" \
        -o "build/$ARCH/pikapik Player"
    for EXT in $EXTENSIONS; do
        SHARED=(Extensions/Shared/*.swift Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/MainCopyChoice.swift)
        [ "$EXT" != Archive ] || SHARED+=(Sources/pikapik/Tools/Archive/Archive.swift)
        LINK=()
        [ "$EXT" != Preview ] || { SHARED=(); LINK=(-import-objc-header Extensions/Preview/libarchive.h -larchive); }
        "${SWIFTC[@]}" \
            $(module "$EXT") \
            -target "$ARCH-apple-macos$MIN_OS" \
            -application-extension \
            $(emit "$EXT") \
            -Xlinker -e -Xlinker _NSExtensionMain \
            ${LINK[@]+"${LINK[@]}"} \
            Extensions/"$EXT"/*.swift ${SHARED[@]+"${SHARED[@]}"} \
            -o "build/$ARCH/$EXT"
    done
    for EXT in $MEDIA_EXTENSIONS; do
        MEDIA_SOURCES=(Extensions/MediaReader/*.swift)
        HEADER=MediaReader
        [ "$EXT" = MediaReader ] || { MEDIA_SOURCES=(Extensions/MediaDecoder/*.swift Extensions/MediaReader/Codecs.swift); HEADER=FFmpeg; }
        "${SWIFTC[@]}" \
            $(module "$EXT") \
            -target "$ARCH-apple-macos15.0" \
            -application-extension \
            -parse-as-library \
            -import-objc-header "Extensions/MediaReader/$HEADER.h" -I Vendor/ffmpeg/include \
            -Xlinker -e -Xlinker _EXExtensionMain -framework ExtensionFoundation \
            Vendor/ffmpeg/lib/*.dylib -Xlinker -dead_strip_dylibs \
            -Xlinker -rpath -Xlinker @executable_path/../../../../Frameworks \
            "${MEDIA_SOURCES[@]}" \
            -o "build/$ARCH/$EXT"
    done
}

PIDS=()
for ARCH in "${ARCHS[@]}"; do
    echo "Building $ARCH"
    mkdir -p "build/$ARCH"
    compile > "build/$ARCH/build.log" 2>&1 &
    PIDS+=($!)
done
for I in "${!ARCHS[@]}"; do
    wait "${PIDS[$I]}" || { cat "build/${ARCHS[$I]}/build.log" >&2; echo "Building ${ARCHS[$I]} failed" >&2; exit 1; }
    cat "build/${ARCHS[$I]}/build.log"
done

[ -n "${FAST:-}" ] || ./scripts/check-strings.sh build/strings
rm -rf build/strings

universal() {
    local IN=() DWARF=() ARCH
    for ARCH in "${ARCHS[@]}"; do
        IN+=("build/$ARCH/$1")
        DWARF+=("build/$ARCH/$1.dSYM/Contents/Resources/DWARF/$1")
        ditto "build/$ARCH/$1.dSYM" "build/dSYM/$1.dSYM"
    done
    lipo -create "${IN[@]}" -output "$2"
    lipo -create "${DWARF[@]}" -output "build/dSYM/$1.dSYM/Contents/Resources/DWARF/$1"
    strip -x "$2"
}

universal pikapik "$APP/Contents/MacOS/pikapik"
./scripts/make-lproj.sh
[ -n "${APPSTORE:-}" ] || cp Vendor/7zip/7zz "$APP/Contents/MacOS/7zz"
if [ -n "$HELPERS" ]; then
    universal fan-helper "$APP/Contents/Library/LaunchServices/fan-helper"
    universal "pikapik Player" "$PLAYER/Contents/MacOS/pikapik Player"
    cp Helper/Player/Info.plist "$PLAYER/Contents/Info.plist"
    cp -R build/lproj/*.lproj "$PLAYER/Contents/Resources/"
    LOCAL_TEXT='pikapik Player shares the video you are playing with the AirPlay device you choose, only inside your local network.'
    for LPROJ in build/lproj/*.lproj; do
        grep -F "\"$LOCAL_TEXT\" = " "$LPROJ/Localizable.strings" | sed 's/^"[^"]*"/"NSLocalNetworkUsageDescription"/' > "$PLAYER/Contents/Resources/$(basename "$LPROJ")/InfoPlist.strings"
    done
fi
cp Sources/pikapik/Info.plist "$APP/Contents/Info.plist"
for EXT in $EXTENSIONS; do
    APPEX="$APP/Contents/PlugIns/$EXT.appex"
    universal "$EXT" "$APPEX/Contents/MacOS/$EXT"
    cp "Extensions/$EXT/Info.plist" "$APPEX/Contents/Info.plist"
    [ -z "${APPSTORE:-}" ] || { mkdir -p "$APPEX/Contents/Resources" && cp Resources/PrivacyInfo.xcprivacy "$APPEX/Contents/Resources/"; }
    for KEY in CFBundleShortVersionString CFBundleVersion; do
        /usr/libexec/PlistBuddy -c "Set :$KEY $(/usr/libexec/PlistBuddy -c "Print :$KEY" "$APP/Contents/Info.plist")" "$APPEX/Contents/Info.plist"
    done
    for LPROJ in build/lproj/*.lproj; do
        OUT="$APPEX/Contents/Resources/$(basename "$LPROJ")"
        mkdir -p "$OUT"
        case $EXT in
            NewFile) TEXTS='New File' NAME='New File in Finder' ;;
            Compress) TEXTS='Make a Smaller Copy' NAME='Smaller Copy in Finder' ;;
            Convert) TEXTS='Convert To|M4A \(Audio Only\)' NAME='Convert in Finder' ;;
            Archive) TEXTS='Extract|Create Archive…' NAME='Archives in Finder' ;;
            Preview) TEXTS='%lld items|Expands to %@|It could fill up your disk.|Protected with a password|Part of a multi-part archive|Damaged. Showing what could be read.|Only the first items are shown.|Contains a program. Open it only if you trust where it came from.' NAME='Archives in Finder' ;;
        esac
        grep -E "^\"($TEXTS)\" = " "$LPROJ/Localizable.strings" > "$OUT/Localizable.strings"
        grep "^\"$NAME\" = " "$LPROJ/Localizable.strings" | sed 's/^"[^"]*"/"CFBundleDisplayName"/' > "$OUT/InfoPlist.strings"
        [ "$EXT" != Preview ] || cp "$LPROJ/Localizable.stringsdict" "$OUT/"
    done
done
for EXT in $MEDIA_EXTENSIONS; do
    APPEX="$APP/Contents/Extensions/$EXT.appex"
    universal "$EXT" "$APPEX/Contents/MacOS/$EXT"
    cp "Extensions/$EXT/Info.plist" "$APPEX/Contents/Info.plist"
    for KEY in CFBundleShortVersionString CFBundleVersion; do
        /usr/libexec/PlistBuddy -c "Set :$KEY $(/usr/libexec/PlistBuddy -c "Print :$KEY" "$APP/Contents/Info.plist")" "$APPEX/Contents/Info.plist"
    done
    NAME="$(echo "$EXT" | tr a-z A-Z)_PROFILE"
    [ ! -f "${!NAME:-}" ] || cp "${!NAME}" "$APPEX/Contents/embedded.provisionprofile"
done
rm -rf build/arm64 build/x86_64

RES="$APP/Contents/Resources"
mkdir -p "$RES"
cp -R build/lproj/*.lproj "$RES/"
CAPTURE_TEXT='pikapik passes each app’s sound through itself to change its volume. Nothing is recorded or saved.'
for LPROJ in build/lproj/*.lproj; do
    grep -F "\"$CAPTURE_TEXT\" = " "$LPROJ/Localizable.strings" | sed 's/^"[^"]*"/"NSAudioCaptureUsageDescription"/' > "$RES/$(basename "$LPROJ")/InfoPlist.strings"
    grep '^"Archive" = ' "$LPROJ/Localizable.strings" >> "$RES/$(basename "$LPROJ")/InfoPlist.strings"
done
if [ -z "${APPSTORE:-}" ]; then
    FINDER_TEXT='pikapik asks Finder to move apps to the Trash when macOS doesn’t let it do that itself.'
    /usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string $FINDER_TEXT" "$APP/Contents/Info.plist"
    for LPROJ in build/lproj/*.lproj; do
        grep -F "\"$FINDER_TEXT\" = " "$LPROJ/Localizable.strings" | sed 's/^"[^"]*"/"NSAppleEventsUsageDescription"/' >> "$RES/$(basename "$LPROJ")/InfoPlist.strings"
    done
    cp Vendor/7zip/License.txt "$RES/7-Zip License.txt"
fi
if [ -n "$HELPERS" ]; then
    mkdir -p "$APP/Contents/Frameworks"
    cp Vendor/ffmpeg/lib/*.dylib "$APP/Contents/Frameworks/"
    { printf 'pikapik Player plays DTS sound and shows the picture subtitles PGS, VobSub and DVB with the FFmpeg decoders dca, pgssub, dvdsub and dvbsub; like all of FFmpeg here, they are under the LGPL below.\n\n'; cat Vendor/ffmpeg/License.txt; } > "$RES/Player Licenses.txt"
fi
rm -rf build/lproj
cp Resources/github.svg Resources/AppIcon.icon/Assets/pikapik.svg "$RES/"
[ -n "${APPSTORE:-}" ] && cp Resources/PrivacyInfo.xcprivacy "$RES/"
if xcrun --find actool >/dev/null 2>&1 && xcrun actool "$PWD/Resources/AppIcon.icon" \
        --compile "$PWD/$RES" \
        --app-icon AppIcon \
        --platform macosx \
        --target-device mac \
        --minimum-deployment-target "$MIN_OS" \
        --output-partial-info-plist "$PWD/build/icon-info.plist" >build/actool.log 2>&1 \
        && [ -f "$RES/Assets.car" ]; then
    [ -f "$RES/AppIcon.icns" ] || cp Resources/AppIcon.icns "$RES/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist"
    echo "Icon: Assets.car from AppIcon.icon"
else
    [ -s build/actool.log ] && tail -5 build/actool.log
    rm -f "$RES/Assets.car"
    cp Resources/AppIcon.icns "$RES/AppIcon.icns"
    echo "Icon: prebuilt AppIcon.icns"
fi
rm -f build/icon-info.plist build/actool.log
if [ -n "$HELPERS" ]; then
    cp "$RES/AppIcon.icns" "$PLAYER/Contents/Resources/"
    for KEY in CFBundleShortVersionString CFBundleVersion; do
        /usr/libexec/PlistBuddy -c "Set :$KEY $(/usr/libexec/PlistBuddy -c "Print :$KEY" "$APP/Contents/Info.plist")" "$PLAYER/Contents/Info.plist"
    done
fi

sign() {
    if [ "$SIGN_IDENTITY" = "-" ]; then
        codesign --force --sign - "$@"
    elif [[ "$SIGN_IDENTITY" == "Developer ID"* ]]; then
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$@"
    else
        codesign --force --options runtime --sign "$SIGN_IDENTITY" "$@"
    fi
}

group_entitlements() {
    local OUT="build/$2.entitlements"
    cp "$1" "$OUT"
    local BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$3/Contents/Info.plist")"
    [ "$2" = Preview ] || /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups array" -c "Add :com.apple.security.application-groups:0 string $TEAM_ID.com.pikapik.app" "$OUT"
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$OUT"
    echo "$OUT"
}

if [ -n "${APPSTORE:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $APPSTORE_ID" -c "Add :ITSAppUsesNonExemptEncryption bool false" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLName $APPSTORE_ID" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 pikapik-store" -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:1 pika-tools-store" "$APP/Contents/Info.plist"
    for EXT in $EXTENSIONS; do
        PLIST="$APP/Contents/PlugIns/$EXT.appex/Contents/Info.plist"
        ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST")"
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${ID/com.pikapik.app.direct./$APPSTORE_ID.}" "$PLIST"
        [ "$EXT" = Preview ] || /usr/libexec/PlistBuddy -c "Set :PikapikURLScheme pikapik-store" "$PLIST"
    done
elif [ -n "$DEV" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.pikapik.app.dev" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLName com.pikapik.app.dev" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 pikapik-dev" -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:1 pika-tools-dev" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :NSServices:0:NSPortName pikapik-dev" -c "Set :NSServices:0:NSMenuItem:default Fix Wrong Keyboard Layout (Dev)" "$APP/Contents/Info.plist"
    for EXT in $EXTENSIONS; do
        PLIST="$APP/Contents/PlugIns/$EXT.appex/Contents/Info.plist"
        ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST")"
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${ID/com.pikapik.app.direct./com.pikapik.app.dev.}" "$PLIST"
        [ "$EXT" = Preview ] || /usr/libexec/PlistBuddy -c "Set :PikapikURLScheme pikapik-dev" "$PLIST"
    done
    for EXT in $MEDIA_EXTENSIONS; do
        PLIST="$APP/Contents/Extensions/$EXT.appex/Contents/Info.plist"
        ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST")"
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${ID/com.pikapik.app.direct./com.pikapik.app.dev.}" -c "Set :EXAppExtensionAttributes:ClassImplementationID ${ID/com.pikapik.app.direct./com.pikapik.app.dev.}" "$PLIST"
    done
    [ -z "$HELPERS" ] || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.pikapik.app.dev.player" "$PLAYER/Contents/Info.plist"
fi
APP_ENTITLEMENTS=()
for EXT in $EXTENSIONS; do
    ENTITLEMENTS="Extensions/$EXT/$EXT.entitlements"
    [ -n "${APPSTORE:-}" ] && [ -n "${TEAM_ID:-}" ] && ENTITLEMENTS="$(group_entitlements "$ENTITLEMENTS" "$EXT" "$APP/Contents/PlugIns/$EXT.appex")"
    sign --entitlements "$ENTITLEMENTS" "$APP/Contents/PlugIns/$EXT.appex"
done
if [ -n "$HELPERS" ]; then
    sign "$APP"/Contents/Frameworks/*.dylib
    for EXT in $MEDIA_EXTENSIONS; do sign --entitlements "Extensions/$EXT/$EXT.entitlements" "$APP/Contents/Extensions/$EXT.appex"; done
    cp Helper/Player/Player.entitlements build/player.entitlements
    [[ "$SIGN_IDENTITY" == "Developer ID"* ]] || /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" build/player.entitlements
    sign --entitlements build/player.entitlements "$PLAYER"
fi
if [ -n "${APPSTORE:-}" ]; then
    ENTITLEMENTS=Resources/AppStore.entitlements
    [ -n "${TEAM_ID:-}" ] && ENTITLEMENTS="$(group_entitlements "$ENTITLEMENTS" app "$APP")"
    APP_ENTITLEMENTS=(--entitlements "$ENTITLEMENTS")
else
    APP_ENTITLEMENTS=(--entitlements Resources/Direct.entitlements)
    BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")"
    [ -z "$HELPERS" ] || sign --identifier "$BUNDLE_ID.fans" "$APP/Contents/Library/LaunchServices/fan-helper"
    sign --identifier "$BUNDLE_ID.7zz" "$APP/Contents/MacOS/7zz"
fi
sign ${APP_ENTITLEMENTS[@]+"${APP_ENTITLEMENTS[@]}"} "$APP"

echo "Done: $APP ($(lipo -archs "$APP/Contents/MacOS/pikapik"))"
