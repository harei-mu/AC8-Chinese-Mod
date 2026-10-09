"""Extend the fixed-build offline HUD font with audited Simplified Chinese glyphs.

Preserves all original BC3 blocks, character metrics and remappings. A generated
atlas remains an ignored local game-derived artifact. Requires asset-json.ps1
export of the two original fonts; never edits the game installation.
"""
import base64
import copy
import hashlib
import io
import json
import struct
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / 'tools/python-native'))
sys.stdout.reconfigure(encoding='utf-8')
from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

def load(path):
    return json.loads((root / path).read_text(encoding='utf-8'))

def save(path, value):
    (root / path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

asset = load('work/offline-font.json')
face = load('work/noto-font.json')
font_export, texture = asset['Exports']
assert font_export['ObjectName'] == 'AcesSleipnir-Regular_HUD_OFFLINE'
assert texture['ObjectName'] == 'AcesSleipnir-Regular_HUD_OFFLINE_PageA'
properties = {p['Name']: p for p in font_export['Data']}
characters = properties['Characters']['Value']
assert len(characters) == 351 and properties['IsRemapped']['Value'] == 1
original_characters = copy.deepcopy(characters)
remap_data = base64.b64decode(font_export['Extras'])
assert len(remap_data) == 4 + 351 * 4 and struct.unpack_from('<I', remap_data)[0] == 351
remap = list(struct.iter_unpack('<HH', remap_data[4:]))
assert len(dict(remap)) == len(remap) and max(v for _, v in remap) < len(characters)

face_data = base64.b64decode(face['Exports'][0]['Extras'])
assert struct.unpack_from('<III', face_data) == (1, 1, len(face_data) - 12)
ttf = face_data[12:]
assert ttf[:4] == b'\0\1\0\0'
font_file = root / 'work/NotoSansSC-SemiBold.ttf'
font_file.write_bytes(ttf)
cmap = TTFont(io.BytesIO(ttf)).getBestCmap()
font = ImageFont.truetype(str(font_file), 30)

decisions = load('reports/translation-decisions.json')
selected = [r for r in decisions if r['action'] == 'translate' and (r['category'] == 'targets' or r['key'].startswith('Hud'))]
# Include every authored translation to make subsequent scoped additions possible.
required = set(''.join(r['after'] for r in decisions if r['action'] == 'translate'))
required |= set('友军航空母舰坚忍号潜射巡航导弹机炮导弹诱饵损伤目标时间得分高度速度')
required.discard('\n')
required.discard('\r')
extra_chars = sorted(required - {chr(k) for k, _ in remap}, key=ord)
assert all(ord(c) <= 65535 and ord(c) in cmap for c in extra_chars), 'Font face lacks a required glyph'

old_extra = base64.b64decode(texture['Extras'])
assert len(old_extra) == 262248 and old_extra[:12] == bytes.fromhex('050005000100000001000000')
assert struct.unpack_from('<Q', old_extra, 20)[0] == 262220
assert old_extra[60:68] == b'PF_DXT5\0'
assert struct.unpack_from('<iii', old_extra, 44) == (512, 512, 1)
assert struct.unpack_from('<ii', old_extra, 68) == (0, 1)
assert struct.unpack_from('<i', old_extra, 76)[0] == 0
assert struct.unpack_from('<iii', old_extra, 80 + 262144) == (512, 512, 1)
assert asset['DataResources'][0]['SerialOffset'] == 120
assert asset['DataResources'][0]['SerialSize'] == 262144

# Reserve the entire original 512-square page. Lay out new glyphs in fixed cells.
size, cell = 1024, 34
slots = [(x, y) for y in range(2, size - cell, cell) for x in range(2, size - cell, cell)
         if x >= 514 or y >= 514]
if len(extra_chars) > len(slots):
    raise RuntimeError(f'Atlas cannot hold {len(extra_chars)} glyphs in {len(slots)} slots')
alpha = Image.new('L', (size, size), 0)
draw = ImageDraw.Draw(alpha)
glyph_report = []
for character, (x, y) in zip(extra_chars, slots):
    left, top, right, bottom = font.getbbox(character)
    width, height = right - left, bottom - top
    assert 0 < width <= cell - 2 and 0 < height <= cell - 2
    draw.text((x - left, y - top), character, font=font, fill=255)
    index = len(characters)
    new = copy.deepcopy(original_characters[65])
    new['Name'] = new['Value'][0]['Name'] = str(index)
    new['Value'][0]['Value'].update(StartU=x, StartV=y, USize=max(30, width), VSize=height,
                                  TextureIndex=0, VerticalOffset=max(0, 34 - height))
    characters.append(new)
    remap.append((ord(character), index))
    glyph_report.append({'character': character, 'index': index, 'rect': [x, y, width, height]})

atlas = Image.new('RGBA', (size, size), (255, 255, 255, 0))
atlas.putalpha(alpha)
dds = io.BytesIO()
atlas.save(dds, format='DDS', pixel_format='DXT5')
dds_data = dds.getvalue()
assert dds_data[:4] == b'DDS ' and dds_data[84:88] == b'DXT5'
blocks = bytearray(dds_data[128:])
assert len(blocks) == size * size
original_blocks = old_extra[80:80 + 262144]
for block_row in range(128):
    old_start = block_row * 128 * 16
    new_start = block_row * (size // 4) * 16
    blocks[new_start:new_start + 128 * 16] = original_blocks[old_start:old_start + 128 * 16]
for block_row in range(128):
    assert blocks[block_row * 4096:block_row * 4096 + 2048] == original_blocks[block_row * 2048:(block_row + 1) * 2048]

new_extra = bytearray(old_extra[:80])
struct.pack_into('<Q', new_extra, 20, len(blocks) + 76)
struct.pack_into('<ii', new_extra, 44, size, size)
new_extra.extend(blocks)
new_extra.extend(struct.pack('<iii', size, size, 1) + old_extra[-12:])
assert len(new_extra) == len(blocks) + 104
texture['Extras'] = base64.b64encode(new_extra).decode('ascii')
texture['Data'][0]['Value'][0]['Value'] = [size, size]
for field in ('SerialSize', 'RawSize'):
    asset['DataResources'][0][field] = len(blocks)
font_export['Extras'] = base64.b64encode(struct.pack('<I', len(remap)) + b''.join(struct.pack('<HH', *p) for p in remap)).decode('ascii')
for p in properties['ImportOptions']['Value']:
    if p['Name'] in ('TexturePageWidth', 'TexturePageMaxHeight'):
        p['Value'] = size
assert characters[:351] == original_characters
assert remap[:351] == list(struct.iter_unpack('<HH', remap_data[4:]))
assert required <= {chr(k) for k, _ in remap}
save('work/offline-font-zh.json', asset)

# Preview uses the actual BC3 payload, including preserved original blocks.
preview_dds = bytearray(dds_data[:128]) + blocks
preview = Image.open(io.BytesIO(preview_dds))
preview.getchannel('A').save(root / 'work/hud-font-atlas.png')
sample = Image.new('RGBA', (900, 120), (18, 25, 30, 255))
remap_dict = dict(remap)
for line_index, line in enumerate(['ALLY 友军  AIRCRAFT CARRIER 航空母舰', 'SLCM 潜射巡航导弹  坚忍号  SPEED 速度']):
    position = 12
    for ch in line:
        metrics = characters[remap_dict[ord(ch)]]['Value'][0]['Value']
        x, y, width, height = (metrics[k] for k in ('StartU', 'StartV', 'USize', 'VSize'))
        crop = preview.crop((x, y, x + width, y + height))
        green = Image.new('RGBA', crop.size, (120, 242, 190, 255))
        green.putalpha(crop.getchannel('A'))
        sample.alpha_composite(green, (position, 8 + line_index * 52 + metrics['VerticalOffset']))
        position += width + 1
sample.save(root / 'work/hud-font-preview.png')
save('reports/hud-font.json', {'status': 'BUILT: glyph/atlas checks passed; runtime rendering pending',
     'gameBuild': '25201480', 'package': '/Game/UI/Font/AcesSleipnir-Regular_HUD_OFFLINE',
     'originalCharacters': 351, 'addedCharacters': len(extra_chars), 'totalCharacters': len(characters),
     'atlasSize': [size, size], 'originalBlocksPreserved': True, 'requiredTranslationCharactersCovered': True,
     'sourceFontSha256': hashlib.sha256(ttf).hexdigest(), 'addedCodepoints': ''.join(extra_chars)})
print(json.dumps({'addedCharacters': len(extra_chars), 'totalCharacters': len(characters), 'atlasSize': size}, ensure_ascii=False))
