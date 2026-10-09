import fs from 'node:fs';
import zlib from 'node:zlib';

// AC series DAT byte scrambling followed by a zlib stream.
// Format reference: https://github.com/GreenTrafficLight/Ace7-Localization-Format
export function scramble(input, seed) {
  const output = Buffer.from(input);
  let shift = 0, state = seed & 255;
  for (let i = 0; i < output.length; i++) {
    shift = ((shift << 1) | ((~(shift ^ (shift << 3)) >>> 7) & 1)) >>> 0;
    state = (state * 5 + 1) & 255;
    output[i] ^= (shift + state) & 255;
  }
  return output;
}
export function decode(file, languageOffset = 0) {
  const input = fs.readFileSync(file);
  return zlib.inflateSync(scramble(input, input.length + languageOffset), { maxOutputLength: 64 * 1024 * 1024 });
}
export function encode(data, languageOffset = 0) {
  const compressed = zlib.deflateSync(data);
  return scramble(compressed, compressed.length + languageOffset);
}
export function strings(data) {
  if (data.at(-1) !== 0) throw new Error('Missing final string terminator');
  return new TextDecoder('utf-8', { fatal: true }).decode(data).slice(0, -1).split('\0');
}
export function keys(data) {
  let at = 0;
  const entries = [];
  function int() {
    if (at + 4 > data.length) throw new Error('Truncated common table');
    const n = data.readInt32LE(at); at += 4; return n;
  }
  function walk(prefix, depth) {
    if (depth > 256) throw new Error('Common table depth exceeded');
    const count = int();
    if (count < 0 || count > 100000) throw new Error('Invalid common table count');
    for (let i = 0; i < count; i++) {
      const length = int();
      if (length < 0 || at + length > data.length) throw new Error('Invalid key length');
      const part = new TextDecoder('utf-8', { fatal: true }).decode(data.subarray(at, at + length));
      at += length;
      const index = int();
      if (index >= 0) entries.push({ key: prefix + part, index });
      walk(prefix + part, depth + 1);
    }
  }
  walk('', 0);
  if (at !== data.length) throw new Error('Trailing common table data');
  return entries;
}
