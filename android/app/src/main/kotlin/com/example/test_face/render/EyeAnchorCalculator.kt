package com.example.test_face.render

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/** Resultado geométrico 2D de un ojo, listo para proyectar a espacio de mundo. */
data class EyeAnchor(
    val point: ImagePoint,
    val widthPx: Float,
    val heightPx: Float,
    val upperLidTangent: ImagePoint,
)

/**
 * Calcula el punto de anclaje de las pestañas 3D.
 *
 * **Principio (corregido 2026-07-24)**: `anchor.point` es el punto de mundo
 * donde debe renderizar la RAÍZ real de la pestaña (`EyeModelSlot.
 * rootLocalY`, ver [EyeTransformCalculator]) — NO el centro geométrico del
 * bounding box del modelo. Se verificó con los 10 `.glb` reales de
 * `assets/modelos/` que su bounding box en Y está centrado en el origen
 * local, pero la masa/raíz visual del mesh está muy por debajo de ese
 * centro — anclar el centro (como se hacía antes) empujaba la pestaña
 * sistemáticamente hacia la ceja. Para extensiones de pestañas reales:
 *   - El borde del párpado (lash line) es el ORIGEN de las pestañas
 *   - Las pestañas se extienden HACIA ARRIBA desde ahí
 *
 * En coordenadas de imagen, Y crece HACIA ABAJO, así que "arriba en el
 * rostro" = Y menor. La fórmula es:
 *
 *   anchorY = edgeLidY - height * HEIGHT_OFFSET
 *
 * donde `edgeLidY` es el borde inferior del párpado superior (máximo Y
 * de los puntos upperLid) y HEIGHT_OFFSET ≥ 0 mueve el ancla hacia arriba
 * (Y más pequeño = más arriba en la imagen = hacia la frente).
 *
 * HEIGHT_OFFSET = 0.0 (valor actual) → ancla en el borde del párpado, y como
 * ahora se ancla la RAÍZ real (no el centro), la raíz de la pestaña nace
 * exactamente ahí — anatómicamente correcto por defecto.
 * HEIGHT_OFFSET > 0 → la raíz queda esa fracción de la altura del ojo por
 * ENCIMA del borde, solo si hiciera falta un margen estético.
 */
object EyeAnchorCalculator {

    fun compute(eye: EyeLandmarks): EyeAnchor? {
        if (eye.upperLid.size < 2) return null

        val width = eye.width
        val height = eye.height
        if (width < 1f || height < 0.5f) return null

        // Centro X del ojo = promedio de todos los puntos del párpado
        val meanX = eye.upperLid.sumOf { it.x.toDouble() }.toFloat() / eye.upperLid.size

        // Borde del párpado = el punto MÁS BAJO del párpado superior
        // (máximo Y en coords de imagen = más abajo en la imagen = el
        // borde visible del párpado donde nacen las pestañas).
        // Se promedia el 30% inferior para estabilidad ante ruido.
        val sortedByYDesc = eye.upperLid.sortedByDescending { it.y }
        val edgeCount = (sortedByYDesc.size * 0.30f).toInt().coerceAtLeast(1)
        val edgeLidY = sortedByYDesc.take(edgeCount).sumOf { it.y.toDouble() }.toFloat() / edgeCount

        // El ancla sube (Y decrece) desde el borde del párpado según HEIGHT_OFFSET.
        // El CENTRO del modelo 3D se coloca aquí.
        val anchorY = edgeLidY - height * RendererConfiguration.HEIGHT_OFFSET
        val anchor = ImagePoint(meanX, anchorY)

        val meanY = eye.upperLid.sumOf { it.y.toDouble() }.toFloat() / eye.upperLid.size
        val tangent = fittedUpperLidTangent(eye.upperLid, meanX, meanY)

        return EyeAnchor(point = anchor, widthPx = width, heightPx = height, upperLidTangent = tangent)
    }

    private fun fittedUpperLidTangent(
        points: List<ImagePoint>,
        meanX: Float,
        meanY: Float,
    ): ImagePoint {
        var sxx = 0.0
        var syy = 0.0
        var sxy = 0.0
        for (p in points) {
            val dx = (p.x - meanX).toDouble()
            val dy = (p.y - meanY).toDouble()
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        val theta = 0.5 * atan2(2.0 * sxy, sxx - syy)
        var tx = cos(theta).toFloat()
        var ty = sin(theta).toFloat()

        val first = points.first()
        val last = points.last()
        val refDx = last.x - first.x
        val refDy = last.y - first.y
        if (tx * refDx + ty * refDy < 0f) {
            tx = -tx
            ty = -ty
        }

        val len = hypot(tx.toDouble(), ty.toDouble()).toFloat().coerceAtLeast(1e-4f)
        return ImagePoint(tx / len, ty / len)
    }
}
