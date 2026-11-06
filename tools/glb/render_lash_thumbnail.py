"""Render a carousel thumbnail from an existing GLB, including original assets."""
import argparse
import json
import struct
from pathlib import Path

from generate_mobile_lashes import thumbnail


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    data = args.source.read_bytes()
    json_size = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + json_size])
    binary_start = 28 + json_size
    primitive = doc["meshes"][0]["primitives"][0]

    def values(index, components):
        accessor = doc["accessors"][index]
        view = doc["bufferViews"][accessor["bufferView"]]
        code, size = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}[accessor["componentType"]]
        start = binary_start + view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        stride = view.get("byteStride", size * components)
        return [struct.unpack_from("<" + code * components, data, start + i * stride) for i in range(accessor["count"])]

    mesh = dict(positions=values(primitive["attributes"]["POSITION"], 3), indices=[v[0] for v in values(primitive["indices"], 1)])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    thumbnail(args.output, mesh)


if __name__ == "__main__":
    main()
