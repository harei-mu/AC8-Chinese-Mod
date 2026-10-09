"""Extract managed asset-reader dependencies from the pinned toolkit, offline.

Bundle layout: dotnet/runtime Microsoft.NET.HostModel/Bundle/{Bundler,Manifest,FileEntry}.cs.
Only the fixed, already-downloaded development tool is accepted; no game writes.
"""
import hashlib
import io
import json
import struct
import zlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = root / 'tools/ac8-override-toolkit/AC8OverrideToolkit.exe'
blob = source.read_bytes()
assert hashlib.sha256(blob).hexdigest() == '2a5677032f31fa4437f3ad401007a42c2d9ac070faab5628610a3b715df466ff'
signature = bytes.fromhex('8b1202b96a612038727b930214d7a03213f5b9e6efae3318ee3b2dce24b36aae')
position = blob.index(signature)
offset, = struct.unpack_from('<q', blob, position - 8)
stream = io.BytesIO(blob)
stream.seek(offset)

def unpack(fmt):
    return struct.unpack(fmt, stream.read(struct.calcsize(fmt)))

def string():
    length, shift = 0, 0
    while True:
        value = stream.read(1)[0]
        length |= (value & 127) << shift
        if not value & 128:
            break
        shift += 7
        assert shift <= 28
    return stream.read(length).decode('utf-8')

major, minor, count = unpack('<IIi')
assert major == 6 and minor == 0 and 0 < count < 2000
bundle_id = string()
stream.read(40)
entries = []
destination = root / 'tools/asset-api'
destination.mkdir(parents=True, exist_ok=True)
for _ in range(count):
    start, size, compressed_size, kind = unpack('<qqqB')
    name = string()
    assert start >= 0 and size > 0 and start + (compressed_size or size) <= len(blob)
    entries.append({'name': name, 'size': size, 'compressedSize': compressed_size, 'type': kind})
    if name.endswith('.dll') and not name.startswith(('System.', 'Microsoft.')) and kind == 1:
        assert '/' not in name and '\\' not in name
        data = blob[start:start + (compressed_size or size)]
        if compressed_size:
            data = zlib.decompress(data, -15)
        assert len(data) == size and data[:2] == b'MZ'
        (destination / name).write_bytes(data)
(root / 'work/asset-api-bundle.json').write_text(json.dumps(entries, indent=2), encoding='utf-8')
print(json.dumps({'bundleVersion': major, 'files': count, 'extracted': [p.name for p in destination.glob('*.dll')]}))
