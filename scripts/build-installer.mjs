import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = path.resolve(root, process.argv[2] ?? 'dist/AC8简体汉化');
if (!out.startsWith(path.join(root, 'dist') + path.sep)) throw new Error('Package output must stay inside dist');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const audit = JSON.parse(fs.readFileSync(path.join(root, 'reports/simplified-audit.json')));
const font = JSON.parse(fs.readFileSync(path.join(root, 'reports/hud-font.json')));
if (audit.unresolvedCount || !font.containerVerified || !font.requiredTranslationCharactersCovered) throw new Error('Translation/font verification failed');
const outputs = new Set();
function put(relative, bytes) {
  const file = path.join(out, relative);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, bytes); outputs.add(relative);
}
function copy(relative, source, expected) {
  const bytes = fs.readFileSync(path.join(root, source));
  if (expected && hash(bytes) !== expected) throw new Error(`Dependency hash mismatch: ${source}`);
  put(relative, bytes);
}
for (const file of fs.readdirSync(path.join(root, 'installer')).filter(x => x.endsWith('.ps1'))) {
  // Windows PowerShell 5.1 requires BOM to parse Chinese literals correctly.
  put('App/' + file, '\ufeff' + fs.readFileSync(path.join(root, 'installer', file), 'utf8').replace(/^\ufeff/, ''));
}
const assembly = path.join(root, 'work/AC8TextTables-' + Date.now() + '.dll');
execFileSync(path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'),
  ['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(root,'scripts/compile-installer.ps1'),
   '-Source',path.join(root,'installer/Text-Tables.cs'),'-Output',assembly], {stdio:'inherit'});
put('App/AC8TextTables.dll', fs.readFileSync(assembly));
fs.unlinkSync(assembly);
const decisions = JSON.parse(fs.readFileSync(path.join(root, 'reports/translation-decisions.json')));
const rows = new Map();
for (const d of decisions.filter(x => x.action === 'translate')) {
  const component = /^WeaponShort_Name_(?:mg|msl|flr)$/.test(d.key) ? 'Shared' :
    d.category === 'targets' || d.category === 'callsigns' || d.key.startsWith('Hud') ? 'HUD' : 'UI';
  if (rows.has(d.index) && rows.get(d.index).after !== d.after) throw new Error('Conflicting indexed translations');
  rows.set(d.index, { key:d.key, index:d.index, before:d.before, after:d.after, component });
}
put('App/translations.json', JSON.stringify([...rows.values()], null, 2) + '\n');
copy('Payload/dwmapi.dll', 'tools/ue4ss-package/dwmapi.dll');
copy('Payload/runtime/UE4SS.dll', 'tools/ue4ss-package/ue4ss/UE4SS.dll');
let settings = fs.readFileSync(path.join(root, 'tools/ue4ss-package/ue4ss/UE4SS-settings.ini'), 'utf8');
settings = settings.replace(/^MajorVersion =.*$/m, 'MajorVersion = 5').replace(/^MinorVersion =.*$/m, 'MinorVersion = 4')
  .replace(/^EnableAutoReloadingLuaMods =.*$/m, 'EnableAutoReloadingLuaMods = 0');
put('Payload/runtime/UE4SS-settings.ini', settings);
put('Payload/runtime/Mods/mods.txt', 'AC8Chinese : 0\r\nAC8OverrideLoader : 1\r\n');
copy('Payload/runtime/Mods/AC8OverrideLoader/dlls/main.dll', 'tools/ac8-override-loader/main.dll',
  '225c8d6c3fbf5e8882cb8e334dbd3426cb24a1415b3585073cc4264ae834f851');
for (const ext of ['utoc','ucas','pak']) {
  copy(`Payload/runtime/Mods/AC8OverrideLoader/payloads/0020_AC8ChineseHudFont/AC8ChineseHudFont_P.${ext}`,
    `dist/hud-font/AC8ChineseHudFont_P.${ext}`, font.files[ext].sha256);
}
copy('Licenses/UE4SS.txt', 'tools/ue4ss-package/ue4ss/LICENSE');
copy('Licenses/AC8OverrideLoader.txt', 'tools/ac8-override-loader/LICENSE');
copy('Licenses/NotoSansSC.txt', 'docs/LICENSE-Noto.txt');
copy('LICENSE', 'LICENSE');
copy('注意事项.txt', 'docs/注意事项.txt');
copy('Licenses/THIRD-PARTY-NOTICES.md', 'docs/THIRD-PARTY-NOTICES.md');
const setupExe = path.join(root, 'work/AC8Setup-' + Date.now() + '.exe');
execFileSync(path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'),
  ['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(root,'scripts/compile-installer.ps1'),
   '-Source',path.join(root,'installer/Setup.cs'),'-Output',setupExe,'-Setup'], {stdio:'inherit'});
put('汉化安装器.exe', fs.readFileSync(setupExe));
fs.unlinkSync(setupExe);
copy('使用说明.txt', 'docs/使用说明.txt');
// Remove stale outputs by exact file path, restricted to this package's directory.
function walk(dir) {return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);}
for (const file of walk(out)) {
  const relative=path.relative(out,file).replaceAll('\\','/');
  if (!outputs.has(relative) && relative !== 'package-manifest.json') fs.unlinkSync(file);
}
const files = [...outputs].sort().map(relative => {
  const bytes=fs.readFileSync(path.join(out,relative));return {path:relative,bytes:bytes.length,sha256:hash(bytes)};
});
const manifest = {owner:'AC8ChineseMod:offline-v1',version:'0.3.0',gameBuild:'25201480',gameVersion:'1.1.2.0',
  exeSha256:'51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F',
  license:'GPL-3.0-only',repository:'harei-mu/AC8-Chinese-Mod',files};
fs.writeFileSync(path.join(out,'package-manifest.json'),JSON.stringify(manifest,null,2)+'\n');
console.log({package:out,files:files.length,translations:rows.size,components:Object.fromEntries(['UI','HUD','Shared'].map(c=>[c,[...rows.values()].filter(r=>r.component===c).length]))});
