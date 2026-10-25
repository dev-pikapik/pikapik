#!/bin/bash
# Usage: scripts/make-lproj.sh
# Turns the String Catalogs in Resources/ into build/lproj/<language>.lproj with Localizable.strings, Localizable.stringsdict and ServicesMenu.strings.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf build/lproj
PYTHONPATH=scripts python3 -B - <<'XCPY'
import os, plistlib
import xcstrings

def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')

loc_data, langs = xcstrings.load('Resources/Localizable.xcstrings')
srv_data, _ = xcstrings.load('Resources/ServicesMenu.xcstrings')
for lang in langs:
    out_dir = f'build/lproj/{lang}.lproj'
    os.makedirs(out_dir, exist_ok=True)
    lines = []
    sdict = {}
    for key, item in loc_data.items():
        text, plural = xcstrings.forms(item.get('localizations', {}).get(lang, {}))
        if text is None:
            continue
        lines.append(f'"{esc(key)}" = "{esc(text["value"])}";\n')
        if plural:
            var_name = 'lines' if 'lines' in key else 'count'
            rule_dict = {
                'NSStringFormatSpecTypeKey': 'NSStringPluralRuleType',
                'NSStringFormatValueTypeKey': 'lld',
            }
            for rule, unit in plural.items():
                rule_dict[rule] = unit['value']
            sdict[key] = {'NSStringLocalizedFormatKey': f'%#@{var_name}@', var_name: rule_dict}
    with open(f'{out_dir}/Localizable.strings', 'w', encoding='utf-8') as f:
        f.writelines(lines)
    with open(f'{out_dir}/Localizable.stringsdict', 'wb') as f:
        plistlib.dump(sdict, f, sort_keys=False)
    srv_lines = []
    for key, item in srv_data.items():
        text, plural = xcstrings.forms(item.get('localizations', {}).get(lang, {}))
        if text is not None and plural is None:
            srv_lines.append(f'"{esc(key)}" = "{esc(text["value"])}";\n')
    with open(f'{out_dir}/ServicesMenu.strings', 'w', encoding='utf-8') as f:
        f.writelines(srv_lines)
XCPY
