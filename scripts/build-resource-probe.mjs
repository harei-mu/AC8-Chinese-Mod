import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { decode, encode, strings } from './gamedata.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(root, 'work/extracted/Live/Content/Localization/GameData/CP_M.dat');
const original = strings(decode(source, 12));
const output = [...original];
const decisions = JSON.parse(fs.readFileSync(path.join(root, 'reports/translation-decisions.json'), 'utf8'));
const selected = decisions.filter(d => d.action === 'translate' && ['options', 'menu'].includes(d.category) && !d.key.startsWith('Hud'));
const changed = new Set();
for (const d of selected) {
  if (original[d.index] !== d.before) throw new Error(`Source mismatch: ${d.key}`);
  output[d.index] = d.after;
  changed.add(d.index);
}
const staging = path.join(root, 'dist/resource-probe-staging/Live/Content/Localization/GameData');
fs.mkdirSync(staging, { recursive: true });
const dat = path.join(staging, 'CP_M.dat');
fs.writeFileSync(dat, encode(Buffer.from(output.join('\0') + '\0', 'utf8'), 12));
if (JSON.stringify(strings(decode(dat, 12))) !== JSON.stringify(output)) throw new Error('Resource probe DAT roundtrip failed');
const destination = path.join(root, 'dist/resource-probe');
fs.mkdirSync(destination, { recursive: true });
const container = path.join(destination, 'AC8ChineseMenuProbe_P.utoc');
const retoc = path.join(root, 'tools/retoc/retoc.exe');
execFileSync(retoc, ['to-zen', '--version', 'UE5_4', path.join(root, 'dist/resource-probe-staging'), container], { stdio: 'inherit' });
execFileSync(retoc, ['verify', container], { stdio: 'inherit' });
// retoc does not copy arbitrary .dat files. Build and roundtrip the companion explicitly.
const repak = path.join(root, 'tools/repak/repak.exe');
const pak = path.join(destination, 'AC8ChineseMenuProbe_P.pak');
execFileSync(repak, ['pack', '--version', 'V11', path.join(root, 'dist/resource-probe-staging'), pak], { stdio: 'inherit' });
const listing = execFileSync(repak, ['list', pak], { encoding: 'utf8' }).trim();
if (listing !== 'Live/Content/Localization/GameData/CP_M.dat') throw new Error(`Unexpected companion contents: ${listing}`);
const roundtrip = path.join(root, 'work/resource-probe-roundtrip');
execFileSync(repak, ['unpack', pak, '-o', roundtrip, '-f'], { stdio: 'inherit' });
if (!fs.readFileSync(dat).equals(fs.readFileSync(path.join(roundtrip, listing)))) throw new Error('Companion DAT content mismatch');
const files = Object.fromEntries(['utoc', 'ucas', 'pak'].map(ext => {
  const file = path.join(destination, `AC8ChineseMenuProbe_P.${ext}`);
  return [ext, { bytes: fs.statSync(file).size, sha256: crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') }];
}));
const report = { gameBuild: '25201480', status: 'EXPERIMENTAL: container integrity verified; DAT companion mounting and in-game lookup unverified',
  changedStrings: changed.size, combatLabelsExcluded: true, runtimeSubstitutionDisabledDuringProbe: true, files };
fs.writeFileSync(path.join(root, 'reports/resource-probe.json'), JSON.stringify(report, null, 2) + '\n');
console.log(report);
