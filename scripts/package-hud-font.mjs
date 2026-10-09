import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const assetName = 'Live/Content/UI/Font/AcesSleipnir-Regular_HUD_OFFLINE';
const staging = path.join(root, 'dist/hud-font-staging');
const destination = path.join(root, 'dist/hud-font');
const roundtrip = path.join(root, 'work/hud-font-roundtrip');
const validationInput = path.join(root, 'work/hud-font-validation-input');
const retoc = path.join(root, 'tools/retoc/retoc.exe');
const original = JSON.parse(fs.readFileSync(path.join(root, 'work/offline-font-zh.json'), 'utf8'));
const readback = JSON.parse(fs.readFileSync(path.join(root, 'work/offline-font-zh-readback.json'), 'utf8'));
for (let i = 0; i < original.Exports.length; i++) {
  if (JSON.stringify(original.Exports[i].Data) !== JSON.stringify(readback.Exports[i].Data) || original.Exports[i].Extras !== readback.Exports[i].Extras) {
    throw new Error('Font serializer readback mismatch');
  }
}
if (JSON.stringify(original.DataResources) !== JSON.stringify(readback.DataResources)) throw new Error('Font bulk metadata mismatch');
fs.mkdirSync(destination, { recursive: true });
const container = path.join(destination, 'AC8ChineseHudFont_P.utoc');
execFileSync(retoc, ['to-zen', '--version', 'UE5_4', staging, container], { stdio: 'inherit' });
execFileSync(retoc, ['verify', container], { stdio: 'inherit' });
// Native class imports resolve through the original game's small global type table.
fs.mkdirSync(validationInput, { recursive: true });
const gamePaks = 'E:/SteamLibrary/steamapps/common/ACE COMBAT 8/Game/Content/Paks';
for (const ext of ['utoc', 'ucas']) {
  fs.copyFileSync(path.join(gamePaks, `global.${ext}`), path.join(validationInput, `global.${ext}`));
  fs.copyFileSync(path.join(destination, `AC8ChineseHudFont_P.${ext}`), path.join(validationInput, `AC8ChineseHudFont_P.${ext}`));
}
execFileSync(retoc, ['to-legacy', '--filter', '/UI/Font/', '--no-shaders', '--no-script-objects', validationInput, roundtrip], { stdio: 'inherit' });
if (!fs.readFileSync(path.join(staging, assetName + '.uexp')).equals(fs.readFileSync(path.join(roundtrip, assetName + '.uexp')))) {
  throw new Error('Font IoStore roundtrip changed export payload');
}
const files = Object.fromEntries(['utoc', 'ucas', 'pak'].map(ext => {
  const file = path.join(destination, `AC8ChineseHudFont_P.${ext}`);
  return [ext, { bytes: fs.statSync(file).size, sha256: crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') }];
}));
const reportFile = path.join(root, 'reports/hud-font.json');
const report = JSON.parse(fs.readFileSync(reportFile, 'utf8'));
report.files = files;
report.containerVerified = true;
report.exportPayloadRoundtripExact = true;
fs.writeFileSync(reportFile, JSON.stringify(report, null, 2) + '\n');
console.log({ files, containerVerified: true, exportPayloadRoundtripExact: true });
