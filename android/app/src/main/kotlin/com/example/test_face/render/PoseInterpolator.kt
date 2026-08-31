package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import kotlin.math.sqrt

/**
 * Predictor de pose que desacopla el framerate de render (vsync ~60Hz) del
 * framerate de MediaPipe (~20-30Hz) usando predicción cuadrática forward
 * con compensación ADAPTATIVA de latencia.
 *
 * **Cómo funciona la compensación adaptativa** (técnica de TikTok/DeepAR):
 *
 * 1. CameraXManager mide la latencia REAL de MediaPipe en ESTE dispositivo
 *    (ej: 40ms en un Snapdragon 6xx, 20ms en un Snapdragon 8xx)
 * 2. LashRenderer pasa esa latencia medida (+ 16ms de SurfaceFlinger)
 *    a [sample] en cada vsync
 * 3. Este interpolador predice la posición [latencyNanos] en el FUTURO,
 *    usando velocidad + aceleración de las 3 últimas muestras
 *
 * Resultado: el modelo 3D muestra dónde el rostro ESTÁ AHORA, no dónde
 * estaba cuando se capturó el frame que MediaPipe acaba de procesar.
 */
class PoseInterpolator {
    private data class Sample(val transform: EyeTransform, val tNanos: Long)

    @Volatile private var s0: Sample? = null
    @Volatile private var s1: Sample? = null
    @Volatile private var s2: Sample? = null
    @Volatile private var pushesSinceReset = 0

    fun push(transform: EyeTransform, tNanos: Long) {
        s0 = s1
        s1 = s2
        s2 = Sample(transform, tNanos)
        pushesSinceReset++
    }

    fun reset() {
        s0 = null; s1 = null; s2 = null
        pushesSinceReset = 0
    }

    /**
     * Pose predicha para [nowNanos], compensando [latencyNanos] de pipeline.
     * Con 3 muestras usa predicción cuadrática (velocidad + aceleración);
     * con 2 usa lineal; con 1 devuelve la muestra directa.
     */
    fun sample(nowNanos: Long, latencyNanos: Long = 35_000_000L): EyeTransform? {
        val latest = s2 ?: return null
        if (pushesSinceReset < WARMUP_PUSHES) return latest.transform

        val mid = s1 ?: return latest.transform
        val dt1 = (latest.tNanos - mid.tNanos).toFloat()
        if (dt1 <= 0f) return latest.transform

        // Timestamp predicho: ahora + latencia de pipeline completo.
        // Esto hace que el modelo se renderice donde el rostro ESTÁ AHORA,
        // no donde estaba hace [latencyNanos] ms.
        val targetNanos = nowNanos + latencyNanos
        val elapsed = (targetNanos - latest.tNanos).toFloat()
        val t = (elapsed / dt1).coerceIn(0f, MAX_EXTRAPOLATION_FACTOR)

        val prev = s0
        return if (prev != null) {
            val dt0 = (mid.tNanos - prev.tNanos).toFloat()
            if (dt0 > 0f) {
                quadraticPredict(prev.transform, mid.transform, latest.transform, dt0, dt1, t)
            } else {
                lerpTransform(mid.transform, latest.transform, 1f + t)
            }
        } else {
            lerpTransform(mid.transform, latest.transform, 1f + t)
        }
    }

    /**
     * Predicción cuadrática: pos = p2 + v2·Δt + ½·a·Δt²
     * Mucho más precisa que lineal cuando la cabeza acelera/desacelera.
     */
    private fun quadraticPredict(
        a: EyeTransform, b: EyeTransform, c: EyeTransform,
        dt0: Float, dt1: Float, t: Float,
    ): EyeTransform {
        val v0 = (b.position - a.position) * (1f / dt0)
        val v1 = (c.position - b.position) * (1f / dt1)
        val dtAvg = (dt0 + dt1) * 0.5f
        val accel = (v1 - v0) * (1f / dtAvg)
        val tScaled = t * dt1
        // Clamp la aceleración para evitar overshoot en movimiento brusco
        val accelMag = length(accel)
        val clampedAccel = if (accelMag > MAX_ACCEL) accel * (MAX_ACCEL / accelMag) else accel
        val predictedPos = c.position + v1 * tScaled + clampedAccel * (0.5f * tScaled * tScaled)

        // Escala: lineal (cuadrática en escala produce overshoots visuales)
        val scale = c.scale + (c.scale - b.scale) * t

        val rotation = lerpQuaternion(b.rotation, c.rotation, 1f + t)

        return EyeTransform(
            position = predictedPos,
            rotation = rotation,
            scale = scale,
            opennessRatio = c.opennessRatio,
            lashLineCurve = c.lashLineCurve,
            eyeWidthPx = c.eyeWidthPx,
        )
    }

    private fun lerpTransform(a: EyeTransform, b: EyeTransform, factor: Float): EyeTransform {
        return EyeTransform(
            position = a.position + (b.position - a.position) * factor,
            rotation = lerpQuaternion(a.rotation, b.rotation, factor),
            scale = a.scale + (b.scale - a.scale) * factor,
            opennessRatio = b.opennessRatio,
            lashLineCurve = b.lashLineCurve,
            eyeWidthPx = b.eyeWidthPx,
        )
    }

    private fun lerpQuaternion(a: Quaternion, b: Quaternion, factor: Float): Quaternion {
        val dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
        val al = if (dot < 0f) Quaternion(-b.x, -b.y, -b.z, -b.w) else b
        val x = a.x + (al.x - a.x) * factor
        val y = a.y + (al.y - a.y) * factor
        val z = a.z + (al.z - a.z) * factor
        val w = a.w + (al.w - a.w) * factor
        val lenSq = x * x + y * y + z * z + w * w
        if (lenSq <= 0f || !lenSq.isFinite()) return if (dot < 0f) al else b
        val inv = 1f / sqrt(lenSq)
        return Quaternion(x * inv, y * inv, z * inv, w * inv)
    }

    private fun length(v: Float3): Float = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)

    private companion object {
        /** Máxima extrapolación: 1.5× el intervalo entre muestras.
         * Reducido de 3.0×: con MediaPipe a ~20Hz (50ms/frame) y 3.0×,
         * se predecía 150ms hacia el futuro, causando overshoot visible
         * (pestañas "saltando"). Con 1.5× = ~75ms, justo lo suficiente para
         * compensar la latencia sin causar inestabilidad. */
        const val MAX_EXTRAPOLATION_FACTOR = 1.5f

        /** Límite de aceleración más conservador para evitar overshoot. */
        const val MAX_ACCEL = 5e-14f

        /** Más calentamiento antes de activar predicción, para evitar
         * saltos en los primeros frames tras detectar el rostro. */
        const val WARMUP_PUSHES = 5
    }
}
