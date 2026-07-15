package com.example.test_face.render

import kotlin.math.hypot

/** Resultado geométrico 2D de un ojo, listo para proyectar a espacio de mundo. */
data class EyeAnchor(
    val point: ImagePoint,
    val widthPx: Float,
    val heightPx: Float,
    /** Tangente local del párpado superior (2D, normalizada), de un extremo al otro. */
    val upperLidTangent: ImagePoint,
)

/**
 * Calcula el punto de anclaje real de las pestañas: el promedio de TODA la
 * curva del párpado superior (no el mínimo Y de un único punto, como hacía
 * la versión anterior), desplazado hacia arriba una fracción de la altura
 * del ojo — el lugar donde nacen las pestañas reales.
 */
object EyeAnchorCalculator {

    fun compute(eye: EyeLandmarks): EyeAnchor? {
        if (eye.upperLid.size < 2) return null

        val width = eye.width
        val height = eye.height
        if (width < 1f || height < 0.5f) return null

        val meanX = eye.upperLid.sumOf { it.x.toDouble() }.toFloat() / eye.upperLid.size
        val meanY = eye.upperLid.sumOf { it.y.toDouble() }.toFloat() / eye.upperLid.size
        val anchor = ImagePoint(meanX, meanY - height * RendererConfiguration.HEIGHT_OFFSET)

        val first = eye.upperLid.first()
        val last = eye.upperLid.last()
        val tdx = last.x - first.x
        val tdy = last.y - first.y
        val tLen = hypot(tdx.toDouble(), tdy.toDouble()).toFloat().coerceAtLeast(1e-4f)
        val tangent = ImagePoint(tdx / tLen, tdy / tLen)

        return EyeAnchor(point = anchor, widthPx = width, heightPx = height, upperLidTangent = tangent)
    }
}
