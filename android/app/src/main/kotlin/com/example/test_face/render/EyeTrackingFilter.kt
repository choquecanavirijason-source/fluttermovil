package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import kotlin.math.sqrt

/**
 * Suavizado temporal de UN ojo: un [OneEuroFilter] independiente por
 * componente de posición/rotación/escala (ver auditoría del motor,
 * Hallazgo #5, y [RendererConfiguration] para los parámetros). Reemplaza el
 * EMA/slerp de alpha fijo que tenía este proyecto antes: un alpha constante
 * no puede suavizar el jitter en reposo y evitar el lag en movimiento rápido
 * a la vez — el One Euro Filter sí, porque su corte se adapta a la
 * velocidad instantánea de cada señal.
 *
 * La rotación se filtra componente a componente del quaternion crudo y se
 * renormaliza al final — simplificación estándar en motores de AR facial en
 * producción: más barata que una interpolación adaptativa "exacta" sobre la
 * variedad de rotaciones, y el error introducido es insignificante porque
 * entre dos frames consecutivos la rotación cambia poco.
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

    fun apply(target: EyeTransform): EyeTransform {
        val now = System.nanoTime()

        val position = Float3(
            posX.filter(target.position.x, now),
            posY.filter(target.position.y, now),
            posZ.filter(target.position.z, now),
        )

        val raw = target.rotation
        val qx = rotX.filter(raw.x, now)
        val qy = rotY.filter(raw.y, now)
        val qz = rotZ.filter(raw.z, now)
        val qw = rotW.filter(raw.w, now)
        val rotation = normalizedQuaternion(qx, qy, qz, qw)

        val scale = Float3(
            scaleX.filter(target.scale.x, now),
            scaleY.filter(target.scale.y, now),
            scaleZ.filter(target.scale.z, now),
        )

        return EyeTransform(position = position, rotation = rotation, scale = scale)
    }

    fun reset() {
        posX.reset(); posY.reset(); posZ.reset()
        rotX.reset(); rotY.reset(); rotZ.reset(); rotW.reset()
        scaleX.reset(); scaleY.reset(); scaleZ.reset()
    }

    private fun normalizedQuaternion(x: Float, y: Float, z: Float, w: Float): Quaternion {
        val lengthSq = x * x + y * y + z * z + w * w
        if (lengthSq <= 0f || !lengthSq.isFinite()) return Quaternion(0f, 0f, 0f, 1f)
        val invLength = 1f / sqrt(lengthSq)
        return Quaternion(x * invLength, y * invLength, z * invLength, w * invLength)
    }
}
