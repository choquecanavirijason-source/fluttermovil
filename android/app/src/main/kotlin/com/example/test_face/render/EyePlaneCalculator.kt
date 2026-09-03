package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Float4
import dev.romainguy.kotlin.math.Mat4
import dev.romainguy.kotlin.math.Quaternion
import dev.romainguy.kotlin.math.cross
import dev.romainguy.kotlin.math.dot
import dev.romainguy.kotlin.math.normalize
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/** Base ortonormal y normal del plano local de un ojo específico. */
data class EyePlane(
    val right: Float3,
    val up: Float3,
    val normal: Float3,
    val rotation: Quaternion,
)

/**
 * Construye el plano local de un ojo combinando la pose global de la cabeza
 * (robusta, calculada por [EyePoseEstimator] a partir de la matriz de
 * MediaPipe) con la curvatura propia del párpado de ESE ojo en particular.
 *
 * La corrección local es el residuo angular 2D entre la tangente del
 * párpado superior y la línea recta esquina-a-esquina del ojo: captura
 * exactamente lo que la pose global de cabeza NO puede (asimetría/curvatura
 * natural de cada ojo), sin duplicar el giro de cabeza ya aplicado.
 */
object EyePlaneCalculator {

    fun compute(headPose: HeadPose, eye: EyeLandmarks, anchor: EyeAnchor): EyePlane {
        val ring = eye.ring
        val cornerA = ring.minByOrNull { it.x } ?: anchor.point
        val cornerB = ring.maxByOrNull { it.x } ?: anchor.point
        val cornerAngle = atan2((cornerB.y - cornerA.y).toDouble(), (cornerB.x - cornerA.x).toDouble())
        val lidAngle = atan2(anchor.upperLidTangent.y.toDouble(), anchor.upperLidTangent.x.toDouble())
        val residualRad = (lidAngle - cornerAngle).toFloat()

        val right = rotateAroundAxis(headPose.right, headPose.forward, residualRad)
        val rawUp = rotateAroundAxis(headPose.up, headPose.forward, residualRad)

        // Giro de 180° del modelo alrededor de su eje `right`: las pestañas
        // quedan VOLCADAS sobre el ojo (las fibras caen desde la raíz por
        // encima del párpado) en vez de erguidas hacia la ceja. Es la
        // orientación pedida expresamente para este producto — ver
        // [RendererConfiguration.FLIP_EYE_UP_AXIS].
        //
        // Se niegan `up` Y `normal` a la vez, nunca uno solo:
        //   - Negar solo `up` deja la base con determinante -1 (una
        //     reflexión, no una rotación) y `toQuaternion()` sobre eso
        //     devuelve una orientación inválida — el mismo error que la
        //     auditoría ya documentó en [EyePoseEstimator] (Hallazgo #2).
        //   - Negar `up` y `right` también daría determinante +1, pero
        //     intercambiaría izquierda/derecha, y ese eje está bien.
        //
        // La RAÍZ no se mueve: `rootCorrectedPosition` (ver
        // [EyeTransformCalculator]) desplaza el origen a lo largo de este
        // mismo `up`, así que al invertirse los dos términos se compensan y
        // el nacimiento de la pestaña sigue cayendo exactamente en el ancla
        // — los puntos del arco del párpado superior. Solo cambia hacia
        // dónde salen las fibras.
        //
        // `normal` solo se consume como `abs(normal.z)` (factor de escorzo en
        // [EyeTransformCalculator]), así que negarlo no altera ese cálculo.
        // ── Ángulo de nacimiento de la pestaña ─────────────────────────
        // Sin esto, las fibras salen a lo largo del eje "arriba" del PLANO DE
        // LA CARA, o sea planas contra el párpado. Una pestaña real no es
        // plana: nace en la línea y se levanta hacia ADELANTE, fuera de la
        // cara. La diferencia no se nota de frente, pero sí en ángulo —
        // mirando la cámara desde abajo, un abanico plano queda casi de canto
        // y se proyecta como una rayita (reportado en dispositivo), mientras
        // que unas pestañas reales desde abajo se ven MÁS, no menos.
        //
        // Es una rotación de la base alrededor de `right` (el eje del ojo
        // canto-a-canto), o sea inclina `up` hacia `normal`. Al ser una
        // rotación propia conserva el determinante +1, y como no toca `right`
        // no altera el eje izquierda/derecha.
        //
        // El SIGNO se decide por frame: rotar alrededor de `right` mueve `up`
        // hacia +`normal`, pero la normal de MediaPipe puede apuntar hacia la
        // cámara o hacia adentro de la cabeza según la pose. Se elige el
        // sentido que la lleva hacia la cámara (que en el mundo de Filament,
        // con la cámara mirando por -Z, es +Z) en vez de negar la normal —
        // negarla convertiría la base en una REFLEXIÓN y `toQuaternion()`
        // devolvería basura (mismo error que la auditoría documentó en
        // [EyePoseEstimator], Hallazgo #2).
        val tiltRad = Math.toRadians(
            RendererConfiguration.LASH_FORWARD_TILT_DEGREES.toDouble(),
        ).toFloat()
        val signedTilt = if (headPose.forward.z >= 0f) tiltRad else -tiltRad
        val tiltedUp = rotateAroundAxis(rawUp, right, signedTilt)
        val tiltedNormal = rotateAroundAxis(headPose.forward, right, signedTilt)

        val flip = if (RendererConfiguration.FLIP_EYE_UP_AXIS) -1f else 1f
        val up = tiltedUp * flip
        val normal = tiltedNormal * flip

        val rotationMatrix = Mat4(
            Float4(right, 0f),
            Float4(up, 0f),
            Float4(normal, 0f),
            Float4(0f, 0f, 0f, 1f),
        )
        return EyePlane(right = right, up = up, normal = normal, rotation = rotationMatrix.toQuaternion())
    }

    /** Fórmula de rotación de Rodrigues: rota [v] alrededor de [axis] (se normaliza) por [angleRad]. */
    private fun rotateAroundAxis(v: Float3, axis: Float3, angleRad: Float): Float3 {
        val a = normalize(axis)
        val cosA = cos(angleRad.toDouble()).toFloat()
        val sinA = sin(angleRad.toDouble()).toFloat()
        val term1 = v * cosA
        val term2 = cross(a, v) * sinA
        val term3 = a * (dot(a, v) * (1f - cosA))
        return term1 + term2 + term3
    }
}
