import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { decode, encode, strings, keys } from './gamedata.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const input = path.join(root, 'work/extracted/Live/Content/Localization/GameData');
const glossary = JSON.parse(fs.readFileSync(path.join(root, 'translations/glossary.json'), 'utf8'));
Object.assign(glossary.menu, JSON.parse(fs.readFileSync(path.join(root, 'translations/interface-extra.json'), 'utf8')));
const overrides = JSON.parse(fs.readFileSync(path.join(root, 'translations/overrides.json'), 'utf8'));
const table = keys(decode(path.join(input, 'CP_Cmn.dat')));
const en = strings(decode(path.join(input, 'CP_B.dat'), 1));
const original = strings(decode(path.join(input, 'CP_M.dat'), 12));
const byKey = new Map(table.map(row => [row.key, row]));
if (en.length !== original.length) throw new Error('Language count mismatch');
const translated = [...original], decisions = [], modified = new Map();
const tokens = s => (s.match(/\{[^}]*\}|<[^>]*>|%\d*\$?[sdif]|[\uE000-\uF8FF]/g) ?? []).sort().join('\0');
for (const row of table) {
  let category;
  if (/^Option/i.test(row.key)) category = 'options';
  else if (/^(MainmenuTopTitle_|MainmenuTop_Select_|MainmenuSystemTitle_|MainmenuSystemGeneral_|CampaignMenu_|CampaignDifficulty|CampaignFailed_Select_|CampaignPreparation_|CampaignPause|CampaignBriefing|Training_Name_|Hangar|HudIndicator_|HudMissioninfo_|HudMissionprogress_|MissionWeather_|MissionClouddata_|MissionLocation_Name_|Missiontitle_Name_|MissionNo_Name_)/.test(row.key) || ['DataviewerGallery_Select_Music', 'Missionname_Name_ms30'].includes(row.key)) category = 'menu';
  else if (/^(ContainerAircraft_Name_|ContainerGround_Name_|ContainerEscortTargetName_|ContainerWaypoint_|ContainerUnknown_|HudContainerinfo_)/.test(row.key)) category = 'targets';
  else if (/^Container.*Callsign/.test(row.key)) category = 'callsigns';
  else continue;
  if (row.index >= original.length) throw new Error('Invalid string index');
  const source = original[row.index];
  const base = source.trim();
  let replacement = glossary[category]?.[base];
  let officialSourceKey;
  if (/^MissionLocation_Name_/.test(row.key)) officialSourceKey = row.key.replace('MissionLocation_', 'MissionLocationJP_');
  if (/^Missiontitle_Name_/.test(row.key)) officialSourceKey = row.key.replace('Missiontitle_', 'MissiontitleJp_');
  if (officialSourceKey) {
    const paired = byKey.get(officialSourceKey);
    if (paired && /\p{Script=Han}/u.test(original[paired.index])) replacement = original[paired.index];
  }
  if (/^MissionNo_Name_/.test(row.key) && /^MISSION \d+$/.test(base)) replacement = base.replace('MISSION ', '任务 ');
  if (overrides[row.key]) replacement = overrides[row.key];
  let action = 'keep', reason = '保留型号、专名、呼号或非文字标识';
  let value = source;
  if (/\p{Script=Han}/u.test(source) && !overrides[row.key]) reason = '已有中文';
  else if (replacement) {
    value = source.replace(base, replacement);
    if (value.includes('\0') || tokens(value) !== tokens(source)) throw new Error(`Invalid translation: ${row.key}`);
    if (modified.has(row.index) && modified.get(row.index) !== value) throw new Error('Conflicting aliases');
    modified.set(row.index, value);
    translated[row.index] = value;
    action = 'translate'; reason = overrides[row.key] ? '精确资源键简体用语审校' : officialSourceKey ? `沿用游戏内中文：${officialSourceKey}` : '界面文字或通用目标名称';
  } else if (/^\d+ x \d+（\d+:\d+）$/.test(base)) {
    reason = '分辨率与宽高比';
  } else if (/[A-Za-z]/.test(source) && category === 'options' && source.length < 200 && !glossary.keepOptionValues.includes(base)) {
    action = 'review'; reason = '待核对，不自动覆盖';
  }
  decisions.push({ key: row.key, index: row.index, category, action, reason, before: source, after: value });
}
if (!modified.size) throw new Error('No translations produced');
const stage = path.join(root, 'dist/staging/Live/Content/Localization/GameData');
fs.mkdirSync(stage, { recursive: true });
const output = path.join(stage, 'CP_M.dat');
fs.writeFileSync(output, encode(Buffer.from(translated.join('\0') + '\0', 'utf8'), 12));
const actual = strings(decode(output, 12));
if (JSON.stringify(actual) !== JSON.stringify(translated)) throw new Error('Built DAT failed roundtrip');
for (let i = 0; i < original.length; i++) {
  if (!modified.has(i) && actual[i] !== original[i]) throw new Error('Unexpected change outside allowlist');
}
const groups = Object.fromEntries(['options', 'menu', 'targets', 'callsigns'].map(c => [c, Object.fromEntries(['translate', 'keep', 'review'].map(a => [a, decisions.filter(d => d.category === c && d.action === a).length]))]));
const report = { build: '25201480', status: 'text built; game loading and font rendering NOT verified', changedStrings: modified.size, groups, outputSha256: crypto.createHash('sha256').update(fs.readFileSync(output)).digest('hex'), validation: ['UTF-8 and full table decode', 'string count preserved', 'placeholders preserved', 'all modified entries roundtrip', 'all unrelated entries unchanged'] };
fs.writeFileSync(path.join(root, 'reports/build.json'), JSON.stringify(report, null, 2) + '\n');
fs.writeFileSync(path.join(root, 'reports/translation-decisions.json'), JSON.stringify(decisions, null, 2) + '\n');
const luaDir = path.join(root, 'mod/AC8Chinese/Scripts');
fs.mkdirSync(luaDir, { recursive: true });
const quote = s => '"' + s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n').replaceAll('\r', '\\r').replaceAll('\t', '\\t') + '"';
fs.writeFileSync(path.join(luaDir, 'translations.lua'), '-- Generated by scripts/build-mod.mjs; keyed replacements only.\nreturn {\n' + decisions.filter(d => d.action === 'translate').map(d => `  [${quote(d.key)}] = ${quote(d.after)},`).join('\n') + '\n}\n');
fs.writeFileSync(path.join(luaDir, 'source-text.lua'), '-- Exact source guard: recycled widgets may retain a stale TextID.\nreturn {\n' + decisions.filter(d => d.action === 'translate').map(d => `  [${quote(d.key)}] = {${quote(d.before)}, ${quote(en[d.index])}},`).join('\n') + '\n}\n');
const targetLabels = new Map();
for (const d of decisions.filter(d => d.category === 'targets' && d.action === 'translate')) {
  if (targetLabels.has(d.before) && targetLabels.get(d.before) !== d.after) throw new Error('Ambiguous target label');
  targetLabels.set(d.before, d.after);
}
fs.writeFileSync(path.join(luaDir, 'target-labels.lua'), '-- Generated; only use on verified target-label components.\nreturn {\n' + [...targetLabels].map(([k,v]) => `  [${quote(k)}] = ${quote(v)},`).join('\n') + '\n}\n');
console.log(report);
console.log('REVIEW:', decisions.filter(d => d.action === 'review'));
