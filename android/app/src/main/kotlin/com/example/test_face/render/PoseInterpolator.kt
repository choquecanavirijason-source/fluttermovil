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
        // Tope en TIEMPO, no en cantidad de intervalos. `t` es "cuántos
        // intervalos entre muestras predecir", así que un tope expresado en
        // intervalos significa cosas distintas en cada dispositivo: 1.5×
        // son 50 ms con MediaPipe a 30 Hz y 90 ms a 17 Hz. Lo que realmente
        // limita cuánto se puede predecir es el TIEMPO — a partir de cierto
        // horizonte la suposición de velocidad constante deja de valer, y eso
        // no depende de a qué ritmo entregue resultados el dispositivo.
        val maxT = MAX_EXTRAPOLATION_NANOS / dt1
        val t = (elapsed / dt1).coerceIn(0f, maxT)

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

        // ── Freno del término cuadrático ────────────────────────────────
        // ANTES: `MAX_ACCEL = 5e-14`, un tope ABSOLUTO sobre la aceleración.
        // El problema son sus unidades — "unidades de mundo de Filament por
        // nanosegundo al cuadrado": para un movimiento normal de cabeza salen
        // del orden de 1e-17, o sea que ese tope estaba unas mil veces por
        // encima de cualquier valor real y NUNCA frenaba nada. Y el término
        // cuadrático crece con Δt², así que sin freno efectivo puede superar
        // al lineal y mandar el modelo lejos — el "pestañas saltando" que en
        // su momento obligó a recortar el horizonte de extrapolación (ver
        // [MAX_EXTRAPOLATION_NANOS]), o sea tapando el síntoma en vez de la
        // causa.
        //
        // Ahora el límite es RELATIVO: la corrección cuadrática no puede
        // aportar más de [ACCEL_TERM_MAX_RATIO] veces lo que ya aporta el
        // término lineal. Al ser adimensional no depende de la escala del
        // mundo, ni de la distancia de la cara, ni de la resolución — no hay
        // ninguna constante que calibrar en dispositivo. La predicción queda
        // acotada para cualquier Δt, que es justamente lo que permite
        // extrapolar más lejos sin volver a los saltos.
        val velocityTerm = v1 * tScaled
        val accelTerm = accel * (0.5f * tScaled * tScaled)
        val accelLen = length(accelTerm)
        val maxAccelLen = length(velocityTerm) * ACCEL_TERM_MAX_RATIO
        val limitedAccelTerm = if (accelLen > maxAccelLen && accelLen > 1e-30f) {
            accelTerm * (maxAccelLen / accelLen)
        } else {
            accelTerm
        }
        val predictedPos = c.position + velocityTerm + limitedAccelTerm

        // Posición, rotación y escala se extrapolan con EL MISMO `t`.
        //
        // Se probó darle a la posición un horizonte mayor que a rotación y
        // escala, con el argumento de que el retraso de posición es el que se
        // nota. Fue un error: los tres describen LA MISMA pose. Con
        // horizontes distintos, en cuanto la persona se mueve rápido —
        // acercarse a la cámara, bajar la cabeza — la posición se adelanta
        // más que la escala, y el modelo termina donde va a estar la cara
        // pero con el tamaño que la cara tenía antes. Se desacoplan justo
        // durante el movimiento, que es exactamente cuando tienen que estar
        // de acuerdo; reportado en dispositivo como que la pestaña "se
        // desconfigura" al acercarse y al mirar hacia abajo.
        //
        // Escala: lineal (cuadrática en escala produce overshoots visuales).
        val scale = c.scale + (c.scale - b.scale) * t

        val rotation = lerpQuaternion(b.rotation, c.rotation, 1f + t)

        return EyeTransform(
            position = predictedPos,
            rotation = rotation,
            scale = scale,
            opennessRatio = c.opennessRatio,
            lashLineCurve = c.lashLineCurve,
            eyeWidthPx = c.eyeWidthPx,
            lidShapeTrusted = c.lidShapeTrusted,
        )
    }

    /** [factor] es `1 + t`, el mismo para los tres componentes — ver la nota
     * sobre desacople en [quadraticPredict]. */
    private fun lerpTransform(a: EyeTransform, b: EyeTransform, factor: Float): EyeTransform {
        return EyeTransform(
            position = a.position + (b.position - a.position) * factor,
            rotation = lerpQuaternion(a.rotation, b.rotation, factor),
            scale = a.scale + (b.scale - a.scale) * factor,
            opennessRatio = b.opennessRatio,
            lashLineCurve = b.lashLineCurve,
            eyeWidthPx = b.eyeWidthPx,
            lidShapeTrusted = b.lidShapeTrusted,
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

    /** Público (no `private`) para que [LashRenderer] pueda incluir el tope
     * en el log del presupuesto de latencia — ver PRESUPUESTO_LATENCIA. */
    companion object {
        /**
         * Horizonte máximo de predicción, en NANOSEGUNDOS hacia el futuro.
         * Uno solo para posición, rotación y escala — ver la nota sobre
         * desacople en [quadraticPredict].
         *
         * ## Por qué en tiempo y no en intervalos
         *
         * Antes era `MAX_EXTRAPOLATION_FACTOR`, un múltiplo del intervalo
         * entre resultados de MediaPipe. Pero ese intervalo depende del
         * dispositivo: `1.5×` son 50 ms con MediaPipe a 30 Hz y 90 ms a 17 Hz,
         * o sea que el mismo número daba comportamientos muy distintos según
         * el teléfono. Lo que en realidad limita cuánto se puede predecir es
         * el TIEMPO: más allá de cierto horizonte la suposición de velocidad
         * constante deja de valer y la predicción se pasa. Eso es una
         * propiedad de cómo se mueve una cabeza, no del ritmo del dispositivo.
         *
         * ## Por qué 150 ms
         *
         * Este tope tiene que dar lugar al PRESUPUESTO DE LATENCIA COMPLETO
         * que arma [LashRenderer.writeInterpolatedPose], si no recorta
         * justamente la compensación que se acaba de agregar y el atraso
         * vuelve. Sumando: ~51 ms de pipeline+composición, hasta 45 ms del
         * One Euro de pose ([RendererConfiguration.FILTER_DELAY_COMPENSATION_MAX_NANOS]),
         * 35 ms del lead de [PoseFollower], más `(ahora − última muestra)`,
         * que llega a ~40 ms justo antes del resultado siguiente. Eso da un
         * pico de ~170 ms; 150 cubre casi todo el rango sin dejar que el peor
         * caso mande.
         *
         * Era 70 ms, elegido para no predecir tan lejos como para que un
         * frenazo de cabeza produjera un salto visible. Ese motivo ya no
         * aplica igual, por dos cambios posteriores: [PoseFollower] reparte
         * en el tiempo cualquier corrección brusca —incluido un sobrepaso de
         * predicción— así que un frenazo se resuelve como un asentamiento
         * suave; y [MotionGate] directamente no dibuja la pestaña mientras la
         * cabeza va rápido, que es cuando el sobrepaso sería mayor. O sea que
         * el error de extrapolación solo se ve con la cara moviéndose LENTO,
         * donde `velocidad × horizonte` es chico por el otro factor.
         *
         * CALIBRACIÓN: si al frenar de golpe la pestaña se pasa de largo de
         * forma visible, bajar de a 20 ms. Es el primer valor a tocar si
         * aparece sobrepaso.
         */
        const val MAX_EXTRAPOLATION_NANOS = 150_000_000f

        /** Cuánto puede aportar como máximo el término cuadrático respecto al
         * lineal, en [quadraticPredict]. Adimensional a propósito — ver la
         * nota extensa ahí sobre por qué reemplaza al tope absoluto
         * `MAX_ACCEL`, que nunca llegó a actuar. */
        const val ACCEL_TERM_MAX_RATIO = 0.5f

        /** Más calentamiento antes de activar predicción, para evitar
         * saltos en los primeros frames tras detectar el rostro. */
        const val WARMUP_PUSHES = 5
    }
}
