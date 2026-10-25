#!/bin/bash
# Usage: scripts/check-strings.sh [dir with .stringsdata from swiftc -emit-localized-strings]
# Without an argument it first extracts the strings of the direct and the App Store version into a temporary dir.
# It also checks every Resources/*.xcstrings catalog: all 23 languages for every key, complete plural forms, nothing left to review or empty.
set -euo pipefail
cd "$(dirname "$0")/.."

DIR="${1:-}"
if [ -z "$DIR" ]; then
    DIR="$(mktemp -d)"
    export TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$DIR" "$TMPDIR"' EXIT
    SOURCES=()
    while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find Sources -name '*.swift' -print0)
    SOURCES+=(Extensions/Convert/ConvertFormats.swift Extensions/Preview/ZipNames.swift)
    FLAGS=()
    if [ -d Private/Sources ] && [ -n "$(find Private/Sources -name '*.swift' -print -quit)" ]; then
        while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find Private/Sources -name '*.swift' -print0)
        FLAGS+=(-D PIKA_PRIVATE)
    fi
    extract() {
        swiftc -wmo -emit-module -swift-version 5 -module-name "$1" -target arm64-apple-macos14.0 \
            ${FLAGS[@]+"${FLAGS[@]}"} \
            -Xfrontend -emit-localized-strings -Xfrontend -emit-localized-strings-path -Xfrontend "$DIR/$VARIANT/$1" \
            "${@:2}" -emit-module-path "$DIR/$VARIANT/$1/$1.swiftmodule"
    }
    for VARIANT in direct appstore; do
        echo "Extracting the strings of the $VARIANT version"
        if [ "$VARIANT" = appstore ]; then
            FLAGS=(-D APPSTORE)
            SOURCES=()
            while IFS= read -r f; do SOURCES+=("$f"); done < <(./scripts/appstore-sources.sh)
        fi
        extract Pikapik "${SOURCES[@]}"
        for EXT in NewFile Compress Convert Archive Preview; do
            SHARED=(Extensions/Shared/*.swift Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/MainCopyChoice.swift)
            [ "$EXT" != Archive ] || SHARED+=(Sources/pikapik/Tools/Archive/Archive.swift)
            [ "$EXT" != Preview ] || SHARED=(-import-objc-header Extensions/Preview/libarchive.h)
            extract "$EXT" -application-extension Extensions/"$EXT"/*.swift "${SHARED[@]}"
        done
        [ "$VARIANT" = appstore ] || [ ! -d Vendor/ffmpeg/include ] || extract Player \
            -import-objc-header Helper/Player/Player.h -I Vendor/ffmpeg/include \
            Helper/Player/*.swift Extensions/MediaReader/{Demuxer,Formats,Codecs,AudioDecoder}.swift Sources/pikapik/Tools/Player/{PlayerLogic,ImageLogic,PlayerMarks,PlayerOutput,SubtitleParser}.swift Sources/pikapik/Core/Symbol.swift Sources/pikapik/UI/SymbolImage.swift
    done
fi

PYTHONPATH=scripts python3 -B - "$DIR" <<'PY'
import glob, json, os, re, subprocess, sys
from collections import Counter
import xcstrings

problems = []

def fail(text):
    problems.append(text)

def escape(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')

def unescape(s):
    return re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), s)

SPEC = re.compile(r'%(?:\d+\$)?[-+ 0#]*(?:\d+|\*)?(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA]')

def specs(s):
    return Counter(re.sub(r'(?<=%)\d+\$', '', m) for m in SPEC.findall(s.replace('%%', '')))

WHOLE_NUMBER_FORMS = {
    'ar': 'zero one two few many', 'cs': 'one few', 'de': 'one', 'en': 'one', 'es': 'one many', 'fr': 'one many',
    'hi': 'one', 'id': '', 'it': 'one many', 'ja': '', 'ko': '', 'nl': 'one', 'pl': 'one few many', 'pt-BR': 'one many',
    'ro': 'one few', 'ru': 'one few many', 'sv': 'one', 'th': '', 'tr': 'one', 'uk': 'one few many', 'vi': '',
    'zh-Hans': '', 'zh-Hant': '',
}
FRACTION_FORMS = {'cs': 'many'}
ONE_IS_SEVERAL_NUMBERS = {'fr', 'hi', 'pt-BR', 'ru', 'uk'}
XCSTRINGSTOOL = (subprocess.run(['xcrun', '--find', 'xcstringstool'], capture_output=True, text=True).stdout.strip()
                 or '/Applications/Xcode.app/Contents/Developer/usr/bin/xcstringstool')
if not os.path.exists(XCSTRINGSTOOL) and os.environ.get('CI'):
    fail('xcstringstool is missing, so the catalogs were not compiled')

def check_state(path, where, key, unit):
    if unit.get('state') != 'translated':
        fail(f'{path} ({where}): "{key[:60]}" has state "{unit.get("state", "")}", it must be "translated"')

def leaves_out_count(key, value):
    return (specs(key) - specs(value) == Counter({'%lld': 1}) and not specs(value) - specs(key)
            and all(re.match(r'%(?!1\$)\d+\$', s) for s in SPEC.findall(value.replace('%%', ''))))

def load_catalog(path):
    if not os.path.exists(path):
        fail(f'{path}: missing')
        return {}, []
    try:
        strings, all_langs = xcstrings.load(path, lambda key, n: fail(f'{path}: "{key[:60]}" is written {n} times'))
    except Exception as e:
        fail(f'{path}: {e}')
        return {}, []
    if os.path.exists(XCSTRINGSTOOL):
        r = subprocess.run([XCSTRINGSTOOL, 'compile', path, '--output-directory', sys.argv[1] + '/xc', '--dry-run'], capture_output=True, text=True)
        if r.returncode:
            fail(f'{path}: {r.stderr.strip().replace(os.path.abspath(path) + ": ", "")}')
    tables = {lang: {} for lang in all_langs}
    for key, item in strings.items():
        locs = item.get('localizations', {})
        missing = [lang for lang in all_langs if lang not in locs]
        if missing:
            fail(f'{path}: "{key[:60]}" is missing in {", ".join(missing)}')
        first = SPEC.search(key.replace('%%', ''))
        if any('plural' in loc.get('variations', {}) for loc in locs.values()) and (not first or re.sub(r'(?<=%)\d+\$', '', first.group()) != '%lld'):
            fail(f'{path}: "{key[:60]}" changes with a number, so its first placeholder must be that number, %lld')
        for lang, loc in locs.items():
            unit, plural = xcstrings.forms(loc)
            if plural is not None:
                if lang not in WHOLE_NUMBER_FORMS:
                    fail(f'{path} ({lang}): add the plural forms of {lang} to WHOLE_NUMBER_FORMS in scripts/check-strings.sh')
                needed_forms = WHOLE_NUMBER_FORMS.get(lang, '').split() + ['other']
                for rule in needed_forms:
                    if rule not in plural:
                        fail(f'{path} ({lang}): "{key[:60]}" is missing plural "{rule}"')
                for rule, unit in plural.items():
                    value = unit.get('value', '')
                    one_number = rule in ('zero', 'two') or rule == 'one' and lang not in ONE_IS_SEVERAL_NUMBERS
                    if rule not in needed_forms + FRACTION_FORMS.get(lang, '').split() + ['zero']:
                        fail(f'{path} ({lang}): "{key[:60]}" has plural "{rule}", which {lang} never uses for whole numbers')
                    check_state(path, f'{lang}.{rule}', key, unit)
                    if not value.strip():
                        fail(f'{path} ({lang}.{rule}): "{key[:60]}" is empty')
                    elif rule != 'other' and specs(value) != specs(key) and not (one_number and leaves_out_count(key, value)):
                        fail(f'{path} ({lang}.{rule}): "{key[:60]}" has different placeholders: {dict(specs(value))}')
                tables[lang][key] = plural.get('other', {}).get('value', '')
            elif unit is not None:
                check_state(path, lang, key, unit)
                tables[lang][key] = unit.get('value', '')
            else:
                fail(f'{path} ({lang}): "{key[:60]}" varies by {", ".join(loc.get("variations", loc))}, the build reads only plain texts and plurals')
    return tables, all_langs

code = {}
for path in sorted(glob.glob(sys.argv[1] + '/**/*.stringsdata', recursive=True)):
    data = json.load(open(path))
    for table, items in data.get('tables', {}).items():
        for item in items:
            where = f"{os.path.relpath(data['source'])}:{item.get('location', {}).get('startingLine', '?')}"
            if table != 'Localizable':
                fail(f'{where}: table "{table}" is not Localizable')
            code.setdefault(item['key'], where)
if not code:
    fail(f'no strings found in {sys.argv[1]}')

swift = {}
for root in ('Sources', 'Extensions', 'Helper', 'Private/Sources'):
    for path in glob.glob(root + '/**/*.swift', recursive=True):
        swift[path] = open(path, encoding='utf-8').read()

# The compiler does not see texts picked through a ternary or looked up by name at run time.
named = {}
for path, text in swift.items():
    for n, line in enumerate(text.split('\n'), 1):
        for m in re.finditer(r'(?:synonyms:|LocalizedStringKey\(|NSLocalizedString\()\s*"((?:[^"\\]|\\.)*)"', line):
            if '\\(' not in m.group(1):
                named.setdefault(unescape(m.group(1)), f'{path}:{n}')
needed = {**named, **code}

tables, langs = load_catalog('Resources/Localizable.xcstrings')
srv_tables, srv_langs = load_catalog('Resources/ServicesMenu.xcstrings')
if srv_langs != langs:
    fail(f'ServicesMenu.xcstrings languages differ from Localizable.xcstrings: {sorted(set(srv_langs) ^ set(langs))}')
english = tables.get('en', {})
all_text = '\n'.join(swift.values())
for path in glob.glob('Helper/*/Info.plist'):
    all_text += ''.join(f'\n"{escape(text)}"' for text in re.findall(r'UsageDescription</key>\s*<string>(.*?)</string>', open(path, encoding='utf-8').read()))
def flatten(s):
    out, i = '', 0
    while (j := s.find('\\(', i)) >= 0:
        out, depth, i = out + s[i:j] + '%', 1, j + 2
        while i < len(s) and depth:
            depth += (s[i] == '(') - (s[i] == ')')
            i += 1
    return out + s[i:]
interpolated = {flatten(m) for m in re.findall(r'"((?:[^"\\\n]|\\.)*\\\((?:[^"\\\n]|\\.)*)"', all_text)}

for key, where in sorted(needed.items(), key=lambda kv: kv[1]):
    if not any(key in table for table in tables.values()):
        fail(f'{where}: "{key[:60]}" is not in Resources/Localizable.xcstrings')
if not os.environ.get('APPSTORE'):
    for key in sorted(english):
        if key not in needed and f'"{escape(key)}"' not in all_text and SPEC.sub('%', escape(key)) not in interpolated:
            fail(f'Resources/Localizable.xcstrings: "{key[:60]}" is not used in the code')
for path, catalog in (('Resources/Localizable.xcstrings', tables), ('Resources/ServicesMenu.xcstrings', srv_tables)):
    for lang, table in catalog.items():
        for key, value in table.items():
            if not value.strip():
                fail(f'{path} ({lang}): "{key[:60]}" is empty')
            elif specs(key) != specs(value):
                fail(f'{path} ({lang}): "{key[:60]}" has different placeholders: {dict(specs(value))}')

LITERAL = re.compile(r'(?:NSMenuItem\(title:|addItem\(withTitle:|addButton\(withTitle:|\bitem\(menu,|'
                     r'\.(?:messageText|informativeText|prompt|toolTip|placeholderString)\s*=|setAccessibilityLabel\()\s*"[^"]*[A-Za-z]')
for path, text in swift.items():
    for n, line in enumerate(text.split('\n'), 1):
        if LITERAL.search(line):
            fail(f'{path}:{n}: this text is not translated, wrap it in String(localized:)')

declared = set(json.loads(subprocess.run(['plutil', '-extract', 'CFBundleLocalizations', 'json', '-o', '-',
                                          'Sources/pikapik/Info.plist'], capture_output=True, text=True).stdout or '[]'))
picker = re.search(r'static let codes = \[([^\]]*)\]', all_text)
picker = set(re.findall(r'"([^"]+)"', picker.group(1))) if picker else set()
for name, found in (('CFBundleLocalizations in Info.plist', declared), ('Language.codes', picker)):
    if found != set(langs):
        fail(f'{name} differs from Resources/Localizable.xcstrings: {sorted(found ^ set(langs))}')
for lang in langs:
    readme = 'README.md' if lang == 'en' else f'docs/readme/README.{lang}.md'
    if not os.path.exists(readme):
        fail(f'{readme} is missing')
    elif '¶' in open(readme, encoding='utf-8').read():
        fail(f'{readme} has a leftover ¶ marker')

if problems:
    print('\n'.join(problems[:60]))
    if len(problems) > 60:
        print(f'... and {len(problems) - 60} more')
    sys.exit(f'Strings check failed: {len(problems)} problem(s)')
print(f'Strings OK: {len(english)} texts in {len(langs)} languages')
PY
