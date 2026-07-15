"""Generador procedural de pestañas AR — hair cards, no geometría sólida.

CÓMO CORRER
    1. Abrir Blender (4.x) -> pestaña "Scripting".
    2. Cargar este archivo, ajustar los parámetros en LashDesignParams al
       final del archivo (o duplicar un preset) y ejecutar (Alt+P / Run).
    3. Asignar la textura de fibra real al nodo "FIBER_ATLAS" del material
       generado (Shading tab) — el script deja el slot listo pero no puede
       generar la textura en sí, eso es trabajo de arte.
    4. Los 3 objetos (`lash_inner`/`lash_center`/`lash_outer`) quedan
       parented a un Empty `<nombre>_root` — exportar seleccionando ese
       Empty y su jerarquía.

QUÉ RESUELVE (ver auditoría del motor de render, sección GLB/Blender)
    Los .glb actuales (`assets/modelos/**/*.glb`) están modelados como
    geometría SÓLIDA de cada pestaña individual: 21 000-143 000 triángulos
    por ojo, sin textura, sin tangentes, sin huesos, un único mesh/nodo. Ese
    enfoque es exactamente lo opuesto a como se renderiza pelo/pestañas en
    tiempo real en cualquier motor de producción (TikTok/Snapchat incluidos):
    tarjetas planas con textura alfa-recortada ("hair cards"), un orden de
    magnitud más baratas y con tangentes reales para shading anisotrópico.

    Este generador reemplaza esa técnica: por diseño, cada pestaña es una
    tira de pocos triángulos (no un tubo sólido), y el resultado se separa en
    3 sub-mallas (interna/centro/externa) bajo un nodo raíz común — necesario
    para que Kotlin (LashRenderer/EyelidCurveFitter, ver plan de motor) pueda
    orientar cada tercio siguiendo la curva real del párpado en vez de mover
    todo el ojo como un único cuerpo rígido.

LIMITACIÓN HONESTA
    Este script no se pudo ejecutar ni verificar visualmente en Blender real
    desde este entorno (no hay Blender instalado aquí) — su API (`bpy`,
    `bmesh`, `export_scene.gltf`) es estable y está usada de forma estándar,
    pero el resultado visual (curvatura, densidad, densidad de "wispy" vs.
    "volumen") necesita iteración de un artista en Blender antes de
    reemplazar los .glb actuales en `assets/modelos/`.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass, field

import bpy
import bmesh
from mathutils import Vector


@dataclass
class LashDesignParams:
    """Un preset = un diseño (`classic`, `volumen`, `wispy`, `cat eye`, ...)."""

    name: str = "natural"
    eye: str = "left"  # "left" | "right" — controla el espejado en X.

    num_lashes: int = 48
    """Cuántas tiras individuales a lo largo de la línea del párpado."""

    base_length: float = 0.9
    """Largo de cada pestaña en unidades locales (antes de variación aleatoria)."""

    length_variation: float = 0.25
    """Variación aleatoria de largo, como fracción de base_length (0-1)."""

    base_width: float = 0.035
    """Ancho de la base de cada tira (se afina hacia la punta, ver taper)."""

    taper: float = 0.15
    """Ancho de la punta como fracción del ancho de la base (0 = punta en cero)."""

    curl_strength: float = 0.55
    """Cuánto se curva cada pestaña hacia arriba (0 = recta, 1 = muy curva)."""

    spread_degrees: float = 12.0
    """Variación angular aleatoria por pestaña, en grados — evita el look
    "peine perfecto" y da la irregularidad natural de una pestaña real."""

    eyelid_arc_span: float = 1.6
    """Ancho total (X) de la línea del párpado sobre la que se distribuyen
    las raíces de las pestañas, en unidades locales."""

    eyelid_arc_curve: float = 0.28
    """Altura del arco del párpado (curvatura de la línea de raíces)."""

    segments_per_lash: int = 4
    """Segmentos a lo largo de cada tira — 3-5 es suficiente para una curva
    suave sin acercarse a la densidad de la geometría sólida que se reemplaza."""

    seed: int = 0


def _eyelid_root_point(t: float, p: LashDesignParams) -> Vector:
    """t en [0,1] a lo largo del párpado -> punto 3D de la raíz de una pestaña.

    Arco simple (parábola), suficiente para distribuir raíces — la curva
    REAL del párpado la calcula MediaPipe en runtime (ver EyelidCurveFitter
    en el plan de motor); esto es solo la geometría base del asset.
    """
    x = (t - 0.5) * p.eyelid_arc_span
    y = p.eyelid_arc_curve * (1.0 - (2.0 * t - 1.0) ** 2)
    return Vector((x, y, 0.0))


def _build_single_lash(
    root: Vector,
    direction_deg: float,
    length: float,
    base_width: float,
    p: LashDesignParams,
) -> tuple[list[Vector], list[Vector], list[tuple[int, int, int, int]], list[tuple[float, float]]]:
    """Genera una tira curva individual: lista de vértices (2 por segmento,
    izquierda/derecha de la tira), caras (quads) y UVs a lo largo de [0,1]
    en U (largo) y [0,1] en V (ancho) — el rango U completo se remapea luego
    al atlas compartido de fibra.
    """
    verts: list[Vector] = []
    uvs: list[tuple[float, float]] = []
    n = p.segments_per_lash
    angle_rad = math.radians(direction_deg)
    tangent = Vector((math.sin(angle_rad), math.cos(angle_rad), 0.0))
    normal_side = Vector((math.cos(angle_rad), -math.sin(angle_rad), 0.0))

    for i in range(n + 1):
        s = i / n  # 0 = raíz, 1 = punta
        # Curvatura: la tira sube en Z a medida que avanza (curl_strength) —
        # una curva de Bézier cuadrática simple es suficiente para una tira.
        curl_z = p.curl_strength * length * (s * s)
        along = tangent * (length * s)
        center = root + along + Vector((0.0, 0.0, curl_z))

        width = base_width * (1.0 - s * (1.0 - p.taper))
        verts.append(center - normal_side * (width * 0.5))
        verts.append(center + normal_side * (width * 0.5))
        uvs.append((s, 0.0))
        uvs.append((s, 1.0))

    faces: list[tuple[int, int, int, int]] = []
    for i in range(n):
        a = i * 2
        b = i * 2 + 1
        c = i * 2 + 3
        d = i * 2 + 2
        faces.append((a, b, c, d))

    return verts, [], faces, uvs


def _build_lash_group(
    group_name: str,
    t_range: tuple[float, float],
    p: LashDesignParams,
    rng: random.Random,
) -> bpy.types.Object:
    """Construye UNA de las 3 sub-mallas (inner/center/outer) uniendo todas
    las tiras individuales cuya raíz cae en `t_range` (fracción [0,1] a lo
    largo del párpado)."""
    mesh = bpy.data.meshes.new(group_name)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    t0, t1 = t_range
    lashes_in_group = max(1, round(p.num_lashes * (t1 - t0)))

    for k in range(lashes_in_group):
        t = t0 + (t1 - t0) * ((k + 0.5) / lashes_in_group)
        root = _eyelid_root_point(t, p)

        length = p.base_length * (1.0 + rng.uniform(-p.length_variation, p.length_variation))
        width = p.base_width * (1.0 + rng.uniform(-0.15, 0.15))
        direction = rng.uniform(-p.spread_degrees, p.spread_degrees)

        verts, _, faces, uvs = _build_single_lash(root, direction, length, width, p)
        bm_verts = [bm.verts.new(v) for v in verts]
        bm.verts.ensure_lookup_table()
        for face_idx, (a, b, c, d) in enumerate(faces):
            face = bm.faces.new((bm_verts[a], bm_verts[b], bm_verts[c], bm_verts[d]))
            face.smooth = True
            for loop, uv_idx in zip(face.loops, (a, b, c, d)):
                loop[uv_layer].uv = uvs[uv_idx]

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj = bpy.data.objects.new(group_name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _build_fiber_material(name: str) -> bpy.types.Material:
    """Material PBR compartido entre TODOS los diseños — solo cambia la
    geometría/curva por diseño, no el material (ver auditoría: escalable a
    "cualquier diseño futuro" sin reinventar el shading cada vez).

    Deja un nodo Image Texture llamado "FIBER_ATLAS" sin imagen asignada —
    ahí va la textura alfa-recortada de fibra que el artista debe pintar/
    generar (fuera del alcance de este script: es trabajo de arte 2D, no de
    geometría procedural).
    """
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.blend_method = "HASHED"  # alpha cutout — clave para hair cards.
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.3
    tex = nodes.new("ShaderNodeTexImage")
    tex.name = "FIBER_ATLAS"
    tex.label = "FIBER_ATLAS (asignar textura de fibra acá)"

    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return mat


def generate(p: LashDesignParams) -> bpy.types.Object:
    rng = random.Random(p.seed)
    mirror_x = -1.0 if p.eye == "right" else 1.0

    root_name = f"{p.name}_{p.eye}_root"
    root_empty = bpy.data.objects.new(root_name, None)
    bpy.context.collection.objects.link(root_empty)

    material = _build_fiber_material(f"LashFiber_{p.name}")

    groups = {
        "inner": (0.0, 1 / 3),
        "center": (1 / 3, 2 / 3),
        "outer": (2 / 3, 1.0),
    }
    for group_name, t_range in groups.items():
        obj = _build_lash_group(f"{p.name}_{p.eye}_{group_name}", t_range, p, rng)
        obj.scale.x = mirror_x
        obj.data.materials.append(material)
        obj.parent = root_empty

    return root_empty


def export_gltf(root_empty: bpy.types.Object, output_path: str) -> None:
    """Exporta la jerarquía completa (root + 3 sub-mallas) con TANGENTES —
    sin esto, el material anisotrópico de pelo (ver Fase 4 del plan de
    motor) es imposible de aplicar, es el prerrequisito de datos que
    faltaba en los .glb actuales."""
    bpy.ops.object.select_all(action="DESELECT")
    root_empty.select_set(True)
    for child in root_empty.children:
        child.select_set(True)

    bpy.ops.export_scene.gltf(
        filepath=output_path,
        use_selection=True,
        export_format="GLB",
        export_tangents=True,
        export_normals=True,
        export_texcoords=True,
        export_materials="EXPORT",
        export_apply=True,
    )


if __name__ == "__main__":
    # ── Presets de ejemplo — duplicar/ajustar por diseño ────────────────────
    presets = [
        LashDesignParams(name="classic", eye="left", curl_strength=0.4, spread_degrees=6, num_lashes=40),
        LashDesignParams(name="wispy", eye="left", curl_strength=0.7, spread_degrees=22, num_lashes=30, length_variation=0.4),
        LashDesignParams(name="catEye", eye="left", curl_strength=0.6, eyelid_arc_curve=0.22, base_length=1.1),
    ]

    for preset in presets:
        root = generate(preset)
        export_gltf(root, f"//export/{preset.name}_{preset.eye}.glb")
