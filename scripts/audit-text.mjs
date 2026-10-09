import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { decode, encode, strings, keys } from './gamedata.mjs';
import zlib from 'node:zlib';
import { scramble } from './gamedata.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'work/extracted/Live/Content/Localization/GameData');
const entries = keys(decode(path.join(dir, 'CP_Cmn.dat')));
const en = strings(decode(path.join(dir, 'CP_B.dat'), 1));
const zh = strings(decode(path.join(dir, 'CP_M.dat'), 12));
if (en.length !== zh.length) throw new Error('Language table count mismatch');
const rows = entries.map(entry => {
  if (entry.index >= en.length) throw new Error('Key index out of bounds');
  return { ...entry, en: en[entry.index], zh: zh[entry.index] };
});
for (const name of ['CP_Cmn.dat', 'CP_B.dat', 'CP_M.dat']) {
  const offset = name.includes('_B') ? 1 : name.includes('_M') ? 12 : 0;
  const raw = decode(path.join(dir, name), offset);
  const roundtrip = encode(raw, offset);
  if (!zlib.inflateSync(scramble(roundtrip, roundtrip.length + offset)).equals(raw)) throw new Error('Roundtrip failed');
}
fs.writeFileSync(path.join(root, 'work/text-audit.json'), JSON.stringify(rows, null, 2) + '\n');
const stats = { build: '25201480', scope: 'offline single player', keys: rows.length, languageStrings: en.length, englishTable: 'CP_B.dat', simplifiedChineseTable: 'CP_M.dat', identicalNonempty: rows.filter(r => r.en && r.en === r.zh).length, roundtrip: 'PASS: common, English and Simplified Chinese' };
fs.writeFileSync(path.join(root, 'reports/text-audit-summary.json'), JSON.stringify(stats, null, 2) + '\n');
console.log(stats);
console.log(rows.filter(r => /option|radar|target|plane.*name|aircraft.*name/i.test(r.key)).slice(0, 45));
