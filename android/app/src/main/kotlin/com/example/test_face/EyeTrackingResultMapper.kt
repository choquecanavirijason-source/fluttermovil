package com.example.test_face

import android.graphics.Bitmap
import com.example.test_face.render.ImagePoint
import com.example.test_face.render.LashEdgeDetector
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult

/**
 * Convertido de `object` a `class` para poder mantener estado de suavizado
 * (EMA) entre llamadas a [map]. El `object` anterior era sin estado y por
 * eso los puntos de pestaña naranja saltaban con el jitter de MediaPipe
 * sin ninguna forma de suavizarlos.
 *
 * ## Por qué se movían los puntos naranjas (explicación técnica)
 *
 * 1. **Jitter de MediaPipe (±2-3px)**: los landmarks del párpado oscilan
 *    entre frames aunque la cara no se mueva. Como el detector recibía los
 *    puntos crudos, el punto de origen de búsqueda se movía ±2-3px, y el
 *    resultado también.
 *
 * 2. **Tangente ruidosa**: la tangente local se calcula desde los landmarks
 *    (que jittean), así que la dirección perpendicular de búsqueda rotaba
 *    levemente cada frame, amplificando el movimiento.
 *
 * 3. **Sin memoria temporal**: el `object` singleton partía de cero en cada
 *    frame — no había forma de suavizar la salida entre frames.
 *
 * ## Solución: EMA con α = 0.35
 *
 * Cada punto detectado se mezcla 35% con el resultado nuevo y 65% con el
 * promedio histórico. Con MediaPipe a ~25Hz, esto equivale a un tiempo de
 * respuesta de ~4 frames (~160ms) — suficientemente rápido para seguir
 * movimientos reales de cabeza, suficientemente lento para absorber el
 * jitter frame-a-frame.
 *
 * Instanciar una vez por [FaceLandmarkerHelper] y reusar en cada resultado.
 */
class EyeTrackingResultMapper {

    // EMA para los puntos de pestaña naranja (debug overlay).
    // null = sin muestra previa (primer frame tras detectar el rostro).
    private var leftLashSmoothed: List<ImagePoint>? = null
    private var rightLashSmoothed: List<ImagePoint>? = null

    companion object {
        /** Factor de suavizado EMA: 0.35 = responde bien a movimiento real
         * pero absorbe el jitter de MediaPipe entre frames. */
        private const val EMA_ALPHA = 0.35f

        private val leftEyeIdx = listOf(33, 133, 160, 159, 158, 144, 145, 153)
        private val rightEyeIdx = listOf(362, 263, 387, 386, 385, 373, 374, 380)
        private val leftIrisIdx = listOf(468, 469, 470, 471, 472)
        private val rightIrisIdx = listOf(473, 474, 475, 476, 477)

        // Anillo completo de 16 puntos por ojo (mismo que FaceLandmarkIndices).
        // Orden anatómico fijo de MediaPipe: primeros 8 = párpado inferior,
        // últimos 8 = párpado superior.
        private val leftEyeRing = intArrayOf(33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246)
        private val rightEyeRing = intArrayOf(362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398)

        private val faceOvalIdx = listOf(
            10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377,
            152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109,
        )
    }

    /** Resetea el estado EMA cuando se pierde el rostro, para que al
     * redetectarlo no haya arrastre de posiciones antiguas. */
    fun reset() {
        leftLashSmoothed = null
        rightLashSmoothed = null
    }

