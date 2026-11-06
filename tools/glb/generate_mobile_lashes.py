"""Deterministic, texture-free mobile eyelash GLBs matching the current reader.

One mesh/primitive per eye, identity node, +Y fibers, flat Y=0 attachment
row and sampled curved root Z. Crossed tapered ribbons retain thickness
from oblique views without dense tubes. Writes a staging directory only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import struct

STYLES = {
    "cateye": dict(name="Cat Eye", folder="cateye", left="cateyeleft", right="cateyeright", count=72, width=.010, curl=.58, fan=9, sweep=20, seed=1101),
    "wispy": dict(name="Wispy", folder="wispy", left="wispy_left", right="wispy_right", count=70, width=.0085, curl=.65, fan=15, sweep=6, seed=2202),
    "catclassic": dict(name="Cat Classic", folder="catclassic", left="cat_classic_left", right="cat_classic_right", count=80, width=.0095, curl=.55, fan=9, sweep=12, seed=3303),
    "foxyeye": dict(name="Foxy Eye", folder="foxyeyex", left="foxy_intense_left", right="foxy_intense_right", count=78, width=.009, curl=.38, fan=7, sweep=32, seed=4404),
    "natural": dict(name="Natural", folder="natural", left="natural_left", right="natural_right", count=58, width=.0075, curl=.48, fan=10, sweep=3, seed=5505),
    "dolleye": dict(name="Doll Eye", folder="dolleye", left="doll_eye_left", right="doll_eye_right", count=72, width=.009, curl=.72, fan=13, sweep=0, seed=6606),
    "squirrel": dict(name="Squirrel", folder="squirrel", left="squirrel_left", right="squirrel_right", count=70, width=.009, curl=.62, fan=10, sweep=10, seed=7707),
    "kitten": dict(name="Kitten", folder="kitten", left="kitten_left", right="kitten_right", count=62, width=.008, curl=.54, fan=8, sweep=14, seed=8808),
    "wetlook": dict(name="Wet Look", folder="wetlook", left="wet_look_left", right="wet_look_right", count=36, width=.011, curl=.52, fan=8, sweep=8, seed=9909),
    "anime": dict(name="Anime", folder="anime", left="anime_left", right="anime_right", count=24, width=.011, curl=.64, fan=15, sweep=2, seed=10110),
    "kimk": dict(name="Kim K", folder="kimk", left="kim_k_left", right="kim_k_right", count=68, width=.009, curl=.61, fan=12, sweep=12, seed=11111),
}
SEGMENTS = 9


def root_z(x):
    return -.12 - .18 * (x / 1.5) ** 2


def smooth(t):
    t = max(0., min(1., t))
    return t * t * (3 - 2 * t)


def length_at(style, t):
    # t=0 inner/short; t=1 outer. Assets, not the pose, define each design.
    if style == "natural":
        return .24 + .20 * math.sin(math.pi * t) ** .8 + .025 * t
    if style == "catclassic":
        return .30 + .27 * smooth(t / .85) - .045 * smooth((t - .9) / .1)
    if style == "cateye":
        return .26 + .40 * smooth(t / .88) - .06 * smooth((t - .94) / .06)
    if style == "foxyeye":
        return .24 + .47 * smooth(t) - .025 * smooth((t - .97) / .03)
    if style == "dolleye":
        return .23 + .43 * math.sin(math.pi * t) ** .9
    if style == "squirrel":
        return .24 + .42 * smooth(t / .72) - .30 * smooth((t - .72) / .28)
    if style == "kitten":
        return .23 + .29 * smooth(t / .80) - .09 * smooth((t - .88) / .12)
    if style == "wetlook":
        return .25 + .28 * math.sin(math.pi * t) ** .8 + .035 * t
    if style == "anime":
        return .21 + .18 * math.sin(math.pi * t) ** .8
    if style == "kimk":
        return .27 + .23 * math.sin(math.pi * t) ** .8 + .07 * t
    return .29 + .24 * math.sin(math.pi * min(t, .92)) ** .8 + .045 * t


def make_mesh(style, eye, width_multiplier=1.0):
    spec = dict(STYLES[style])
    spec["width"] *= width_multiplier
    rng = random.Random(spec["seed"])
    positions, colors, uvs, indices = [], [], [], []
    fibers = []

    def add_fiber(t, length, width, angle, curl):
        x = (0.5 - t) * 3.0  # LEFT: temporal corner is negative X.
        z = root_z(x)
        theta = math.radians(angle)
        lateral_curve = rng.uniform(-.032, .032)
        for crossed in (False, True):
            start = len(positions)
            for j in range(SEGMENTS + 1):
                s = j / SEGMENTS
                # Soft S curl; all root vertices are exactly on Y=0.
                cx = x + math.sin(theta) * length * s ** 1.12 + lateral_curve * length * math.sin(math.pi * s)
                cy = math.cos(theta) * length * s
                cz = z + curl * length * (1.15 * s * s - .15 * s ** 3)
                half = width * .5 * ((1 - s) ** 1.2 + .025)
                g = .045 + .12 * s ** .7
                for side in (-1, 1):
                    positions.append((cx + (0 if crossed else side * half), cy, cz + (side * half * .65 if crossed else 0)))
                    colors.append((g, g, g, 1.0))
                    uvs.append((s, (side + 1) / 2))
            for j in range(SEGMENTS):
                a = start + j * 2
                indices.extend((a, a + 1, a + 2, a + 1, a + 3, a + 2))
        fibers.append(dict(t=round(t, 6), length=round(length, 6), angle=round(angle, 3)))

    count = spec["count"]
    for i in range(count):
        t = i / (count - 1)
        if 0 < i < count - 1:
            t += rng.uniform(-.38, .38) / count
        base = length_at(style, t) * rng.uniform(.86 if style == "natural" else .90, 1.10)
        # Positive angle points inward in a LEFT model; outer sweep is negative.
        angle = (0.5 - t) * spec["fan"] - spec["sweep"] * smooth((t - .35) / .65) + rng.uniform(-5, 5)
        add_fiber(t, base, spec["width"] * rng.uniform(.90, 1.08), angle, spec["curl"])
        if style not in ("natural", "wetlook", "anime") and i % 2 == 0:
            # Fine secondary fiber, not an opaque sheet or duplicated tube.
            tt = max(0., min(1., t + .0035))
            add_fiber(tt, base * rng.uniform(.78, .91), spec["width"] * .68, angle + rng.uniform(-4, 4), spec["curl"] * 1.05)
        if style == "wispy" and i % 4 == 2:
            # Separated long spikes interleave with softer short fans.
            add_fiber(t, base * 1.42, spec["width"] * .80, angle + rng.uniform(-2, 2), spec["curl"] * .94)
            add_fiber(max(0., t - .006), base * .78, spec["width"] * .67, angle + 5, spec["curl"])
            add_fiber(min(1., t + .006), base * .82, spec["width"] * .67, angle - 5, spec["curl"])
        if style == "wetlook":
            # Narrow closed fans form distinct mascara-like groups.
            add_fiber(max(0., t - .0035), base * .94, spec["width"] * .82, angle - .8, spec["curl"])
            add_fiber(min(1., t + .0035), base * .98, spec["width"] * .82, angle + .8, spec["curl"])
        if style == "anime":
            # Large, separated spikes and a short supporting fringe.
            add_fiber(max(0., t - .009), base * .77, spec["width"] * .72, angle + 7, spec["curl"])
            add_fiber(min(1., t + .009), base * .82, spec["width"] * .72, angle - 7, spec["curl"])
            if i % 2 == 0:
                add_fiber(t, base * 1.90, spec["width"] * 1.15, angle, spec["curl"] * .92)
        if style == "kimk" and i % 5 == 2:
            add_fiber(t, base * 1.60, spec["width"] * .95, angle, spec["curl"] * .93)
            add_fiber(max(0., t - .004), base * 1.30, spec["width"] * .65, angle + 2, spec["curl"])

    # Subpixel attachment rail. Its bottom edge is the exact Y=0 root row.
    start = len(positions)
    for i in range(97):
        x = -1.5 + 3 * i / 96
        for y in (0., .0045):
            positions.append((x, y, root_z(x)))
            colors.append((.045, .045, .045, 1.0))
            uvs.append((i / 96, y / .0045))
    for i in range(96):
        a = start + i * 2
        indices.extend((a, a + 1, a + 2, a + 1, a + 3, a + 2))

    if eye == "right":
        positions = [(-x, y, z) for x, y, z in positions]
        indices = [v for i in range(0, len(indices), 3) for v in (indices[i], indices[i + 2], indices[i + 1])]

    normals = [[0., 0., 0.] for _ in positions]
    for i in range(0, len(indices), 3):
        a, b, c = [positions[indices[i + k]] for k in range(3)]
        u = [b[k] - a[k] for k in range(3)]
        v = [c[k] - a[k] for k in range(3)]
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        for idx in indices[i:i + 3]:
            for k in range(3):
                normals[idx][k] += n[k]
    normals = [tuple(v / math.sqrt(sum(w * w for w in n)) for v in n) for n in normals]
    return dict(positions=positions, normals=normals, colors=colors, uvs=uvs, indices=indices, fibers=fibers)


def write_glb(path, mesh, style, eye):
    binary = bytearray()
    views, accessors = [], []

    def attribute(values, components, kind, component_type=5126, target=34962, bounds=False):
        while len(binary) % 4:
            binary.append(0)
        offset = len(binary)
        code = "f" if component_type == 5126 else "H"
        flat = [v for row in values for v in row] if components > 1 else values
        binary.extend(struct.pack("<" + code * len(flat), *flat))
        views.append(dict(buffer=0, byteOffset=offset, byteLength=len(binary) - offset, target=target))
        accessor = dict(bufferView=len(views) - 1, componentType=component_type, count=len(values), type=kind)
        if bounds:
            accessor["min"] = [min(p[k] for p in values) for k in range(components)]
            accessor["max"] = [max(p[k] for p in values) for k in range(components)]
        accessors.append(accessor)
        return len(accessors) - 1

    attrs = dict(POSITION=attribute(mesh["positions"], 3, "VEC3", bounds=True),
                 NORMAL=attribute(mesh["normals"], 3, "VEC3"),
                 TEXCOORD_0=attribute(mesh["uvs"], 2, "VEC2"),
                 COLOR_0=attribute(mesh["colors"], 4, "VEC4"))
    index = attribute(mesh["indices"], 1, "SCALAR", 5123, 34963)
    doc = dict(asset=dict(version="2.0", generator="elashes mobile lashes v1"), scene=0,
               scenes=[dict(nodes=[0])], nodes=[dict(mesh=0, name=f"{style}_{eye}")],
               meshes=[dict(primitives=[dict(attributes=attrs, indices=index, material=0, mode=4)])],
               materials=[dict(name="NeutralLashFiber", doubleSided=True, alphaMode="OPAQUE",
                               pbrMetallicRoughness=dict(baseColorFactor=[1, 1, 1, 1], metallicFactor=0, roughnessFactor=.82))],
               buffers=[dict(byteLength=len(binary))], bufferViews=views, accessors=accessors,
               extras=dict(style=style, eye=eye, version=1, rootAxis="Y=0", rootSpan=3.0,
                           fibers=len(mesh["fibers"]), segments=SEGMENTS, texturesRequired=False))
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    data = struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(binary), 0x004E4942) + binary
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return dict(path=str(path), style=style, eye=eye, vertices=len(mesh["positions"]), triangles=len(mesh["indices"]) // 3,
                fibers=len(mesh["fibers"]), bytes=len(data), sha256=hashlib.sha256(data).hexdigest())


def preview_sheet(path, meshes):
    from PIL import Image, ImageDraw, ImageFont
    import numpy as np
    scale = 3
    width, height = 1520, 180 + 230 * len(meshes)
    image = Image.new("RGB", (width * scale, height * scale), (245, 243, 239))
    draw = ImageDraw.Draw(image)
    font_path = "C:/Windows/Fonts/segoeui.ttf"
    font = ImageFont.truetype(font_path, 23 * scale)
    small = ImageFont.truetype(font_path, 17 * scale)
    title = ImageFont.truetype(font_path, 28 * scale)
    draw.text((35 * scale, 20 * scale), "Pestañas ligeras · geometría real v1", font=title, fill=(25, 33, 39))
    for col, text in enumerate(("Abiertas · referencia", "Cerradas · referencia", "Vista oblicua")):
        draw.text(((205 + 435 * col) * scale, 80 * scale), text, font=small, fill=(75, 83, 86))
    for row, (style, mesh) in enumerate(meshes.items()):
        spec = STYLES[style]
        top = 135 + row * 230
        draw.text((30 * scale, (top + 55) * scale), spec["name"], font=font, fill=(23, 41, 44))
        draw.text((30 * scale, (top + 91) * scale), f'{len(mesh["positions"]):,} vértices', font=small, fill=(87, 99, 100))
        src = np.array(mesh["positions"], dtype=float)
        indices = np.array(mesh["indices"]).reshape(-1, 3)
        for col in range(3):
            points = src.copy()
            x = src[:, 0]
            base_z = -.12 - .18 * (x / 1.5) ** 2
            dy = src[:, 1] * 1.55
            dz = src[:, 2] - base_z
            closed = col == 1
            theta = math.radians(150 if closed else 0)
            contour = (-.05 if closed else .25) * (1 - (x / 1.5) ** 2)
            points[:, 1] = contour + math.cos(theta) * dy - math.sin(theta) * dz
            points[:, 2] = math.sin(theta) * dy + math.cos(theta) * dz
            if col == 2:
                yaw = math.radians(32)
                a, z = points[:, 0].copy(), points[:, 2].copy()
                points[:, 0] = a * math.cos(yaw) + z * math.sin(yaw)
                points[:, 2] = -a * math.sin(yaw) + z * math.cos(yaw)
            cx, cy = 410 + col * 435, top + (80 if closed else 140)
            pixels = points[:, :2] * np.array([110, -110]) + np.array([cx, cy])
            order = np.argsort(points[indices, 2].mean(axis=1))
            for tri in indices[order]:
                polygon = [tuple(p * scale) for p in pixels[tri]]
                draw.polygon(polygon, fill=(25, 24, 25))
            # Green attachment reference is intentionally visible for inspection.
            if col < 2:
                line = []
                for n in range(65):
                    xx = -1.5 + n * 3 / 64
                    yy = (-.05 if closed else .25) * (1 - (xx / 1.5) ** 2)
                    line.append(((cx + xx * 110) * scale, (cy - yy * 110) * scale))
                draw.line(line, fill=(18, 137, 102), width=scale)
    draw.text((30 * scale, (height - 50) * scale), "Vistas calculadas de las mallas; el encaje final se comprueba en el probador.", font=small, fill=(87, 99, 100))
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((width, height), Image.Resampling.LANCZOS).save(path)


def thumbnail(path, mesh):
    """Transparent carousel silhouette rendered from the actual mesh."""
    from PIL import Image, ImageDraw
    import numpy as np
    points = np.array(mesh["positions"], dtype=float)
    points[:, 1] = points[:, 1] * 1.55 + .25 * (1 - (points[:, 0] / 1.5) ** 2)
    xy = points[:, :2]
    lo, hi = xy.min(axis=0), xy.max(axis=0)
    factor = min(136 / (hi[0] - lo[0]), 112 / (hi[1] - lo[1]))
    xy = (xy - (lo + hi) / 2) * np.array([factor, -factor]) + np.array([80, 80])
    image = Image.new("RGBA", (640, 640))
    draw = ImageDraw.Draw(image)
    indices = np.array(mesh["indices"]).reshape(-1, 3)
    for tri in indices:
        draw.polygon([tuple(p * 4) for p in xy[tri]], fill=(15, 15, 17, 255))
    image.resize((160, 160), Image.Resampling.LANCZOS).save(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--preview", type=Path)
    parser.add_argument("--styles", nargs="+", choices=STYLES)
    parser.add_argument("--thumbnails", action="store_true")
    parser.add_argument("--width-multiplier", type=float, default=1.0)
    args = parser.parse_args()
    if not 0.25 <= args.width_multiplier <= 5:
        parser.error("--width-multiplier must be between 0.25 and 5")
    report, meshes = [], {}
    for style, spec in STYLES.items():
        if args.styles and style not in args.styles:
            continue
        for eye in ("left", "right"):
            mesh = make_mesh(style, eye, args.width_multiplier)
            path = args.out / spec["folder"] / (spec[eye] + ".glb")
            report.append(write_glb(path, mesh, style, eye))
            if eye == "left":
                meshes[style] = mesh
                if args.thumbnails:
                    thumbnail(args.out / spec["folder"] / "preview.png", mesh)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if args.preview:
        preview_sheet(args.preview, meshes)
    print(json.dumps([{k: r[k] for k in ("style", "eye", "vertices", "triangles", "bytes")} for r in report], indent=2))


if __name__ == "__main__":
    main()
