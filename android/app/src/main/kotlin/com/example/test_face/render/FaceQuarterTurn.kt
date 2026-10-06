package com.example.test_face.render

import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.roundToInt

/**
 * En cuántos cuartos de vuelta está girado el rostro EN LA IMAGEN, y cómo
 * llevar puntos a un marco "derecho" y de vuelta.
 *
 * ## Por qué existe (clienta acostada, cámara trasera)
 *
 * Todo el cálculo 2D del ojo ([EyeLandmarks.width]/`height`,
 * [EyeAnchorCalculator], [EyePlaneCalculator], [LashLineCurve]) está escrito
 * y calibrado para un ojo HORIZONTAL: comisuras = x mínima/máxima, tangente
 * del párpado por mínimos cuadrados de y sobre x, y la curva orientada hacia
 * +x de pantalla. Con la cara a 180° eso orienta la tangente hacia la
 * izquierda DEL ROSTRO y la curva de la línea de pestañas sale invertida
 * respecto del modelo; a ±90° directamente mide el alto del ojo como ancho.
 *
 * En vez de reescribir esos cálculos, se giran los puntos del ojo por
 * cuartos de vuelta hasta que el rostro quede derecho, se calcula todo ahí
 * exactamente como antes, y sólo el ancla (punto y direcciones) vuelve a la
 * imagen. La pose 3D no se toca: viene de la matriz de MediaPipe, que ya
 * trae el giro real de la cabeza.
 *
 * La orientación sale del eje entre los dos ojos, con cada ojo identificado
 * por sus índices anatómicos de MediaPipe — no por su posición en pantalla
 * ni por ningún flag de "modo invertido". Con la cara a menos de 45° de la
 * vertical da 0 y nada cambia respecto del comportamiento de siempre.
 */
object FaceQuarterTurn {

    /**
     * `0` = rostro derecho; `1` = girado 90° en el sentido en que la imagen
     * (y hacia abajo) gira de +x hacia +y; `2` = cabeza abajo; `3` = −90°.
     * `0` también si faltan landmarks.
     */
    fun of(landmarks: List<NormalizedLandmark>, imageWidth: Float, imageHeight: Float): Int {
        val left = centroid(landmarks, FaceLandmarkIndices.LEFT_EYE_RING, imageWidth, imageHeight)
            ?: return 0
        val right = centroid(landmarks, FaceLandmarkIndices.RIGHT_EYE_RING, imageWidth, imageHeight)
            ?: return 0
        // `LEFT_EYE_RING` es el ojo de la izquierda de la imagen con la cara
        // derecha (ver [EyeBlinkBlendshapes]), así que LEFT→RIGHT es el +x
        // del rostro: (1, 0) derecho, (−1, 0) cabeza abajo.
        val angle = atan2((right.y - left.y).toDouble(), (right.x - left.x).toDouble())
        return Math.floorMod((angle / (PI / 2)).roundToInt(), 4)
    }

    /** Gira [p] [quarters] cuartos de vuelta alrededor de ([cx], [cy]); en
     * imagen (y hacia abajo) cada cuarto lleva +x a +y. */
    fun rotate(p: ImagePoint, quarters: Int, cx: Float = 0f, cy: Float = 0f): ImagePoint {
        var dx = p.x - cx
        var dy = p.y - cy
        repeat(Math.floorMod(quarters, 4)) {
            val t = dx
            dx = -dy
            dy = t
        }
        return ImagePoint(cx + dx, cy + dy)
    }

    /** [eye] en el marco donde un rostro girado [turns] cuartos queda derecho. */
    fun toUpright(eye: EyeLandmarks, turns: Int, cx: Float, cy: Float): EyeLandmarks {
        if (turns == 0) return eye
        val back = -turns
        return EyeLandmarks(
            ring = eye.ring.map { rotate(it, back, cx, cy) },
            // Mismo conjunto de puntos (el arco superior anatómico), sólo
            // reordenado por x en el marco nuevo, como lo deja [EyeLandmarks.from].
            upperLid = eye.upperLid.map { rotate(it, back, cx, cy) }.sortedBy { it.x },
            iris = eye.iris?.let { rotate(it, back, cx, cy) },
        )
    }

    /** Devuelve a la imagen un [anchor] calculado en el marco derecho. Las
     * medidas escalares y la forma ([EyeAnchor.measuredShape], relativa a
     * las comisuras) no dependen del giro. */
    fun fromUpright(anchor: EyeAnchor, turns: Int, cx: Float, cy: Float): EyeAnchor {
        if (turns == 0) return anchor
        return anchor.copy(
            point = rotate(anchor.point, turns, cx, cy),
            upperLidTangent = rotate(anchor.upperLidTangent, turns),
            lidCenter = rotate(anchor.lidCenter, turns, cx, cy),
            medialCanthus = rotate(anchor.medialCanthus, turns, cx, cy),
            lateralCanthus = rotate(anchor.lateralCanthus, turns, cx, cy),
        )
    }

    private fun centroid(
        landmarks: List<NormalizedLandmark>,
        ring: IntArray,
        imageWidth: Float,
        imageHeight: Float,
    ): ImagePoint? {
        val valid = ring.filter { it < landmarks.size }
        if (valid.isEmpty()) return null
        return ImagePoint(
            valid.map { landmarks[it].x() * imageWidth }.average().toFloat(),
            valid.map { landmarks[it].y() * imageHeight }.average().toFloat(),
        )
    }
}
