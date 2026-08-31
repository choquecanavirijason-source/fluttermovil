package com.example.test_face.render

import dev.romainguy.kotlin.math.Float2
import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.geometries.Geometry

/**
 * Ribbon PLACEHOLDER de delineado — franja delgada procedural, sin `.glb`
 * (ver plan Fase 4: no hay todavía ningún asset de arte para delineado,
 * a diferencia de las 5 mallas de pestañas que existían desde el día 1).
 *
 * Genera un [RawMesh] con el MISMO contrato que produce
 * [GlbMeshReader.read] desde un archivo — [LinerRenderer] no distingue el
 * origen, así que el día que exista un `.glb` real de delineado, cambiar
 * esa llamada por [GlbMeshReader.read] es lo único que hace falta.
 *
 * Topología: [SEGMENTS]+1 columnas × 2 filas (borde inferior/superior de la
 * franja) en el plano XY local, Z=0 (sin volumen — es una línea, no un
 * abanico como las pestañas). [LashMeshBender] solo necesita vértices
 * distribuidos a lo largo de X para poder aplicar la curva del párpado; no
 * le importa si el mesh vino de un archivo o se generó en código.
 */
object LinerRibbonMesh {

    private const val SEGMENTS = 16
    private const val HALF_WIDTH = 0.5f
    private const val HALF_THICKNESS = 0.03f

    fun build(): RawMesh {
        val columns = SEGMENTS + 1
        val vertices = ArrayList<Geometry.Vertex>(columns * 2)
        val indices = ArrayList<Int>(SEGMENTS * 6)
        val normal = Float3(0f, 0f, 1f)

        for (col in 0 until columns) {
            val t = col.toFloat() / SEGMENTS
            val x = -HALF_WIDTH + t * (2f * HALF_WIDTH)
            // Fila inferior (par) y superior (impar) de cada columna —
            // mismo orden que asume bendInPlace más abajo al triangular.
            vertices.add(Geometry.Vertex(Float3(x, -HALF_THICKNESS, 0f), normal, Float2(t, 0f)))
            vertices.add(Geometry.Vertex(Float3(x, HALF_THICKNESS, 0f), normal, Float2(t, 1f)))
        }

        for (col in 0 until SEGMENTS) {
            val bl = col * 2
            val tl = bl + 1
            val br = bl + 2
            val tr = bl + 3
            indices.add(bl); indices.add(br); indices.add(tl)
            indices.add(tl); indices.add(br); indices.add(tr)
        }

        return RawMesh(
            vertices = vertices,
            indices = indices,
            minX = -HALF_WIDTH,
            maxX = HALF_WIDTH,
            minY = -HALF_THICKNESS,
        )
    }
}