    /**
     * [bitmap] — el mismo bitmap EXACTO que analizó MediaPipe para [result],
     * usado para detectar la posición real de la pestaña con [LashEdgeDetector].
     * `null` → lashLine = upperLid sin corrección.
     */
    fun map(result: FaceLandmarkerResult, width: Int, height: Int, bitmap: Bitmap? = null): Map<String, Any?> {
        if (result.faceLandmarks().isEmpty()) {
            reset() // rostro perdido → limpiar EMA
            return mapOf(
                "faceDetected" to false,
                "imageWidth" to width,
                "imageHeight" to height,
                "leftEye" to emptyList<Map<String, Double>>(),
                "rightEye" to emptyList<Map<String, Double>>(),
                "leftIris" to null,
                "rightIris" to null,
                "faceContour" to emptyList<Map<String, Double>>(),
                "leftUpperLid" to emptyList<Map<String, Double>>(),
                "leftLowerLid" to emptyList<Map<String, Double>>(),
                "rightUpperLid" to emptyList<Map<String, Double>>(),
                "rightLowerLid" to emptyList<Map<String, Double>>(),
                "leftLashLine" to emptyList<Map<String, Double>>(),
                "rightLashLine" to emptyList<Map<String, Double>>(),
            )
        }

        val landmarks = result.faceLandmarks()[0]

        fun point(index: Int): Map<String, Double> {
            val p = landmarks[index]
            return mapOf("x" to (p.x() * width).toDouble(), "y" to (p.y() * height).toDouble())
        }

        fun maybeCenter(indices: List<Int>): Map<String, Double>? {
            val valid = indices.filter { it < landmarks.size }
            if (valid.isEmpty()) return null
            val xs = valid.map { landmarks[it].x() * width }
            val ys = valid.map { landmarks[it].y() * height }
            return mapOf("x" to xs.average(), "y" to ys.average())
        }

        fun ringPoints(ring: IntArray): Pair<List<Map<String, Double>>, List<Map<String, Double>>> {
            val valid = ring.filter { it < landmarks.size }
            val all = valid.map { point(it) }
            val lower = all.take(8)
            val upper = if (all.size > 8) all.drop(8) else emptyList()
            return Pair(upper, lower)
        }

        val (leftUpper, leftLower) = ringPoints(leftEyeRing)
        val (rightUpper, rightLower) = ringPoints(rightEyeRing)

        fun toImagePoints(pts: List<Map<String, Double>>) =
            pts.map { ImagePoint(it.getValue("x").toFloat(), it.getValue("y").toFloat()) }

        fun toMapPoints(pts: List<ImagePoint>) =
            pts.map { mapOf("x" to it.x.toDouble(), "y" to it.y.toDouble()) }

        // ── Detectar + suavizar con EMA ──────────────────────────────────
        // 1. Detectar posición raw de la pestaña en la imagen actual
        val leftRaw  = LashEdgeDetector.detectRealLashLine(bitmap, toImagePoints(leftUpper))
        val rightRaw = LashEdgeDetector.detectRealLashLine(bitmap, toImagePoints(rightUpper))

        // 2. Mezclar con el promedio histórico (EMA)
        val leftSmoothed  = emaSmooth(leftLashSmoothed,  leftRaw,  EMA_ALPHA)
        val rightSmoothed = emaSmooth(rightLashSmoothed, rightRaw, EMA_ALPHA)

        // 3. Guardar para el siguiente frame
        leftLashSmoothed  = leftSmoothed
        rightLashSmoothed = rightSmoothed

        return mapOf(
            "faceDetected" to true,
            "imageWidth" to width,
            "imageHeight" to height,
            "leftEye" to leftEyeIdx.filter { it < landmarks.size }.map { point(it) },
            "rightEye" to rightEyeIdx.filter { it < landmarks.size }.map { point(it) },
            "leftIris" to maybeCenter(leftIrisIdx),
            "rightIris" to maybeCenter(rightIrisIdx),
            "faceContour" to faceOvalIdx.filter { it < landmarks.size }.map { point(it) },
            "leftUpperLid" to leftUpper,
            "leftLowerLid" to leftLower,
            "rightUpperLid" to rightUpper,
            "rightLowerLid" to rightLower,
            "leftLashLine" to toMapPoints(leftSmoothed),
            "rightLashLine" to toMapPoints(rightSmoothed),
        )
    }

    /**
     * EMA punto a punto: cada coordenada se mezcla α×nuevo + (1-α)×anterior.
     * Si no hay muestra previa (primer frame), devuelve [current] tal cual.
     * Si las listas tienen distinto tamaño (no debería pasar en operación
     * normal), devuelve [current] sin mezclar para evitar un IndexOutOfBounds.
     */
    private fun emaSmooth(
        previous: List<ImagePoint>?,
        current: List<ImagePoint>,
        alpha: Float,
    ): List<ImagePoint> {
        if (previous == null || previous.size != current.size) return current
        val invAlpha = 1f - alpha
        return current.mapIndexed { i, c ->
            val p = previous[i]
            ImagePoint(
                x = alpha * c.x + invAlpha * p.x,
                y = alpha * c.y + invAlpha * p.y,
            )
        }
    }
}
