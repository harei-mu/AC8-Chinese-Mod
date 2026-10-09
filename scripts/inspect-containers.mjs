import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const game = process.argv[2];
if (!game) throw new Error('Usage: node scripts/inspect-containers.mjs GAME_DIRECTORY');
const paks = path.join(game, 'Game', 'Content', 'Paks');
function readRange(file, offset, length) {
  const fd = fs.openSync(file, 'r');
  try {
    const b = Buffer.alloc(length);
    if (fs.readSync(fd, b, 0, length, offset) !== length) throw new Error('Truncated file');
    return b;
  } finally { fs.closeSync(fd); }
}
const rows = [];
for (const name of fs.readdirSync(paks).sort()) {
  const file = path.join(paks, name);
  const size = fs.statSync(file).size;
  const row = { name, size };
  if (name.endsWith('.utoc')) {
    const b = readRange(file, 0, 144);
    if (b.subarray(0, 16).toString() !== '-==--==--==--==-') throw new Error(`Invalid UTOC: ${name}`);
    Object.assign(row, { version: b[16], headerSize: b.readUInt32LE(20), entryCount: b.readUInt32LE(24), directoryIndexSize: b.readUInt32LE(48), flags: b[80], encrypted: !!(b[80] & 2), signed: !!(b[80] & 4) });
  } else if (name.endsWith('.pak')) {
    const length = Math.min(512, size);
    const b = readRange(file, size - length, length);
    const i = b.lastIndexOf(Buffer.from('e1126f5a', 'hex'));
    if (i < 17 || i + 44 > b.length) throw new Error(`Unsupported PAK footer: ${name}`);
    Object.assign(row, { version: b.readUInt32LE(i + 4), encryptedIndex: !!b[i - 1], indexOffset: Number(b.readBigUInt64LE(i + 8)), indexSize: Number(b.readBigUInt64LE(i + 16)) });
    if (row.indexOffset + row.indexSize > size) throw new Error(`Invalid index range: ${name}`);
  }
  rows.push(row);
}
fs.mkdirSync(path.join(root, 'reports'), { recursive: true });
fs.writeFileSync(path.join(root, 'reports', 'containers.json'), JSON.stringify({ containers: rows }, null, 2) + '\n');
console.log(JSON.stringify(rows.filter(r => r.version !== undefined), null, 2));
