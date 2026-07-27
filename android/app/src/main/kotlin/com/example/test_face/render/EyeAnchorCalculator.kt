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
 *   anchorY = meanY - height * HEIGHT_OFFSET
 *
 * donde `meanY` es el promedio de Y de TODOS los puntos del párpado
 * superior (el mismo conjunto y el mismo peso que `meanX`, así que X e Y
 * quedan geométricamente consistentes entre sí) y HEIGHT_OFFSET ≥ 0 mueve
 * el ancla hacia arriba (Y más pequeño = más arriba en la imagen = hacia
 * la frente).
 *
 * CORRECCIÓN 2026-07-24 (ajuste fino): antes `anchorY` usaba `edgeLidY`
 * (promedio del 30% de puntos con MAYOR Y del párpado superior) en vez de
 * `meanY`. Para un párpado con forma de arco (más alto — Y menor — en el
 * centro, más bajo en las esquinas, que es la forma real de un ojo), "el
 * 30% con mayor Y" son casi siempre las ESQUINAS, no una muestra
 * representativa de toda la línea de pestañas — mientras que `meanX` sí
 * promedia TODOS los puntos (queda centrado). Esa mezcla (X centrado, Y de
 * esquina) desplazaba el ancla verticalmente respecto a dónde está la
 * línea de pestañas real en el CENTRO del ojo (donde cae `meanX`) — un
 * desfase real de varios píxeles, confirmado con logcat en dispositivo
 * real. `meanY` no tiene ese sesgo: es el centroide del mismo conjunto de
 * puntos que ya usa `meanX`.
 *
 * HEIGHT_OFFSET = 0.0 (valor actual) → ancla en el centroide del párpado
 * superior, y como ahora se ancla la RAÍZ real (no el centro del modelo),
 * la raíz de la pestaña nace ahí — anatómicamente correcto por defecto.
 * HEIGHT_OFFSET > 0 → la raíz queda esa fracción de la altura del ojo por
 * ENCIMA del centroide, solo si hiciera falta un margen estético.
 */
object EyeAnchorCalculator {

    /** [imageWidth] — ancho de la imagen de análisis, en píxeles. Se usa
     * SOLO para estimar qué esquina del ojo es la externa (hacia la sien)
     * vs la interna (hacia la nariz), comparando cada esquina contra el
     * centro horizontal de la imagen — ver [RendererConfiguration.
     * NOSE_AVOID_SHIFT]. No depende de saber si es el ojo izquierdo o
     * derecho de MediaPipe (evita esa ambigüedad — ver nota en
     * [FaceLandmarkIndices]), solo de que el rostro esté razonablemente
     * centrado en el cuadro (caso normal de selfie). */
    fun compute(eye: EyeLandmarks, imageWidth: Float): EyeAnchor? {
        if (eye.upperLid.size < 2) return null

        val width = eye.width
        val height = eye.height
        if (width < 1f || height < 0.5f) return null

        // Centroide del párpado superior = promedio de X e Y de TODOS sus
        // puntos. Ambos se calculan del MISMO conjunto de puntos con el
        // MISMO peso, así que X e Y quedan geométricamente consistentes
        // entre sí (corrección 2026-07-24, ver nota de la clase).
        val meanX = eye.upperLid.sumOf { it.x.toDouble() }.toFloat() / eye.upperLid.size
        val meanY = eye.upperLid.sumOf { it.y.toDouble() }.toFloat() / eye.upperLid.size

        // Desplaza el ancla X hacia la esquina EXTERNA del ojo (la más
        // lejana al centro horizontal de la imagen, asumiendo rostro
        // centrado) — ver RendererConfiguration.NOSE_AVOID_SHIFT y la nota
        // de la clase (2026-07-24): evita que la expansión simétrica de
        // WIDTH_MULTIPLIER invada la nariz por el lado interno.
        val cornerA = eye.ring.minByOrNull { it.x }
        val cornerB = eye.ring.maxByOrNull { it.x }
        val imageCenterX = imageWidth / 2f
        val outerCornerX = if (cornerA != null && cornerB != null) {
            if (kotlin.math.abs(cornerA.x - imageCenterX) > kotlin.math.abs(cornerB.x - imageCenterX)) {
                cornerA.x
            } else {
                cornerB.x
            }
        } else {
            meanX
        }
        val shiftSign = if (outerCornerX >= meanX) 1f else -1f
        val shiftedX = meanX + shiftSign * width * RendererConfiguration.NOSE_AVOID_SHIFT

        // El ancla sube (Y decrece) desde el centroide según HEIGHT_OFFSET.
        val anchorY = meanY - height * RendererConfiguration.HEIGHT_OFFSET
        val anchor = ImagePoint(shiftedX, anchorY)

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
