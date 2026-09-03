#!/usr/bin/env python3
"""Normaliza los .glb de pestanas al material que YA funciona (cat eye).

## Problema que resuelve

`assets/modelos/cateye/cateye{left,right}.glb` es el unico modelo que se ve
bien en dispositivo. Comparando los assets, la diferencia no esta en la
geometria ni en `LashStyleConfig` (todos sus presets estan neutralizados e
identicos a DEFAULT), sino en el material:

    modelo        COLOR_0                 baseColorFactor        specular
    cateye        SI (0.029 -> 0.151)     ausente (= blanco)     specularFactor 0.9
    wispy         no                      0.008,0.008,0.010      specularColorFactor 1.2
    catclassic    no                      0.008,0.008,0.010      specularColorFactor 1.2
    foxy          no                      0.008,0.008,0.010      specularColorFactor 1.2
    natural       no                      0.035,0.022,0.016      (ninguna)

El albedo final del cat eye es `blanco x COLOR_0`, o sea un degradado
raiz->punta: esa variacion es lo que se lee como fibras. Los demas tienen un
albedo PLANO de 0.008 (negro casi puro) y encima el especular amplificado a
1.2, asi que se renderizan como una mancha negra brillante en vez de
pestanas. Ademas `RawMesh.withColorFloor` (el knob del motor que aclara la
raiz, ver RendererConfiguration.LASH_COLOR_FLOOR) solo actua sobre COLOR_0 —
en un modelo sin ese atributo no hace nada, y el material que crea gltfio
para un primitive sin COLOR_0 ni lee el color por vertice que
`GlbMeshReader` rellena por defecto.

## Que hace

Deja a los modelos indicados con la MISMA configuracion del cat eye:

1. Inyecta `COLOR_0` (VEC3 float32) con una rampa lineal por canal sobre la
   Y local normalizada. Los extremos son los medidos en cateyeleft.glb por
   ajuste de minimos cuadrados (R2 = 0.93, o sea el degradado del artista es
   lineal en Y): ver ROOT_RGB / TIP_RGB.
2. Pone `baseColorFactor` en blanco, para que el albedo final sea
   `blanco x COLOR_0` igual que en el cat eye (y no el negro plano de 0.008).
3. Iguala `roughnessFactor` y `KHR_materials_specular` a los del cat eye
   (0.42 y specularFactor 0.9), descartando el `specularColorFactor` de 1.2.

Es idempotente: si el modelo ya trae COLOR_0 no lo toca (solo normaliza el
material), asi que se puede correr de nuevo sin acumular atributos.

Uso:
    python tools/glb/inject_lash_vertex_gradient.py            # aplica
    python tools/glb/inject_lash_vertex_gradient.py --dry-run  # solo reporta
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

# Extremos del degradado, medidos en assets/modelos/cateye/cateyeleft.glb
# (ajuste lineal por canal sobre la Y local normalizada, R2 = 0.9310/0.9305/
# 0.9305 para R/G/B). No son valores elegidos a mano: son los del asset que
# ya se confirmo bien en dispositivo.
ROOT_RGB = (0.02855, 0.01708, 0.01138)
TIP_RGB = (0.15133, 0.09593, 0.06554)

# Material del cat eye, para igualar el resto.
CATEYE_ROUGHNESS = 0.42
CATEYE_SPECULAR_FACTOR = 0.9

TARGETS = [
    "assets/modelos/wispy/wispy_left.glb",
    "assets/modelos/wispy/wispy_right.glb",
    "assets/modelos/catclassic/cat_classic_left.glb",
    "assets/modelos/catclassic/cat_classic_right.glb",
    "assets/modelos/foxyeyex/foxy_intense_left.glb",
    "assets/modelos/foxyeyex/foxy_intense_right.glb",
    "assets/modelos/natural/natural_left.glb",
    "assets/modelos/natural/natural_right.glb",
]

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942
COMPONENT_TYPE_FLOAT = 5126
TARGET_ARRAY_BUFFER = 34962


def read_glb(path):
    data = path.read_bytes()
    magic, version, total = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise SystemExit("%s: no es un .glb (magic=%#x)" % (path, magic))
    if version != 2:
        raise SystemExit("%s: version glTF no soportada (%d)" % (path, version))
    offset, gltf, binary = 12, None, None
    while offset < total:
        length, ctype = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8 : offset + 8 + length]
        if ctype == CHUNK_JSON:
            gltf = json.loads(chunk.decode("utf-8"))
        elif ctype == CHUNK_BIN:
            binary = bytearray(chunk)
        offset += 8 + length + (-length % 4)
    if gltf is None or binary is None:
        raise SystemExit("%s: falta el chunk JSON o BIN" % path)
    return gltf, binary


def write_glb(path, gltf, binary):
    # buffer.byteLength es el tamano REAL de los datos; el chunk BIN se
    # rellena aparte hasta multiplo de 4 (la spec permite que el chunk sea
    # hasta 3 bytes mas grande que buffer.byteLength).
    gltf["buffers"][0]["byteLength"] = len(binary)
    gltf["buffers"][0].pop("uri", None)

    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)  # relleno con ESPACIOS
    bin_bytes = bytes(binary) + b"\x00" * (-len(binary) % 4)  # relleno con CEROS

    total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    out = bytearray()
    out += struct.pack("<III", GLB_MAGIC, 2, total)
    out += struct.pack("<II", len(json_bytes), CHUNK_JSON) + json_bytes
    out += struct.pack("<II", len(bin_bytes), CHUNK_BIN) + bin_bytes
    path.write_bytes(bytes(out))


def read_positions_y(gltf, binary, accessor_index):
    accessor = gltf["accessors"][accessor_index]
    view = gltf["bufferViews"][accessor["bufferView"]]
    if accessor["componentType"] != COMPONENT_TYPE_FLOAT or accessor["type"] != "VEC3":
        raise SystemExit("POSITION no es VEC3/float — no soportado por este script")
    stride = view.get("byteStride")
    if stride not in (None, 12):
        raise SystemExit("POSITION con byteStride=%s — no soportado" % stride)
    base = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    count = accessor["count"]
    # Y es la segunda componente de cada VEC3 (offset de 4 bytes).
    return [struct.unpack_from("<f", binary, base + i * 12 + 4)[0] for i in range(count)]


def normalize_material(gltf):
    changes = []
    for material in gltf.get("materials", []):
        pbr = material.setdefault("pbrMetallicRoughness", {})
        if pbr.get("baseColorFactor") != [1.0, 1.0, 1.0, 1.0]:
            changes.append("baseColorFactor %s -> blanco" % (pbr.get("baseColorFactor"),))
            pbr["baseColorFactor"] = [1.0, 1.0, 1.0, 1.0]
        if pbr.get("roughnessFactor") != CATEYE_ROUGHNESS:
            changes.append(
                "roughnessFactor %s -> %s" % (pbr.get("roughnessFactor"), CATEYE_ROUGHNESS)
            )
            pbr["roughnessFactor"] = CATEYE_ROUGHNESS
        specular = material.setdefault("extensions", {}).get("KHR_materials_specular")
        wanted = {"specularFactor": CATEYE_SPECULAR_FACTOR}
        if specular != wanted:
            changes.append("KHR_materials_specular %s -> %s" % (specular, wanted))
            material["extensions"]["KHR_materials_specular"] = dict(wanted)
    used = gltf.setdefault("extensionsUsed", [])
    if "KHR_materials_specular" not in used:
        used.append("KHR_materials_specular")
    return changes


def inject_color(gltf, binary):
    primitive = gltf["meshes"][0]["primitives"][0]
    attributes = primitive["attributes"]
    if "COLOR_0" in attributes:
        return "COLOR_0 ya presente — no se inyecta"

    ys = read_positions_y(gltf, binary, attributes["POSITION"])
    y_min, y_max = min(ys), max(ys)
    span = y_max - y_min
    if span <= 0:
        return "bbox en Y degenerado — no se inyecta"

    payload = bytearray()
    for y in ys:
        t = (y - y_min) / span
        payload += struct.pack(
            "<3f", *(root + (tip - root) * t for root, tip in zip(ROOT_RGB, TIP_RGB))
        )

    # Alineacion a 4 bytes: los accessors de float lo exigen.
    binary += b"\x00" * (-len(binary) % 4)
    byte_offset = len(binary)
    binary += payload

    gltf["bufferViews"].append(
        {
            "buffer": 0,
            "byteOffset": byte_offset,
            "byteLength": len(payload),
            "target": TARGET_ARRAY_BUFFER,
        }
    )
    gltf["accessors"].append(
        {
            "bufferView": len(gltf["bufferViews"]) - 1,
            "componentType": COMPONENT_TYPE_FLOAT,
            "count": len(ys),
            "type": "VEC3",
            "min": [round(min(ROOT_RGB[i], TIP_RGB[i]), 6) for i in range(3)],
            "max": [round(max(ROOT_RGB[i], TIP_RGB[i]), 6) for i in range(3)],
        }
    )
    attributes["COLOR_0"] = len(gltf["accessors"]) - 1
    return "COLOR_0 inyectado: %d vertices, Y local [%.4f,%.4f], rampa %.5f->%.5f (canal R)" % (
        len(ys),
        y_min,
        y_max,
        ROOT_RGB[0],
        TIP_RGB[0],
    )


def main():
    parser = argparse.ArgumentParser(description="Normaliza los .glb de pestanas.")
    parser.add_argument("--dry-run", action="store_true", help="no escribe archivos")
    parser.add_argument("paths", nargs="*", help="glb a normalizar (default: TARGETS)")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    targets = [Path(p) for p in (args.paths or TARGETS)]

    for relative in targets:
        path = relative if relative.is_absolute() else root / relative
        if not path.exists():
            print("!! %s: no existe" % relative)
            continue
        gltf, binary = read_glb(path)
        print("%s" % relative)
        print("   %s" % inject_color(gltf, binary))
        for change in normalize_material(gltf) or ["material ya normalizado"]:
            print("   %s" % change)
        if args.dry_run:
            print("   (dry-run: no se escribio)")
        else:
            write_glb(path, gltf, binary)
            print("   escrito (%d bytes)" % path.stat().st_size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
