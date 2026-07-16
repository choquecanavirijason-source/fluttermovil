package com.example.test_face.render

import com.google.mediapipe.tasks.components.containers.NormalizedLandmark

/** Punto 2D en espacio de píxeles de la imagen analizada por MediaPipe. */
data class ImagePoint(val x: Float, val y: Float)

/**
 * Landmarks de un ojo ya resueltos a espacio de píxeles, con el párpado
 * superior identificado dinámicamente (mitad del anillo con menor Y) en vez
 * de asumir un sub-orden fijo de índices — más robusto ante cualquier
 * variación de numeración/orientación de MediaPipe.
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
     * a la misma posición horizontal, que este `ring` (ordenado solo por Y
     * para separar párpado superior, ver [from]) no garantiza. Esta razón
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

            val meanY = ring.sumOf { it.y.toDouble() }.toFloat() / ring.size
            val upperLid = ring.filter { it.y <= meanY }
                .ifEmpty { ring }
                .sortedBy { it.x }

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
