package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import kotlin.math.sqrt

/**
 * Suavizado temporal de UN ojo: un [OneEuroFilter] independiente por
 * componente de posición/rotación/escala.
 *
 * **Optimizado para latencia mínima (nivel TikTok)**:
 * - `minCutoff` alto en posición para que el filtro apenas suavice en reposo
 *   (preferimos velocidad sobre estabilidad — el jitter residual es menor
 *   que el lag que un filtro más agresivo introduciría).
 * - Alineación antipodal de quaterniones para evitar glitches de rotación.
 */
class EyeTrackingFilter {
    private val posX = OneEuroFilter(RendererConfiguration.POSITION_MIN_CUTOFF, RendererConfiguration.POSITION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val posY = OneEuroFilter(RendererConfiguration.POSITION_MIN_CUTOFF, RendererConfiguration.POSITION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val posZ = OneEuroFilter(RendererConfiguration.POSITION_MIN_CUTOFF, RendererConfiguration.POSITION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)

    private val rotX = OneEuroFilter(RendererConfiguration.ROTATION_MIN_CUTOFF, RendererConfiguration.ROTATION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val rotY = OneEuroFilter(RendererConfiguration.ROTATION_MIN_CUTOFF, RendererConfiguration.ROTATION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val rotZ = OneEuroFilter(RendererConfiguration.ROTATION_MIN_CUTOFF, RendererConfiguration.ROTATION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val rotW = OneEuroFilter(RendererConfiguration.ROTATION_MIN_CUTOFF, RendererConfiguration.ROTATION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)

    private val scaleX = OneEuroFilter(RendererConfiguration.SCALE_MIN_CUTOFF, RendererConfiguration.SCALE_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val scaleY = OneEuroFilter(RendererConfiguration.SCALE_MIN_CUTOFF, RendererConfiguration.SCALE_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val scaleZ = OneEuroFilter(RendererConfiguration.SCALE_MIN_CUTOFF, RendererConfiguration.SCALE_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)

    /** Último quaternion alineado, referencia para el próximo frame. */
    private var lastAlignedQ = Quaternion(0f, 0f, 0f, 1f)

    fun apply(target: EyeTransform): EyeTransform {
        val now = System.nanoTime()

        val position = Float3(
            posX.filter(target.position.x, now),
            posY.filter(target.position.y, now),
            posZ.filter(target.position.z, now),
        )

        // Alineación antipodal: q y -q son la misma rotación.
        // Sin alinear, un flip de signo de MediaPipe hace que el filtro
        // interpole "a través de cero" → glitch violento.
        val raw = target.rotation
        val aligned = alignQuaternion(raw)

        val qx = rotX.filter(aligned.x, now)
        val qy = rotY.filter(aligned.y, now)
        val qz = rotZ.filter(aligned.z, now)
        val qw = rotW.filter(aligned.w, now)
        val rotation = normalizedQuaternion(qx, qy, qz, qw)
        lastAlignedQ = rotation

        val scale = Float3(
            scaleX.filter(target.scale.x, now),
            scaleY.filter(target.scale.y, now),
            scaleZ.filter(target.scale.z, now),
        )

        return EyeTransform(
            position = position,
            rotation = rotation,
            scale = scale,
            lashLineCurve = target.lashLineCurve,
            eyeWidthPx = target.eyeWidthPx,
        )
    }

    fun reset() {
        posX.reset(); posY.reset(); posZ.reset()
        rotX.reset(); rotY.reset(); rotZ.reset(); rotW.reset()
        scaleX.reset(); scaleY.reset(); scaleZ.reset()
        lastAlignedQ = Quaternion(0f, 0f, 0f, 1f)
    }

    private fun alignQuaternion(q: Quaternion): Quaternion {
        val dot = q.x * lastAlignedQ.x + q.y * lastAlignedQ.y +
                  q.z * lastAlignedQ.z + q.w * lastAlignedQ.w
        return if (dot < 0f) Quaternion(-q.x, -q.y, -q.z, -q.w) else q
    }

    private fun normalizedQuaternion(x: Float, y: Float, z: Float, w: Float): Quaternion {
        val lengthSq = x * x + y * y + z * z + w * w
        if (lengthSq <= 0f || !lengthSq.isFinite()) return Quaternion(0f, 0f, 0f, 1f)
        val invLength = 1f / sqrt(lengthSq)
        return Quaternion(x * invLength, y * invLength, z * invLength, w * invLength)
    }
}
