package com.example.test_face.render

import kotlin.math.PI
import kotlin.math.abs

/**
 * Filtro One Euro (Casiez, Roussel & Vogel, "1€ Filter: A Simple Speed-based
 * Low-pass Filter for Noisy Input in Interactive Systems", CHI 2012) para
 * UNA señal escalar.
 *
 * Reemplaza la media móvil exponencial de alpha fijo que tenía este proyecto
 * antes (ver auditoría del motor, Hallazgo #5): un alpha fijo es un
 * compromiso imposible — bajo, da lag al mover rápido; alto, deja pasar el
 * jitter en reposo. Este filtro adapta su frecuencia de corte a la velocidad
 * instantánea de la señal: quieta, corta fuerte (sin jitter); moviéndose
 * rápido, corta poco (sin lag) — resuelve ambos requisitos a la vez, que es
 * matemáticamente imposible con un único alpha constante.
 *
 * [minCutoff]/[beta] son los únicos parámetros de comportamiento temporal
 * que quedan por afinar en dispositivo (reemplazan a `POSITION_LERP`/
 * `ROTATION_LERP`/`SCALE_LERP`) — a diferencia de `HEIGHT_OFFSET`/
 * `WIDTH_MULTIPLIER`/`WORLD_SCALE_X`, no compensan un error de proyección:
 * son la sensibilidad real del filtro, la misma calibración que cualquier
 * motor de tracking en producción expone.
 */
class OneEuroFilter(
    private val minCutoff: Float,
    private val beta: Float,
    private val dCutoff: Float = 1.0f,
) {
    private var initialized = false
    private var xPrev = 0f
    private var dxPrev = 0f
    private var tPrevNanos = 0L

    /** [tNanos] debe ser monótono creciente (p.ej. `System.nanoTime()`). */
    fun filter(x: Float, tNanos: Long): Float {
        if (!initialized) {
            initialized = true
            xPrev = x
            dxPrev = 0f
            tPrevNanos = tNanos
            return x
        }

        val elapsedNanos = (tNanos - tPrevNanos).coerceAtLeast(1L)
        val te = elapsedNanos / 1_000_000_000f
        tPrevNanos = tNanos

        // 1) Derivada de la señal, suavizada a una frecuencia de corte fija
        // (dCutoff) — es la estimación de "velocidad" que decide cuánto
        // abrir el corte de la propia señal en el paso 2.
        val dx = (x - xPrev) / te
        val edx = lowPass(dx, dxPrev, alpha(dCutoff, te))
        dxPrev = edx

        // 2) Corte adaptativo: a más velocidad, más alto el corte (menos
        // suavizado, menos lag). beta controla cuánto pesa la velocidad.
        val cutoff = minCutoff + beta * abs(edx)
        val filtered = lowPass(x, xPrev, alpha(cutoff, te))
        xPrev = filtered
        return filtered
    }

    fun reset() {
        initialized = false
    }

    private fun alpha(cutoff: Float, te: Float): Float {
        val tau = 1f / (2f * PI.toFloat() * cutoff)
        return 1f / (1f + tau / te)
    }

    private fun lowPass(x: Float, prevFiltered: Float, a: Float): Float = a * x + (1f - a) * prevFiltered
}
