package com.example.test_face.render

import android.graphics.Bitmap
import kotlin.math.hypot

/**
 * Detecta la posición REAL de la pestaña visible en la imagen de cámara.
 *
 * ## Versión 3 — corrección de dirección + detección de borde (edge-first)
 *
 * ### Fix principal: dirección perpendicular garantizada hacia afuera del ojo
 * Las versiones anteriores calculaban la perpendicular como rotación 90° CCW
 * de la tangente. Esto puede apuntar hacia el iris o hacia la piel dependiendo
 * del orden en que se recorren los puntos del anillo del párpado. Ahora se
 * verifica con el centroide del ojo: la perpendicular SIEMPRE apunta en la
 * dirección que se aleja del centro del ojo (donde están las pestañas reales).
 *
 * ### Detección de borde (edge-first) en vez de mínimo de luminancia
 * El mínimo absoluto o el centroide ponderado pueden anclarse en sombra de
 * maquillaje si todo el arco es oscuro. La detección de borde busca la
 * primera TRANSICIÓN luminancia-alta→luminancia-baja al salir del párpado:
 * eso es la raíz de la pestaña. Es más robusta con maquillaje oscuro
 * porque detecta el CAMBIO, no el valor absoluto.
 *
 * ### Referencia de piel local dinámica
 * En lugar de un umbral fijo de luminancia de pestaña, se calcula la
 * luminancia promedio de los primeros píxeles de la banda (cerca del
 * landmark, que suelen ser piel del párpado) y se usa como referencia.
 * Esto hace que el detector funcione con diferentes tonos de piel.
 */
object LashEdgeDetector {

    // ── Parámetros de búsqueda ──────────────────────────────────────────
    // Búsqueda hacia afuera del ojo (donde están las pestañas).
    // El rango pequeño hacia adentro permite corregir si el landmark está
    // ligeramente por encima de la raíz real de la pestaña.
    private const val SEARCH_RANGE_INWARD_PX  = 2f   // hacia el interior del ojo
    private const val SEARCH_RANGE_OUTWARD_PX = 16f  // hacia afuera (pestañas)
    private const val SEARCH_STEP_PX          = 0.5f  // sub-píxel

    // ── Umbral de borde ─────────────────────────────────────────────────
    // La pestaña se detecta cuando la luminancia cae más de este porcentaje
    // por debajo de la referencia de piel local. 0.80 = la pestaña debe ser
    // al menos 20% más oscura que la piel adyacente.
    private const val EDGE_LUMINANCE_RATIO = 0.80f

    // Diferencia absoluta mínima además de la ratio — protege el caso de
    // piel muy oscura donde 20% de diferencia es < 10 unidades de luminancia.
    private const val MIN_ABS_CONTRAST = 22f

    // Cuántos pasos iniciales usar para calcular la referencia de piel.
    // Se promedia la luminancia de los primeros SKIN_REF_STEPS píxeles
    // (los más cercanos al landmark = piel del párpado).
    private const val SKIN_REF_STEPS = 4

    /**
     * Corrige [upperLidPoints] hacia la pestaña real visible en [bitmap].
     * `null` o menos de 2 puntos → devuelve [upperLidPoints] sin cambios.
     */
    fun detectRealLashLine(bitmap: Bitmap?, upperLidPoints: List<ImagePoint>): List<ImagePoint> {
        if (bitmap == null || upperLidPoints.size < 2) return upperLidPoints

        // Centroide del párpado superior = aproximación del centro del ojo.
        // Usado para verificar que la perpendicular apunte hacia AFUERA.
        val cx = upperLidPoints.sumOf { it.x.toDouble() }.toFloat() / upperLidPoints.size
        val cy = upperLidPoints.sumOf { it.y.toDouble() }.toFloat() / upperLidPoints.size

        return upperLidPoints.mapIndexed { i, p ->
            val (tx, ty) = localTangent(upperLidPoints, i)

            // Perpendicular 90° CCW: (-ty, tx)
            var perpX = -ty
            var perpY = tx

            // Vector del centroide al punto actual = dirección "hacia afuera"
            val outX = p.x - cx
            val outY = p.y - cy
            // Si el producto escalar es negativo, la perpendicular apunta
            // hacia el interior del ojo — se invierte para que apunte afuera.
            if (perpX * outX + perpY * outY < 0f) {
                perpX = -perpX
                perpY = -perpY
            }

            detectOne(bitmap, p, perpX, perpY)
        }
    }

