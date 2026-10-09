"""Attach a bounded, read-only localization trace to an explicitly named offline PID."""
import json
import sys
import time
from pathlib import Path

root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / 'tools/python-native'))
import frida

sys.stdout.reconfigure(encoding='utf-8')
pid = int(sys.argv[1])
duration = min(int(sys.argv[2]) if len(sys.argv) > 2 else 45, 60)
events = []
source = r'''
const game = Process.getModuleByName('AceCombat8.exe');
function readString(p) {
  try {
    if (p.isNull()) return null;
    const n = p.add(8).readS32();
    if (n < 1 || n > 250) return null;
    return p.readPointer().readUtf16String(n - 1);
  } catch (_) { return null; }
}
let count = 0;
for (const rva of [0x6eaf1c0, 0x73b1750]) Interceptor.attach(game.base.add(rva), {
  onEnter(args) {
    this.output = args[0];
    this.key = readString(args[2]);
    this.enumArg = args[1].toInt32();
    this.rva = rva;
    this.trace = count < 8 ? Thread.backtrace(this.context, Backtracer.ACCURATE).map(p => p.sub(game.base).toString()) : [];
  },
  onLeave(retval) {
    if (count++ < 60) send({ type: 'localize', rva:this.rva.toString(16), key: this.key, enumArg: this.enumArg, result: readString(rva === 0x73b1750 ? retval : this.output), trace: this.trace });
  }
});
send({type:'ready', pid:Process.id, game:game.name});
'''
device = frida.get_local_device()
process = next((p for p in device.enumerate_processes() if p.pid == pid), None)
if not process or process.name.lower() != 'acecombat8.exe':
    raise RuntimeError('Explicit offline game PID no longer matches')
session = device.attach(pid)
script = session.create_script(source)
def message(event, data):
    events.append(event)
    print(json.dumps(event, ensure_ascii=False), flush=True)
script.on('message', message)
script.load()
try:
    time.sleep(duration)
finally:
    script.unload()
    session.detach()
    (root / 'work/native-observe.json').write_text(json.dumps(events, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
