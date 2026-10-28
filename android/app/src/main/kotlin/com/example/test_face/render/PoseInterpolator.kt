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
        historyGeneration++
    }

    // ── Mezcla de corrección al llegar una muestra nueva (ver [blend]) ────
    // Todo esto lo toca SOLO el hilo principal (desde [sample]), salvo
    // [historyGeneration], que lo incrementan [reset]/[dropHistory] desde el
    // hilo del resultado para anular una corrección en curso.
    @Volatile private var historyGeneration = 0
    private var seenGeneration = -1
    private var lastOutput: EyeTransform? = null
    private var lastOutputNanos = 0L
    private var lastOutputLatest: Sample? = null
    private var correctionPos = Float3()
    private var correctionScale = Float3()
    private var correctionRot = IDENTITY
    private var correctionStartNanos = 0L

    /**
     * Descarta las muestras ANTERIORES a un hueco de tracking, sin volver a
     * calentamiento. Se llama justo antes del primer [push] tras recuperar el
     * rostro (ver [LashRenderer.onFaceResult]).
     *
     * Sin esto, la primera muestra nueva se combinaba con las de antes del
     * hueco: la velocidad salía de "todo lo recorrido durante la retención"
     * y la aceleración de compararla contra la de antes (≈ 0 si la persona
     * estaba quieta) — y la predicción cuadrática lanzaba la pestaña más
     * allá del ojo justo al recuperar. Con el historial vacío, [sample]
     * devuelve la muestra tal cual y la predicción se rearma con las
     * siguientes (lineal con 2, cuadrática con 3). A diferencia de [reset],
     * no hace falta esperar [WARMUP_PUSHES]: el filtro aguas arriba no se
     * reseteó, así que las muestras nuevas ya llegan limpias.
     */
    fun dropHistory() {
        s0 = null
        s1 = null
        historyGeneration++
    }

    /**
     * Pose predicha para [nowNanos], compensando [latencyNanos] de pipeline.
     * Con 3 muestras usa predicción cuadrática (velocidad + aceleración);
     * con 2 usa lineal; con 1 devuelve la muestra directa. Al cambiar de
     * muestra, la corrección se reparte en el tiempo — ver [blend].
     */
    fun sample(nowNanos: Long, latencyNanos: Long = 35_000_000L): EyeTransform? {
        val latest = s2 ?: return null
        val predicted = predict(latest, nowNanos, latencyNanos)
        return blend(predicted, latest, nowNanos)
    }

    /**
     * MEZCLA DE CORRECCIÓN al reemplazar la muestra.
     *
     * Entre resultados la pose se EXTRAPOLA desde la última muestra. Cuando
     * llega la siguiente, la predicción pasa a calcularse desde ella, y la
     * diferencia entre las dos predicciones (el error de la vieja) aparecía
     * de golpe en el objetivo — a 8-10 resultados/s, un escalón cada
     * ~100-120 ms. [PoseFollower] lo suavizaba con su τ de 35 ms, pero ese τ
     * se eligió para jitter, no para escalones de este tamaño.
     *
     * Acá, en el primer vsync con muestra nueva se guarda la diferencia
     * `salida anterior − predicción nueva` (posición, rotación y escala) y se
     * suma a la predicción nueva decayendo como `e^(−Δt/τ)`, con
     * τ = [SAMPLE_BLEND_TAU_NANOS]. La salida arranca exactamente donde
     * estaba y converge a la trayectoria nueva; la VELOCIDAD nueva se aplica
     * de inmediato (la corrección es un desplazamiento que se apaga, no un
     * filtro sobre la pose), así que no agrega atraso al movimiento.
     *
     * No se mezcla tras [reset]/[dropHistory] (aparición o recuperación del
     * rostro, que ya maneja [PoseFollower.softenRecovery]) ni durante el
     * calentamiento. `sample_blend=off` en perf_flags lo desactiva.
     */
    private fun blend(predicted: EyeTransform, latest: Sample, nowNanos: Long): EyeTransform {
        val generation = historyGeneration
        val enabled = com.example.test_face.PerfFlags.config.sampleBlend &&
            pushesSinceReset >= WARMUP_PUSHES && generation == seenGeneration
        seenGeneration = generation
        // Una salida de hace más de [STALE_OUTPUT_NANOS] (nodo oculto, sin
        // vsync que pidiera pose) no es "donde estaba" la pestaña en pantalla:
        // mezclar desde ahí traería una pose vieja.
        val previous = lastOutput?.takeIf { nowNanos - lastOutputNanos <= STALE_OUTPUT_NANOS }
        lastOutputNanos = nowNanos
        if (latest !== lastOutputLatest) {
            lastOutputLatest = latest
            if (enabled && previous != null) {
                correctionPos = previous.position - predicted.position
                correctionScale = previous.scale - predicted.scale
                correctionRot = multiply(previous.rotation, conjugate(alignTo(predicted.rotation, previous.rotation)))
                correctionStartNanos = nowNanos
            } else {
                correctionPos = Float3()
                correctionScale = Float3()
                correctionRot = IDENTITY
            }
        }
        if (!enabled) {
            lastOutput = predicted
            return predicted
        }
        val decay = kotlin.math.exp(-(nowNanos - correctionStartNanos).toFloat() / SAMPLE_BLEND_TAU_NANOS)
        val out = if (decay < 1e-3f) {
            predicted
        } else {
            predicted.copy(
                position = predicted.position + correctionPos * decay,
                scale = predicted.scale + correctionScale * decay,
                rotation = multiply(lerpQuaternion(IDENTITY, correctionRot, decay), predicted.rotation),
            )
        }
        lastOutput = out
        return out
    }

    private fun predict(latest: Sample, nowNanos: Long, latencyNanos: Long): EyeTransform {
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
        val flags = com.example.test_face.PerfFlags.config
        val cap = capFor(latencyNanos, flags.forwardAge)
        lastCapNanos = cap
        lastSampleSaturated = elapsed > cap
        val t = effectiveElapsed(elapsed, cap, flags.softExtrapolation) / dt1

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

    /** `true` si el último [sample] pidió más allá del tope vigente
     * ([lastCapNanos]) — DIAGNÓSTICO (`extrap_saturada` en
     * `TIEMPOS_ETAPAS`). Solo lo usa el hilo principal. */
    var lastSampleSaturated = false
        private set

    /** Tope usado en el último [sample] (ver [capFor]), para el log
     * `PRESUPUESTO_LATENCIA`. Solo el hilo principal. */
    var lastCapNanos = MAX_EXTRAPOLATION_NANOS
        private set

    /**
     * TOPE DINÁMICO de extrapolación para un horizonte base [horizonNanos].
     *
     * Lo que se pide extrapolar es `horizonte + (ahora − última muestra)`:
     * arranca en H cuando llega un resultado y crece durante el intervalo
     * hasta el siguiente (~110 ms a 8-10 resultados/s). Con `forward_age=on`
     * H ya incluye la antigüedad previa al envío (~220-230 ms medidos), así
     * que un tope FIJO de 250 ms se alcanzaba a los ~30 ms de cada
     * intervalo (`extrap_saturada=116/120`) y el resto del intervalo la
     * pose quedaba frenada: el delay volvía.
     *
     * Por eso el tope sigue al horizonte: `H + `[INTERVAL_MARGIN_NANOS],
     * nunca menos que [MAX_EXTRAPOLATION_NANOS] (el piso de siempre) ni más
     * que [ABSOLUTE_MAX_EXTRAPOLATION_NANOS]. Ese techo existe porque H
     * viene de mediciones: un pico de latencia (GC, frame retenido) no debe
     * habilitar extrapolaciones de medio segundo, que con una cabeza que
     * frena serían un sobrepaso grande. Con `forward_age=off` el tope es el
     * fijo de antes.
     */
    private fun capFor(horizonNanos: Long, forwardAge: Boolean): Float {
        if (!forwardAge) return MAX_EXTRAPOLATION_NANOS
        return (horizonNanos.toFloat() + INTERVAL_MARGIN_NANOS)
            .coerceIn(MAX_EXTRAPOLATION_NANOS, ABSOLUTE_MAX_EXTRAPOLATION_NANOS)
    }

    /**
     * Cuánto se extrapola de verdad para un pedido de [elapsed] ns.
     *
     * [cap] es el tope vigente ([capFor]).
     *
     * `hard`: tope duro en [cap]. Medido en el Note 10+
     * el horizonte (168-221 ms) ya supera el tope apenas llega un resultado,
     * así que `t` quedaba fijo en el tope durante TODO el intervalo hasta el
     * siguiente (145-290 ms): la pose no avanzaba entre resultados aunque
     * se escribía en cada vsync — se congelaba y saltaba.
     *
     * `soft` (default): hasta el tope es igual; pasado el tope el avance
     * sigue con velocidad que decae exponencialmente,
     * `tope + τ·(1 − e^(−exceso/τ))`, con τ = [SOFT_EXTRAPOLATION_TAIL_NANOS].
     * La pose se sigue moviendo a tasa de pantalla y frena suave, sin
     * esquina; lo máximo que puede pasarse del tope es τ — el sobrepaso al
     * frenar la cabeza queda acotado a `velocidad·τ`.
     */
    private fun effectiveElapsed(elapsed: Float, cap: Float, soft: Boolean): Float {
        if (elapsed <= 0f) return 0f
        if (elapsed <= cap) return elapsed
        if (!soft) return cap
        val excess = elapsed - cap
        return cap +
            SOFT_EXTRAPOLATION_TAIL_NANOS * (1f - kotlin.math.exp(-excess / SOFT_EXTRAPOLATION_TAIL_NANOS))
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
            normalizedOpenness = c.normalizedOpenness,
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
            normalizedOpenness = b.normalizedOpenness,
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

    /** Hamilton `a·b` (aplica `b` y después `a`). */
    private fun multiply(a: Quaternion, b: Quaternion): Quaternion = Quaternion(
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    )

    private fun conjugate(q: Quaternion): Quaternion = Quaternion(-q.x, -q.y, -q.z, q.w)

    /** [q] o `−q` (misma rotación), el que esté en el hemisferio de [ref]:
     * así la diferencia es el giro CORTO entre las dos. */
    private fun alignTo(q: Quaternion, ref: Quaternion): Quaternion {
        val dot = q.x * ref.x + q.y * ref.y + q.z * ref.z + q.w * ref.w
        return if (dot < 0f) Quaternion(-q.x, -q.y, -q.z, -q.w) else q
    }

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
         * ## 250 ms (2026-10-28)
         *
         * Con 150 ms el Note 10+ marcó `extrap_saturada=120/120`: el
         * horizonte medido (pipeline ~85-100 ms + One Euro + lead del
         * seguidor) más el tiempo desde la última muestra (hasta 100-120 ms,
         * con MediaPipe a 8-10 resultados/s) supera el tope en TODOS los
         * vsync, y la pose rígida quedaba frenada antes de la muestra
         * siguiente. 250 cubre ese rango; lo que se pase sigue por la cola
         * suave ([SOFT_EXTRAPOLATION_TAIL_NANOS]). El sobrepaso al frenar
         * crece con el tope — lo reparte la mezcla de [blend] al llegar la
         * muestra siguiente.
         *
         * ## Por qué era 150 ms
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
        const val MAX_EXTRAPOLATION_NANOS = 250_000_000f

        /** Margen del tope dinámico sobre el horizonte ([capFor]): cubre el
         * intervalo entre resultados medido (~110 ms) con algo de holgura.
         * Si `extrap_saturada` sigue alto en giros continuos y los
         * resultados llegan más espaciados, subirlo hacia ese intervalo. */
        const val INTERVAL_MARGIN_NANOS = 120_000_000f

        /** Techo absoluto del tope dinámico ([capFor]). Con H ≈ 220-230 ms
         * el tope queda en ~340-350 ms, por debajo; esto solo frena picos
         * de latencia medida. CALIBRACIÓN: si al frenar de golpe la pestaña
         * se pasa de largo, bajar este techo de a 25 ms. */
        const val ABSOLUTE_MAX_EXTRAPOLATION_NANOS = 400_000_000f

        /** τ de la cola de `extrapolation=soft` (ver [effectiveElapsed]):
         * cuánto más allá del tope puede llegar a avanzar la pose, como
         * máximo. Más alto = más movimiento entre resultados y más sobrepaso
         * al frenar; más bajo = se parece más al tope duro.
         *
         * La velocidad pasado el tope cae como `e^(−exceso/τ)`. Historia:
         * 80 → 120 ms (que la inercia durara todo el intervalo entre
         * resultados) → 80 ms (2026-10-28): con 120 la predicción seguía
         * empujando de más al frenar la cabeza de golpe. Con el horizonte
         * ahora compensando la antigüedad previa al envío, se satura más y
         * esta cola pesa más — por eso conviene la corta. */
        const val SOFT_EXTRAPOLATION_TAIL_NANOS = 80_000_000f

        /** τ de la mezcla de corrección de [blend]. 30 ms (era 40): el
         * escalón queda en ~2 % a los 120 ms, antes de la muestra
         * siguiente, y sigue siendo ~2 vsync, así que el reemplazo no se ve
         * como salto. Más alto = más suave pero la pose tarda más en
         * alinearse con el dato nuevo. SIN CALIBRAR en dispositivo. */
        const val SAMPLE_BLEND_TAU_NANOS = 30_000_000f

        /** Ver la guarda de salida vieja en [blend]: ~6 vsync a 60 Hz. */
        private const val STALE_OUTPUT_NANOS = 100_000_000L

        private val IDENTITY = Quaternion(0f, 0f, 0f, 1f)

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