    /**
     * Tangente local en [i] por diferencia central (más precisa en la curvatura
     * del párpado que la tangente global primera→última).
     */
    private fun localTangent(points: List<ImagePoint>, i: Int): Pair<Float, Float> {
        val prev = if (i > 0) points[i - 1] else points[i]
        val next = if (i < points.size - 1) points[i + 1] else points[i]
        val dx = next.x - prev.x
        val dy = next.y - prev.y
        val len = hypot(dx.toDouble(), dy.toDouble()).toFloat().coerceAtLeast(1e-3f)
        return Pair(dx / len, dy / len)
    }

    /**
     * Detecta el borde de la pestaña en la dirección (perpX, perpY) desde [p].
     *
     * Método "edge-first":
     * 1. Calcula la referencia de piel local promediando los primeros
     *    [SKIN_REF_STEPS] píxeles (los más cercanos al landmark).
     * 2. Camina hacia afuera buscando la primera posición donde la luminancia
     *    cae por debajo del umbral dinámico (skin × EDGE_LUMINANCE_RATIO).
     * 3. Si no encuentra borde claro (toda la banda es oscura = maquillaje
     *    uniforme, o toda es clara = sin pestaña visible), conserva el
     *    landmark original en lugar de dar una corrección ruidosa.
     */
    private fun detectOne(bitmap: Bitmap, p: ImagePoint, perpX: Float, perpY: Float): ImagePoint {
        val w = bitmap.width
        val h = bitmap.height

        // ── Paso 1: referencia de piel local ────────────────────────────
        var skinSum = 0f
        var skinCount = 0
        for (s in 0 until SKIN_REF_STEPS) {
            val t = -SEARCH_RANGE_INWARD_PX + s * SEARCH_STEP_PX
            val sx = (p.x + perpX * t).toInt()
            val sy = (p.y + perpY * t).toInt()
            if (sx in 0 until w && sy in 0 until h) {
                skinSum += luminanceOf(bitmap.getPixel(sx, sy))
                skinCount++
            }
        }
        if (skinCount == 0) return p
        val skinRef = skinSum / skinCount

        // ── Paso 2: umbral dinámico ──────────────────────────────────────
        val edgeThreshold = (skinRef * EDGE_LUMINANCE_RATIO)
            .coerceAtMost(skinRef - MIN_ABS_CONTRAST)

        // Si la piel ya es muy oscura, no hay contraste fiable — conservar landmark
        if (skinRef - edgeThreshold < MIN_ABS_CONTRAST) return p

        // ── Paso 3: detección de borde (primer cruce del umbral) ─────────
        var firstEdgeT = Float.NaN
        var bestT = 0f
        var bestLum = Float.MAX_VALUE

        var t = 0f
        while (t <= SEARCH_RANGE_OUTWARD_PX) {
            val sx = (p.x + perpX * t).toInt()
            val sy = (p.y + perpY * t).toInt()
            if (sx in 0 until w && sy in 0 until h) {
                val lum = luminanceOf(bitmap.getPixel(sx, sy))
                if (lum < bestLum) {
                    bestLum = lum
                    bestT = t
                }
                // Primer píxel que cruza el umbral = raíz de la pestaña
                if (firstEdgeT.isNaN() && lum < edgeThreshold) {
                    firstEdgeT = t
                }
            }
            t += SEARCH_STEP_PX
        }

        // Sin borde detectado → conservar landmark original
        if (firstEdgeT.isNaN()) return p

        // Usar el borde detectado. Si el mínimo está muy cerca del primer
        // borde (dentro de 3px), usamos el mínimo (más preciso para lashes
        // finas). Si están lejos (maquillaje grueso), usamos el primer borde
        // (más robusto — el mínimo podría estar en el interior del maquillaje).
        val finalT = if (bestT - firstEdgeT < 3f) bestT else firstEdgeT

        return ImagePoint(p.x + perpX * finalT, p.y + perpY * finalT)
    }

    private fun luminanceOf(pixel: Int): Float {
        val r = (pixel shr 16) and 0xFF
        val g = (pixel shr 8) and 0xFF
        val b = pixel and 0xFF
        return 0.299f * r + 0.587f * g + 0.114f * b
    }
}
