"""Read-only inspection of the fixed-build localization tables; no function hooks."""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / 'tools/python-native'))
import frida
sys.stdout.reconfigure(encoding='utf-8')
pid = int(sys.argv[1])
device = frida.get_local_device()
processes = device.enumerate_processes()
if any('easyanticheat' in p.name.lower() or 'start_protected_game' in p.name.lower() for p in processes):
    raise RuntimeError('Protected launcher detected; inspect only the offline test')
if not any(p.pid == pid and p.name.lower() == 'acecombat8.exe' for p in processes):
    raise RuntimeError('Game PID mismatch')
session = device.attach(pid)
script = session.create_script(r'''
function fstring(p) {
  const count = p.add(8).readS32(), capacity = p.add(12).readS32();
  if (count < 0 || count > 250 || capacity < count || capacity > 1000) return null;
  return count ? p.readPointer().readUtf16String(count - 1) : '';
}
const game = Process.getModuleByName('AceCombat8.exe');
const manager = game.base.add(0xe511bc0);
const tables = [];
for (const offset of [0x50, 0xa0]) {
  const map = manager.add(offset), data = map.readPointer(), num = map.add(8).readS32();
  const entries = [];
  if (num >= 0 && num <= 30 && !data.isNull()) for (let i=0; i<num; ++i) {
    try {
      const item = data.add(i*40), label = fstring(item);
      const count = item.add(24).readS32(), array = item.add(16).readPointer();
      if (label !== null && count >= 0 && count < 100000) entries.push({label,count,array:array.toString(),sample:count && !array.isNull() ? fstring(array) : null});
    } catch (error) { entries.push({index:i,error:String(error)}); }
  }
  tables.push({offset,num,entries});
}
send({tables});
''')
events = []
def message(event, data):
    events.append(event)
    print(json.dumps(event, ensure_ascii=False), flush=True)
script.on('message', message)
try:
    script.load()
finally:
    script.unload()
    session.detach()
    (root / 'work/loaded-text-inspection.json').write_text(json.dumps(events, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
