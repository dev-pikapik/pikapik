#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/render-media.app
OUT=docs/media
DOMAIN=com.pikapik.app.direct.media
trap 'defaults delete "$DOMAIN" 2>/dev/null || true' EXIT
defaults delete "$DOMAIN" 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUT"
if [ $# -eq 0 ]; then find "$OUT" -maxdepth 1 -type f -delete; fi

SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find Sources -name '*.swift' ! -name main.swift -print0)
swiftc -O -parse-as-library -module-name Pikapik -target "$(uname -m)-apple-macos14.0" \
    "${SOURCES[@]}" Extensions/Convert/ConvertFormats.swift Extensions/Preview/ZipNames.swift scripts/render-media.swift \
    -o "$APP/Contents/MacOS/render-media"

PLIST="$APP/Contents/Info.plist"
cp Sources/pikapik/Info.plist "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DOMAIN" -c "Set :CFBundleExecutable render-media" -c "Delete :CFBundleURLTypes" "$PLIST"
rm -rf build/lproj
python3 - <<'XCPY'
import json, os, plistlib

def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')

with open('Resources/Localizable.xcstrings', encoding='utf-8') as f:
    loc_data = json.load(f)['strings']
with open('Resources/ServicesMenu.xcstrings', encoding='utf-8') as f:
    srv_data = json.load(f)['strings']

langs = sorted({l for item in loc_data.values() for l in item.get('localizations', {})})
for lang in langs:
    out_dir = f'build/lproj/{lang}.lproj'
    os.makedirs(out_dir, exist_ok=True)
    lines = []
    sdict = {}
    for key, item in loc_data.items():
        loc = item.get('localizations', {}).get(lang, {})
        if 'stringUnit' in loc:
            val = loc['stringUnit']['value']
            lines.append(f'"{esc(key)}" = "{esc(val)}";\n')
        elif 'variations' in loc and 'plural' in loc['variations']:
            plural = loc['variations']['plural']
            fallback = (plural.get('many') or plural.get('other'))['stringUnit']['value']
            lines.append(f'"{esc(key)}" = "{esc(fallback)}";\n')
            var_name = 'lines' if 'lines' in key else 'count'
            rule_dict = {
                'NSStringFormatSpecTypeKey': 'NSStringPluralRuleType',
                'NSStringFormatValueTypeKey': 'lld',
            }
            for rule, unit in plural.items():
                rule_dict[rule] = unit['stringUnit']['value']
            sdict[key] = {'NSStringLocalizedFormatKey': f'%#@{var_name}@', var_name: rule_dict}
    with open(f'{out_dir}/Localizable.strings', 'w', encoding='utf-8') as f:
        f.writelines(lines)
    with open(f'{out_dir}/Localizable.stringsdict', 'wb') as f:
        plistlib.dump(sdict, f, sort_keys=False)
    srv_lines = []
    for key, item in srv_data.items():
        loc = item.get('localizations', {}).get(lang, {})
        if 'stringUnit' in loc:
            srv_lines.append(f'"{esc(key)}" = "{esc(loc["stringUnit"]["value"])}";\n')
    with open(f'{out_dir}/ServicesMenu.strings', 'w', encoding='utf-8') as f:
        f.writelines(srv_lines)
XCPY
cp -R build/lproj/*.lproj Resources/github.svg Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

"$APP/Contents/MacOS/render-media" "$OUT" cards "$@" -AppleLanguages "(en)"
if [ $# -eq 0 ] || [[ " $* " == *" settings "* ]]; then
    defaults write "$DOMAIN" input-switch -bool true
    defaults write "$DOMAIN" key-repeat -bool true
    for LANGUAGE in $(basename -s .lproj build/lproj/*.lproj); do "$APP/Contents/MacOS/render-media" "$OUT" "$LANGUAGE" -AppleLanguages "($LANGUAGE)"; done
fi
if [ $# -eq 0 ]; then
    sips -s format png -Z 256 Resources/AppIcon.icns --out "$OUT/icon.png" >/dev/null
fi
rm -rf build/lproj
ls -l "$OUT"
