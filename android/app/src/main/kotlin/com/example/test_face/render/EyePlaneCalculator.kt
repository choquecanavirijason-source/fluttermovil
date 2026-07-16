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
        val up = rotateAroundAxis(headPose.up, headPose.forward, residualRad)
        val normal = headPose.forward

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
