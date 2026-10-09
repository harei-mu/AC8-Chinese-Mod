import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = path.join(root, 'dist/AC8简体汉化');
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
const setupExe = path.join(root, 'work/AC8Setup-' + Date.now() + '.exe');
execFileSync(path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'),
  ['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(root,'scripts/compile-installer.ps1'),
   '-Source',path.join(root,'installer/Setup.cs'),'-Output',setupExe,'-Setup'], {stdio:'inherit'});
put('汉化安装器.exe', fs.readFileSync(setupExe));
fs.unlinkSync(setupExe);
put('使用说明.txt', '\ufeff'+`ACE COMBAT 8 简体汉化 0.3.0\r\n\r\n支持游戏 1.1.2.0 / Steam build 25201480，仅用于单机。\r\n\r\n1. 解压整个文件夹，正常退出游戏。\r\n2. 双击“汉化安装器.exe”，选择界面汉化、HUD 汉化或全部汉化，点击安装。\r\n3. 安装会正常退出并重新打开 Steam。以后直接在 Steam 点击“开始游戏”。\r\n4. 更换汉化内容：再次打开安装器，选择新的内容并点击安装。\r\n5. 解除汉化：正常退出游戏后，打开“汉化安装器.exe”，点击“卸载汉化”。卸载会恢复原 Steam 启动选项。\r\n\r\n界面：菜单、设置、训练、机库、资料、战绩、任务结算等。\r\nHUD：仪表、雷达、普通目标类别、目标名称和战斗提示。\r\n机炮、导弹、诱饵弹等与仪表共用的名称随 HUD 组件翻译。型号、武器代号、罗盘字母及玩家自定义名称保留。\r\n全程使用简体中文。游戏自带的剧情字幕保留。\r\n\r\n无需 Python 或开发环境。原始游戏程序、原始资源和存档不会被覆盖。\r\n发现其他 MOD 加载器或自定义启动器时，安装会停止并保留现有文件。\r\n卸载只移除归属于本汉化且校验一致的文件；自行修改的文件会保留。\r\n游戏更新后如版本校验不通过，请更新汉化包。\r\n`);
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
  legacyOwner:root,files};
fs.writeFileSync(path.join(out,'package-manifest.json'),JSON.stringify(manifest,null,2)+'\n');
console.log({package:out,files:files.length,translations:rows.size,components:Object.fromEntries(['UI','HUD','Shared'].map(c=>[c,[...rows.values()].filter(r=>r.component===c).length]))});
