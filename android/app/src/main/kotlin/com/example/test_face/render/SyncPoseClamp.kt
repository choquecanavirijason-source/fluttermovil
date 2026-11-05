package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.sqrt

/**
 * Modo sincronizado ([RendererConfiguration.FRAME_SYNC_MODE]): el fondo de
 * cámara es EXACTAMENTE el fotograma que analizó MediaPipe, así que cualquier
 * retraso del filtro anti-temblor ([EyeTrackingFilter]) se ve como pestaña
 * despegada del ojo — sobre todo al EMPEZAR a moverse, cuando el One Euro
 * todavía no abrió su corte.
 *
 * Acá el filtro solo puede corregir temblor chico: si la pose filtrada se
 * aleja de la cruda más de un margen (fracción del ancho del ojo, grados,
 * fracción de escala), se la acerca hasta ese margen. Quieto, el temblor de
 * MediaPipe queda dentro del margen y el filtro actúa igual que antes; en
 * movimiento la pestaña nunca queda más atrás que el margen.
 */
object SyncPoseClamp {

    fun apply(raw: EyeTransform, filtered: EyeTransform, naturalSpan: Float): EyeTransform {
        // Posición: margen en anchos de ojo (en mundo).
        val width = raw.scale.x * naturalSpan
        var position = filtered.position
        if (width > 1e-6f && width.isFinite()) {
            val maxLag = RendererConfiguration.FRAME_SYNC_MAX_POSITION_LAG_SPANS * width
            val d = filtered.position - raw.position
            val len = sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
            if (len > maxLag && len.isFinite()) {
                position = raw.position + d * (maxLag / len)
            }
        }

        // Rotación: margen en grados.
        var rotation = filtered.rotation
        val a = raw.rotation
        var b = filtered.rotation
        var dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
        if (dot < 0f) {
            b = Quaternion(-b.x, -b.y, -b.z, -b.w)
            dot = -dot
        }
        val angle = 2f * acos(dot.coerceIn(-1f, 1f))
        val maxAngle = Math.toRadians(RendererConfiguration.FRAME_SYNC_MAX_ROTATION_LAG_DEG.toDouble()).toFloat()
        if (angle > maxAngle && angle.isFinite()) {
            val t = maxAngle / angle
            val q = Quaternion(
                a.x + (b.x - a.x) * t,
                a.y + (b.y - a.y) * t,
                a.z + (b.z - a.z) * t,
                a.w + (b.w - a.w) * t,
            )
            val n = sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
            if (n > 1e-6f) rotation = Quaternion(q.x / n, q.y / n, q.z / n, q.w / n)
        }

        // Escala: margen como fracción de la escala cruda.
        val r = RendererConfiguration.FRAME_SYNC_MAX_SCALE_LAG_FRACTION
        fun clampScale(f: Float, c: Float): Float {
            val m = abs(c) * r
            return f.coerceIn(c - m, c + m)
        }
        val scale = Float3(
            clampScale(filtered.scale.x, raw.scale.x),
            clampScale(filtered.scale.y, raw.scale.y),
            clampScale(filtered.scale.z, raw.scale.z),
        )

        return filtered.copy(position = position, rotation = rotation, scale = scale)
    }
}
