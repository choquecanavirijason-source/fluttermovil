"""Structural/geometry checks for staged mobile GLBs and Kotlin XYZ fixtures."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


def read(path):
    data = path.read_bytes()
    magic, version, size = struct.unpack_from("<III", data)
    assert (magic, version, size) == (0x46546C67, 2, len(data)), path
    offset = 12
    doc = binary = None
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8:offset + 8 + length]
        assert length % 4 == 0 and len(chunk) == length
        if kind == 0x4E4F534A:
            doc = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
        offset += 8 + length
    assert doc and binary is not None
    assert len(doc["meshes"]) == 1 and len(doc["meshes"][0]["primitives"]) == 1
    assert len(doc["nodes"]) == 1 and not any(k in doc["nodes"][0] for k in ("matrix", "scale", "rotation", "translation"))
    primitive = doc["meshes"][0]["primitives"][0]
    assert primitive.get("mode", 4) == 4

    def values(index):
        accessor = doc["accessors"][index]
        view = doc["bufferViews"][accessor["bufferView"]]
        count = dict(SCALAR=1, VEC2=2, VEC3=3, VEC4=4)[accessor["type"]]
        code, width = {5126: ("f", 4), 5123: ("H", 2)}[accessor["componentType"]]
        stride = view.get("byteStride", count * width)
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        assert start + (accessor["count"] - 1) * stride + count * width <= len(binary)
        return [struct.unpack_from("<" + code * count, binary, start + i * stride) for i in range(accessor["count"])]

    attrs = {name: values(index) for name, index in primitive["attributes"].items()}
    positions, normals = attrs["POSITION"], attrs["NORMAL"]
    indices = [row[0] for row in values(primitive["indices"])]
    assert 0 < len(positions) < 10_000
    assert all(len(rows) == len(positions) for rows in attrs.values())
    assert all(math.isfinite(v) for rows in attrs.values() for row in rows for v in row)
    assert min(p[1] for p in positions) == 0.0, "Attachment row must be Y=0"
    assert max(p[1] for p in positions) > .2
    assert all(abs(sum(v * v for v in n) - 1) < .00001 for n in normals)
    assert len(indices) % 3 == 0 and max(indices) < len(positions) and min(indices) >= 0
    assert all(0 <= v <= 1 for color in attrs["COLOR_0"] for v in color)
    for i in range(0, len(indices), 3):
        a, b, c = [positions[indices[i + j]] for j in range(3)]
        u, v = [b[k] - a[k] for k in range(3)], [c[k] - a[k] for k in range(3)]
        cross = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
        assert sum(x*x for x in cross) > 1e-22, (path, "Degenerate triangle", i // 3)
    assert not doc.get("images") and not doc.get("textures")
    return doc, positions, indices


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument("--expected-pairs", type=int, default=5)
    args = parser.parse_args()
    args.fixtures.mkdir(parents=True, exist_ok=True)
    report, pairs = [], {}
    paths = sorted(args.models.rglob("*.glb"))
    assert len(paths) == args.expected_pairs * 2
    for path in paths:
        doc, positions, indices = read(path)
        style, eye = doc["extras"]["style"], doc["extras"]["eye"]
        pairs.setdefault(style, {})[eye] = positions
        target = args.fixtures / (path.parent.name + "_" + path.stem + ".bin")
        target.write_bytes(b"".join(struct.pack("<fff", *p) for p in positions))
        report.append(dict(file=str(path.relative_to(args.models)), vertices=len(positions), triangles=len(indices)//3,
                           bytes=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    assert len(pairs) == args.expected_pairs
    for style, eyes in pairs.items():
        assert len(eyes["left"]) == len(eyes["right"])
        for a, b in zip(eyes["left"], eyes["right"]):
            assert a[0] == -b[0] and a[1:] == b[1:], (style, "Eye pair is not mirrored")
    (args.models / "validation.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"PASS: {len(paths)} GLBs, one mesh/primitive, indexed triangles, finite normalized normals, no degenerate triangles, Y=0 roots, mirrored pairs, no texture dependencies. Total {sum(r['vertices'] for r in report):,} vertices.")


if __name__ == "__main__":
    main()
