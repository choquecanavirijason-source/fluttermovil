import json
import pathlib
import struct
import sys

repo = pathlib.Path(__file__).resolve().parents[2]
out = pathlib.Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for path in (repo / 'assets/modelos').rglob('*.glb'):
    data = path.read_bytes()
    json_size = struct.unpack_from('<I', data, 12)[0]
    doc = json.loads(data[20:20 + json_size])
    primitive = doc['meshes'][0]['primitives'][0]
    accessor = doc['accessors'][primitive['attributes']['POSITION']]
    view = doc['bufferViews'][accessor['bufferView']]
    offset = 28 + json_size + view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    stride = view.get('byteStride', 12)
    positions = [struct.unpack_from('<fff', data, offset + i * stride) for i in range(accessor['count'])]
    target = out / (path.parent.name + '_' + path.stem + '.bin')
    target.write_bytes(b''.join(struct.pack('<fff', *p) for p in positions))
print('Extracted GLB position fixtures')
