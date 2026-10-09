"""Audit output and authored translations; fail on unreviewed traditional forms."""
import ctypes
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
sys.stdout.reconfigure(encoding='utf-8')
mapping = ctypes.WinDLL('kernel32', use_last_error=True).LCMapStringEx
mapping.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_wchar_p, ctypes.c_int,
                    ctypes.c_wchar_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ssize_t]
mapping.restype = ctypes.c_int

def simplified(text):
    needed = mapping('zh-CN', 0x02000000, text, -1, None, 0, None, None, 0)
    if not needed:
        raise ctypes.WinError(ctypes.get_last_error())
    buffer = ctypes.create_unicode_buffer(needed)
    if not mapping('zh-CN', 0x02000000, text, -1, buffer, needed, None, None, 0):
        raise ctypes.WinError(ctypes.get_last_error())
    return buffer.value

rows = json.loads((root / 'reports/translation-decisions.json').read_text(encoding='utf-8'))
# Check authored values too, including translations not reached by the current build.
source_rows = []
for filename in ('glossary.json', 'interface-extra.json', 'overrides.json'):
    document = json.loads((root / 'translations' / filename).read_text(encoding='utf-8'))
    def collect(value, key):
        if isinstance(value, dict):
            for child_key, child in value.items():
                collect(child, f'{key}/{child_key}')
        elif isinstance(value, str):
            source_rows.append({'key': key, 'after': value, 'action': 'authored'})
        # Arrays in glossary.json are original values to preserve, not translations.
    collect(document, filename)
suspects = []
for row in rows + source_rows:
    after = row['after']
    candidate = simplified(after)
    if candidate != after:
        if row['key'] == 'OptionmenuTop_Copyright_Dialogue' and row['action'] == 'keep':
            verdict = 'preserve original third-party license notices; not a Chinese UI translation'
        elif simplified(after.replace('著作权', '').replace('瞭望塔', '')) == after.replace('著作权', '').replace('瞭望塔', ''):
            verdict = 'reviewed: standard Simplified Chinese word; NLS conversion is a false positive'
        else:
            verdict = 'needs review'
        suspects.append({'key': row['key'], 'action': row['action'], 'before': after[:160], 'candidate': candidate[:160], 'verdict': verdict})
report = {'method': 'Windows LCMapStringEx LCMAP_SIMPLIFIED_CHINESE; candidates require context review',
          'checkedEntries': len(rows), 'candidateCount': len(suspects),
          'checkedAuthoredValues': len(source_rows),
          'unresolvedCount': sum(x['verdict'] == 'needs review' for x in suspects), 'candidates': suspects}
(root / 'reports/simplified-audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(1 if report['unresolvedCount'] else 0)
