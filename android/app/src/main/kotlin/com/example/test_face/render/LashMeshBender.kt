package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.geometries.Geometry
import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Deforma [RawMesh.vertices] para que la pestaña siga la curva real del
 * párpado ([LashLineCurve]) en vez de mantener su forma genérica de
 * fábrica. Se aplica en espacio LOCAL del mesh, ANTES del transform rígido
 * (posición/rotación/escala) que ya calcula [EyeTransformCalculator] — por
 * eso solo hace falta la curvatura ADICIONAL respecto a la inclinación
 * promedio (que el rígido ya cubre), no la pose completa.
 *
 * Eje de doblado: Y local del mesh. No es una suposición: el formato glTF
 * exige espacio Y-up, y los assets de este proyecto están exportados con
 * "Khronos glTF Blender I/O" (confirmado leyendo el JSON de cada `.glb`),
 * que convierte automáticamente el Z-up nativo de Blender a Y-up al
 * exportar — la garantía viene del formato + la herramienta, no de mirar
 * el modelo.
 *
 * Riesgo NO verificable sin dispositivo: el sentido (izquierda/derecha) del
 * eje X local respecto a la tangente del párpado — si está invertido, el
 * doblado queda espejado en vez de seguir la curva real.
 */
object LashMeshBender {

    /** `curve == null` o `eyeWidthPx <= 0` -> sin curvatura adicional para
     * este frame: devuelve los vértices originales tal cual (barato, sin
     * recorrer nada). */
    fun bend(
        raw: RawMesh,
        curve: LashLineCurve?,
        eyeWidthPx: Float,
        /** [EyeAnchor.lashCurveAnchorOffsetPx] / [EyeTransform.
         * lashCurveAnchorOffsetPx] — `pixelLocalX` de acá abajo está
         * expresado relativo al ANCLA de render (porque ahí es donde
         * `EyeTransformCalculator` posiciona el centro del mesh), pero
         * `curve` fue ajustada relativa a `EyeAnchor.lidCenter` (el
         * centroide real del párpado, sin el shift de NOSE_AVOID_SHIFT —
         * ver nota de [EyeAnchorCalculator], 2026-08-02). Sin sumar este
         * offset, casi todos los vértices quedaban fuera del rango
         * `[minLocalX, maxLocalX]` que la curva realmente ajustó y
         * `deviationAt`/`slopeAt` extrapolaban linealmente en vez de
         * seguir la parábola — la pestaña se veía recta. `0f` = mismo
         * comportamiento que antes del fix (compatibilidad con callers que
         * no lo pasen). */
        anchorOffsetPx: Float = 0f,
        strength: Float = RendererConfiguration.LASH_BEND_STRENGTH,
    ): List<Geometry.Vertex> {
        if (curve == null || eyeWidthPx <= 0f || strength <= 0f) return raw.vertices

        val span = raw.maxX - raw.minX
        if (span <= 1e-4f) return raw.vertices

        // El span local del mesh (unidades propias del .glb) corresponde al
        // ancho real del ojo en píxeles (eyeWidthPx) — de ahí la conversión
        // píxeles<->unidades locales, derivada de cantidades que YA calcula
        // el resto del pipeline, no una constante inventada.
        val meshUnitsPerPixel = span / eyeWidthPx

        return raw.vertices.map { vertex ->
            val pos = vertex.position
            val t = (pos.x - raw.minX) / span
            val pixelLocalX = (t - 0.5f) * eyeWidthPx + anchorOffsetPx

            // `strength` amortigua la desviación calculada (ver
            // RendererConfiguration.LASH_BEND_STRENGTH) — se escala ANTES de
            // la pendiente/normal también, así la inclinación de la normal
            // queda consistente con el desplazamiento real aplicado (si no,
            // la iluminación insinuaría más curva de la que realmente se ve).
            val deviationPx = curve.deviationAt(pixelLocalX) * strength
            val slope = curve.slopeAt(pixelLocalX) * strength

            val newPosition = Float3(pos.x, pos.y + deviationPx * meshUnitsPerPixel, pos.z)
            val newNormal = tiltNormal(vertex.normal ?: DEFAULT_NORMAL, slope)

            vertex.copy(position = newPosition, normal = newNormal)
        }
    }

    /** Rota la normal alrededor del eje Z local por `atan(slope)`. `slope`
     * es adimensional (píxeles/píxeles), así que la rotación no depende de
     * la conversión de unidades usada para la posición. */
    private fun tiltNormal(normal: Float3, slope: Float): Float3 {
        val angle = atan(slope.toDouble()).toFloat()
        val cosA = cos(angle.toDouble()).toFloat()
        val sinA = sin(angle.toDouble()).toFloat()
        val nx = normal.x * cosA - normal.y * sinA
        val ny = normal.x * sinA + normal.y * cosA
        val nz = normal.z
        val lengthSq = nx * nx + ny * ny + nz * nz
        if (lengthSq <= 0f || !lengthSq.isFinite()) return normal
        val invLength = 1f / sqrt(lengthSq)
        return Float3(nx * invLength, ny * invLength, nz * invLength)
    }

    private val DEFAULT_NORMAL = Float3(0f, 1f, 0f)
}
