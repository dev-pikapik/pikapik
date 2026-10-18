#!/bin/bash
# Usage: scripts/make-lproj.sh
# Turns the String Catalogs in Resources/ into build/lproj/<language>.lproj with Localizable.strings, Localizable.stringsdict and ServicesMenu.strings.
set -euo pipefail
cd "$(dirname "$0")/.."

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
