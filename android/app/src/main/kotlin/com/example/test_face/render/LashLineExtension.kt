package com.example.test_face.render

import kotlin.math.hypot

/** Cola externa del párpado. MediaPipe marca la esquina de la ABERTURA del
 * ojo, no el final del párpado donde siguen naciendo pestañas, así que la
 * línea de pestañas se alarga más allá del canto externo en TODOS los ojos.
 *
 * Largo = distancia entre cantos × ([RendererConfiguration.LASH_LINE_TAIL_BASE]
 * + [RendererConfiguration.LASH_LINE_TAIL_NARROW_EXTRA] × qué tan rasgado es).
 * Dirección = mezcla de la tangente del párpado en el canto y el eje
 * lagrimal→canto ([RendererConfiguration.LASH_LINE_TAIL_AXIS_BLEND]): seguir
 * solo el eje formaba una "uña" en ojos redondos (el párpado baja fuerte al
 * canto y la cola volvía a subir); seguir solo la tangente la hundía. Revisado
 * con el face_landmarker de la app sobre todas las fotos de `pruebas/ojos`. */
object LashLineExtension {
    /** [upper]: puntos del párpado superior incluidos los dos cantos.
     * Devuelve la línea ordenada por X con la cola agregada en la punta del
     * canto externo (o sin cola si los datos no sirven). */
    fun withTail(
        upper: List<ImagePoint>,
        medial: ImagePoint,
        lateral: ImagePoint,
        shapeRatio: Float,
    ): List<ImagePoint> {
        val sorted = upper.sortedBy { it.x }
        if (sorted.size < 3) return sorted
        val span = hypot(lateral.x - medial.x, lateral.y - medial.y)
        val k = RendererConfiguration.LASH_LINE_TAIL_BASE +
            RendererConfiguration.LASH_LINE_TAIL_NARROW_EXTRA * narrowness(shapeRatio)
        if (!span.isFinite() || span < 1e-3f || k <= 1e-4f) return sorted
        // Punta de la línea que corresponde al canto externo y su vecino.
        val first = sorted.first()
        val last = sorted.last()
        val lateralIsLast = dist2(last, lateral) <= dist2(first, lateral)
        val end = if (lateralIsLast) last else first
        val prev = if (lateralIsLast) sorted[sorted.size - 2] else sorted[1]
        val tLen = hypot(end.x - prev.x, end.y - prev.y)
        if (!tLen.isFinite() || tLen < 1e-3f) return sorted
        val blend = RendererConfiguration.LASH_LINE_TAIL_AXIS_BLEND
        var dx = (end.x - prev.x) / tLen * (1f - blend) + (lateral.x - medial.x) / span * blend
        var dy = (end.y - prev.y) / tLen * (1f - blend) + (lateral.y - medial.y) / span * blend
        val dLen = hypot(dx, dy)
        if (!dLen.isFinite() || dLen < 1e-4f) return sorted
        dx /= dLen; dy /= dLen
        val tail = ImagePoint(end.x + dx * span * k, end.y + dy * span * k)
        return if (lateralIsLast) sorted + tail else listOf(tail) + sorted
    }

    /** 0 = ojo redondo … 1 = ojo rasgado (alto/ancho del ojo abierto), con
     * smoothstep para que no haya saltos al cambiar de persona/ángulo. */
    fun narrowness(shapeRatio: Float): Float {
        if (!shapeRatio.isFinite()) return 0f
        val round = RendererConfiguration.LASH_LINE_TAIL_ROUND_RATIO
        val narrow = RendererConfiguration.LASH_LINE_TAIL_NARROW_RATIO
        val t = ((round - shapeRatio) / (round - narrow)).coerceIn(0f, 1f)
        return t * t * (3f - 2f * t)
    }

    private fun dist2(a: ImagePoint, b: ImagePoint): Float {
        val dx = a.x - b.x
        val dy = a.y - b.y
        return dx * dx + dy * dy
    }
}
