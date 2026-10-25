# Usage: import xcstrings, run with PYTHONPATH=scripts python3 -B as make-lproj.sh and check-strings.sh do.
# Reads a String Catalog the same way for the build and for its check: load() gives its strings and languages, forms() the text and plural forms of one language.
import json
from collections import Counter


def load(path, repeated=None):
    def pairs(items):
        for key, times in Counter(k for k, _ in items).items():
            if times > 1 and repeated:
                repeated(key, times)
        return dict(items)
    with open(path, encoding='utf-8') as f:
        strings = json.load(f, object_pairs_hook=pairs).get('strings', {})
    return strings, sorted({lang for item in strings.values() for lang in item.get('localizations', {})})


def forms(loc):
    if 'stringUnit' in loc:
        return loc['stringUnit'], None
    if 'plural' in loc.get('variations', {}):
        plural = {rule: form.get('stringUnit', {}) for rule, form in loc['variations']['plural'].items()}
        return plural.get('many') or plural.get('other'), plural
    return None, None
