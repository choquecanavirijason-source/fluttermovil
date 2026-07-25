package com.example.test_face.render

import com.google.mediapipe.tasks.components.containers.NormalizedLandmark

/** Punto 2D en espacio de píxeles de la imagen analizada por MediaPipe. */
data class ImagePoint(val x: Float, val y: Float)

/**
 * Landmarks de un ojo ya resueltos a espacio de píxeles. El párpado superior
 * se identifica por el orden anatómico FIJO de `FaceLandmarkIndices.LEFT/
 * RIGHT_EYE_RING` (los últimos 8 de los 16 índices, ver [from]) — no por un
 * umbral dinámico de Y de imagen: ese umbral se usó antes y resultó frágil
 * ante roll de cabeza (Y de imagen deja de alinear con "arriba" anatómico
 * cuando la cabeza se inclina de costado), causando que el ancla se
 * desplazara de forma dependiente del ángulo.
 */
data class EyeLandmarks(
    val ring: List<ImagePoint>,
    /** Puntos del párpado superior, ordenados de izquierda a derecha en imagen. */
    val upperLid: List<ImagePoint>,
    val iris: ImagePoint?,
) {
    val width: Float
        get() = (ring.maxOf { it.x } - ring.minOf { it.x })

    val height: Float
        get() = (ring.maxOf { it.y } - ring.minOf { it.y })

    /**
     * Proxy barato de apertura del ojo: alto/ancho del anillo completo — más
     * alto = ojo más abierto, cae hacia 0 al cerrarse. NO es el EAR clásico
     * de 6 puntos (Soukupová & Čech, 2016): ese cálculo asume una
     * correspondencia conocida punto-a-punto entre párpado superior/inferior
     * a la misma posición horizontal, que este `ring` no garantiza (aunque
     * el split superior/inferior en sí ya es anatómicamente fijo, ver
     * [from]). Esta razón
     * alto/ancho es la aproximación robusta que sí se puede calcular sin
     * asumir ese orden — se usa en [LashRenderer] para atenuar la escala del
     * modelo suavemente al parpadear, en vez de que la geometría inestable
     * del anillo cuasi-cerrado lo haga de forma implícita y descontrolada
     * (ver auditoría del motor, hallazgo de oclusión/parpadeo).
     */
    val opennessRatio: Float
        get() = if (width > 0f) height / width else 0f

    companion object {
        fun from(
            landmarks: List<NormalizedLandmark>,
            ringIndices: IntArray,
            irisIndices: IntArray,
            imageWidth: Float,
            imageHeight: Float,
        ): EyeLandmarks? {
            val ring = ringIndices
                .filter { it < landmarks.size }
                .map { idx ->
                    val lm = landmarks[idx]
                    ImagePoint(lm.x() * imageWidth, lm.y() * imageHeight)
                }
            if (ring.size < 4) return null

            // El anillo de 16 puntos (FaceLandmarkIndices.LEFT/RIGHT_EYE_RING) tiene
            // un orden anatómico FIJO: los primeros 8 índices trazan el párpado
            // INFERIOR y los últimos 8 el SUPERIOR — verificado cruzando contra
            // landmarks individuales muy conocidos (159/145 para el ojo izquierdo,
            // 386/374 para el derecho, típicos de cualquier cálculo de EAR/parpadeo
            // con MediaPipe): 159 y 386 (top conocido) caen en los últimos 8, 145 y
            // 374 (bottom conocido) caen en los primeros 8, para AMBOS ojos.
            //
            // Usar ese orden fijo es más robusto que separar por umbral de Y de
            // imagen (lo que se hacía antes, `ring.filter { it.y <= meanY }`): con
            // la cabeza en ROLL (inclinada de costado, no solo pitch/yaw), "Y menor
            // en imagen" deja de coincidir con "párpado superior anatómico", así
            // que el umbral agarraba una mezcla de puntos de ambos párpados según
            // cuánto rolleaba la cabeza — eso desplazaba el ancla/tangente
            // calculados de forma DEPENDIENTE DEL ÁNGULO (síntoma reportado con
            // capturas reales: la pestaña se coloca distinto según cómo esté
            // inclinada la cabeza). Fallback al umbral de Y solo si el anillo no
            // tiene los 16 puntos esperados (algún índice fuera de rango del
            // resultado de MediaPipe — no debería pasar en operación normal).
            val upperLid = if (ring.size == ringIndices.size && ring.size == 16) {
                ring.subList(8, 16).sortedBy { it.x }
            } else {
                val meanY = ring.sumOf { it.y.toDouble() }.toFloat() / ring.size
                ring.filter { it.y <= meanY }.ifEmpty { ring }.sortedBy { it.x }
            }

            val validIris = irisIndices.filter { it < landmarks.size }
            val iris = if (validIris.isEmpty()) {
                null
            } else {
                val xs = validIris.map { landmarks[it].x() * imageWidth }
                val ys = validIris.map { landmarks[it].y() * imageHeight }
                ImagePoint(xs.average().toFloat(), ys.average().toFloat())
            }

            return EyeLandmarks(ring = ring, upperLid = upperLid, iris = iris)
        }
    }
}
