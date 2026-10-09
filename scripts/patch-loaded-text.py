"""Fixed-build offline text-table patch via Windows memory APIs; no injected library.

Only exact audited CP_ strings that fit their existing allocation are eligible.
Default mode reads and reports. --apply never touches code or original game files.
"""
import argparse
import ctypes
from ctypes import wintypes as w
import hashlib
import json
import struct
import sys
import time
from pathlib import Path

root = Path(__file__).resolve().parent.parent
sys.stdout.reconfigure(encoding='utf-8')
parser = argparse.ArgumentParser()
parser.add_argument('pid', type=int)
parser.add_argument('--apply', action='store_true')
parser.add_argument('--wait', type=float, default=0)
parser.add_argument('--hud', action='store_true', help='Include target and HUD table entries; requires the verified font container when applying')
args = parser.parse_args()

class ProcessEntry(ctypes.Structure):
    _fields_ = [('size', w.DWORD), ('usage', w.DWORD), ('pid', w.DWORD),
                ('heap', ctypes.c_size_t), ('module', w.DWORD), ('threads', w.DWORD),
                ('parent', w.DWORD), ('priority', w.LONG), ('flags', w.DWORD), ('name', w.WCHAR * 260)]

class ModuleEntry(ctypes.Structure):
    _fields_ = [('size', w.DWORD), ('id', w.DWORD), ('pid', w.DWORD), ('globalUsage', w.DWORD),
                ('processUsage', w.DWORD), ('base', ctypes.c_void_p), ('bytes', w.DWORD),
                ('module', w.HMODULE), ('name', w.WCHAR * 256), ('path', w.WCHAR * 260)]

api = ctypes.WinDLL('kernel32', use_last_error=True)
api.CreateToolhelp32Snapshot.argtypes = [w.DWORD, w.DWORD]
api.CreateToolhelp32Snapshot.restype = w.HANDLE
api.CloseHandle.argtypes = [w.HANDLE]
for method in ('Process32FirstW', 'Process32NextW'):
    getattr(api, method).argtypes = [w.HANDLE, ctypes.POINTER(ProcessEntry)]
    getattr(api, method).restype = w.BOOL
for method in ('Module32FirstW', 'Module32NextW'):
    getattr(api, method).argtypes = [w.HANDLE, ctypes.POINTER(ModuleEntry)]
    getattr(api, method).restype = w.BOOL
