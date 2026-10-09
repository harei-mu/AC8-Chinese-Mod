"""Read-only PE registration inspection, scoped to localization/font UI methods."""
import hashlib
import json
import struct
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / 'tools/python-native'))
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

sys.stdout.reconfigure(encoding='utf-8')
game = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r'E:\SteamLibrary\steamapps\common\ACE COMBAT 8\Game\Binaries\Win64\AceCombat8.exe')
data = game.read_bytes()
pe = pefile.PE(data=data, fast_load=True)
base = pe.OPTIONAL_HEADER.ImageBase
disassembler = Cs(CS_ARCH_X86, CS_MODE_64)

def executable(va):
    return any(s.VirtualAddress <= va - base < s.VirtualAddress + s.Misc_VirtualSize and s.Characteristics & 0x20000000 for s in pe.sections)

results = []
listing = []
for name in ('LocalizeString', 'LocalizeText', 'GetObjName', 'GetObjNameID', 'SetLocalizeText', 'K2_SetText'):
    matches = []
    for encoding in ('ascii', 'utf-16-le'):
        needle = (name + '\0').encode(encoding)
        at = data.find(needle)
        while at >= 0:
            name_va = base + pe.get_rva_from_offset(at)
            address_bytes = struct.pack('<Q', name_va)
            pointer_at = data.find(address_bytes)
            while pointer_at >= 0:
                candidate = struct.unpack_from('<Q', data, pointer_at + 8)[0]
                if executable(candidate):
                    record = {'name': name, 'encoding': encoding, 'wrapperRva': hex(candidate - base), 'registrationRva': hex(pe.get_rva_from_offset(pointer_at))}
                    matches.append(record)
                    code_at = pe.get_offset_from_rva(candidate - base)
                    listing.append(f'\n{name} {record}')
                    for instruction in disassembler.disasm(data[code_at:code_at + 1800], candidate):
                        listing.append(f'{instruction.address - base:08x}: {instruction.mnemonic} {instruction.op_str}')
                        if instruction.mnemonic == 'ret':
                            break
                pointer_at = data.find(address_bytes, pointer_at + 1)
            at = data.find(needle, at + len(needle))
    results.extend(matches)
report = {'exeSha256': hashlib.sha256(data).hexdigest(), 'imageBase': hex(base), 'registrations': results, 'status': 'static inspection only; native ABI and runtime calls unverified'}
for label, rva in {'localization-implementation': 0x6eaf1c0, 'manager-singleton': 0x6eaed90, 'manager-lookup': 0x73b1750, 'GetObjName-wrapper': 0x7d18090, 'SetLocalizeText-wrapper': 0x6eb0d80}.items():
    listing.append(f'\n{label} {hex(rva)}')
    code_at = pe.get_offset_from_rva(rva)
    for instruction in disassembler.disasm(data[code_at:code_at + 1700], base + rva):
        listing.append(f'{instruction.address - base:08x}: {instruction.mnemonic} {instruction.op_str}')
        if instruction.mnemonic == 'ret':
            break
(root / 'work/native-localization-disassembly.txt').write_text('\n'.join(listing), encoding='utf-8')
(root / 'reports/native-localization.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, indent=2))