api.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
api.OpenProcess.restype = w.HANDLE
api.ReadProcessMemory.argtypes = [w.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
api.ReadProcessMemory.restype = w.BOOL
api.WriteProcessMemory.argtypes = api.ReadProcessMemory.argtypes
api.WriteProcessMemory.restype = w.BOOL

def snapshot(flags, pid):
    result = api.CreateToolhelp32Snapshot(flags, pid)
    if result == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    return result

def assert_offline_pid():
    snap = snapshot(2, 0)
    found = False
    entry = ProcessEntry(size=ctypes.sizeof(ProcessEntry))
    try:
        valid = api.Process32FirstW(snap, ctypes.byref(entry))
        while valid:
            name = entry.name.lower()
            if 'easyanticheat' in name or 'start_protected_game' in name:
                raise RuntimeError('Protected launcher detected; refusing to access the game')
            if entry.pid == args.pid:
                found = name == 'acecombat8.exe'
            valid = api.Process32NextW(snap, ctypes.byref(entry))
    finally:
        api.CloseHandle(snap)
    if not found:
        raise RuntimeError('Explicit offline game PID mismatch')

assert_offline_pid()
snap = snapshot(0x18, args.pid)
module = ModuleEntry(size=ctypes.sizeof(ModuleEntry))
try:
    if not api.Module32FirstW(snap, ctypes.byref(module)) or module.name.lower() != 'acecombat8.exe':
        raise RuntimeError('Game main module not found')
    base, game_path = module.base, Path(module.path)
finally:
    api.CloseHandle(snap)
expected_hash = '51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f'
if hashlib.file_digest(game_path.open('rb'), 'sha256').hexdigest() != expected_hash:
    raise RuntimeError('Unsupported executable; table offsets must be revalidated')
permission = 0x10 | (0x20 | 0x8 if args.apply else 0)
handle = api.OpenProcess(permission, False, args.pid)
if not handle:
    raise ctypes.WinError(ctypes.get_last_error())

def read(address, size):
    buffer = ctypes.create_string_buffer(size)
    copied = ctypes.c_size_t()
    if not api.ReadProcessMemory(handle, address, buffer, size, ctypes.byref(copied)) or copied.value != size:
        raise ctypes.WinError(ctypes.get_last_error())
    return buffer.raw

def write(address, data):
    buffer = ctypes.create_string_buffer(data)
    copied = ctypes.c_size_t()
    if not api.WriteProcessMemory(handle, address, buffer, len(data), ctypes.byref(copied)) or copied.value != len(data):
        raise ctypes.WinError(ctypes.get_last_error())

def fstring(address):
    data, count, capacity = struct.unpack('<Qii', read(address, 16))
    if not data or count < 1 or count > 4096 or capacity < count or capacity > 65536:
        raise RuntimeError('Unexpected FString bounds')
    value = read(data, count * 2).decode('utf-16-le', errors='strict')
    if not value.endswith('\0') or '\0' in value[:-1]:
        raise RuntimeError('Unexpected FString termination')
    return value[:-1], data, count, capacity

def cp_arrays():
    result = []
    manager = base + 0xe511bc0
    for offset in (0x50, 0xa0):
        data, count = struct.unpack('<Qi', read(manager + offset, 12))
        if count != 2 or not data:
            raise RuntimeError('Localization maps not initialized')
        for i in range(count):
            entry = data + i * 40
            label = fstring(entry)[0]
            array, length, capacity = struct.unpack('<Qii', read(entry + 16, 16))
            if label == 'CP_' and length == 46584 and capacity >= length and array and fstring(array)[0] == '喂喂，听见没？':
                result.append(array)
    if len(result) != 2:
        raise RuntimeError('Expected two fixed-build CP_ tables')
    return list(dict.fromkeys(result))

decisions = json.loads((root / 'reports/translation-decisions.json').read_text(encoding='utf-8'))
selected = {d['index']: d for d in decisions if d['action'] == 'translate' and
            ((d['category'] in ('options', 'menu') and not d['key'].startswith('Hud')) or
             (args.hud and (d['category'] == 'targets' or d['key'].startswith('Hud'))))}
if args.hud and args.apply:
    font_report = json.loads((root / 'reports/hud-font.json').read_text(encoding='utf-8'))
    if not font_report.get('containerVerified') or not font_report.get('requiredTranslationCharactersCovered'):
        raise RuntimeError('HUD font container is not verified')
    for extension, info in font_report['files'].items():
        payload = root / f'dist/hud-font/AC8ChineseHudFont_P.{extension}'
        if hashlib.file_digest(payload.open('rb'), 'sha256').hexdigest() != info['sha256']:
            raise RuntimeError('HUD font container hash mismatch')
        installed = game_path.parent / f'ue4ss/Mods/AC8OverrideLoader/payloads/0020_AC8ChineseHudFont/AC8ChineseHudFont_P.{extension}'
        if not installed.is_file() or hashlib.file_digest(installed.open('rb'), 'sha256').hexdigest() != info['sha256']:
            raise RuntimeError('HUD font is not installed by the offline test launcher')
    if not (game_path.parent / 'dwmapi.dll').is_file():
        raise RuntimeError('HUD font loader is not enabled')
audit = json.loads((root / 'reports/simplified-audit.json').read_text(encoding='utf-8'))
if audit['unresolvedCount']:
    raise RuntimeError('Simplified Chinese audit has unresolved candidates')
report = {'pid': args.pid, 'mode': 'apply' if args.apply else 'read-only', 'exeSha256': expected_hash,
          'hudIncluded': args.hud, 'modified': [], 'alreadyTranslated': 0, 'skipped': [], 'tableCount': 0}
try:
    deadline = time.monotonic() + min(max(args.wait, 0), 30)
    while True:
        try:
            arrays = cp_arrays()
            break
        except (OSError, RuntimeError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.1)
    report['tableCount'] = len(arrays)
    pending = []
    for table_index, array in enumerate(arrays):
        for index, row in selected.items():
            address = array + index * 16
            current, data, count, capacity = fstring(address)
            if current == row['after']:
                report['alreadyTranslated'] += 1
                continue
            if current != row['before']:
                report['skipped'].append({'key': row['key'], 'table': table_index, 'reason': 'source mismatch'})
                continue
            replacement = (row['after'] + '\0').encode('utf-16-le')
            new_count = len(replacement) // 2
            if new_count > capacity:
                report['skipped'].append({'key': row['key'], 'table': table_index, 'reason': 'exceeds existing allocation'})
                continue
            pending.append((address, data, count, capacity, current, replacement, new_count, row, table_index))
    if args.apply:
        assert_offline_pid()
        if cp_arrays() != arrays:
            raise RuntimeError('Text tables changed during validation')
        for address, data, count, capacity, current, replacement, new_count, row, table_index in pending:
            if fstring(address) != (current, data, count, capacity):
                raise RuntimeError('Text changed during validation')
            write(data, replacement)
            write(address + 8, struct.pack('<i', new_count))
            if fstring(address)[0] != row['after']:
                raise RuntimeError('Text write failed readback')
            report['modified'].append({'key': row['key'], 'table': table_index})
    else:
        report['eligible'] = len(pending)
    (root / 'work/loaded-text-patch.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({**report, 'modified': len(report['modified'])}, ensure_ascii=False), flush=True)
finally:
    api.CloseHandle(handle)
