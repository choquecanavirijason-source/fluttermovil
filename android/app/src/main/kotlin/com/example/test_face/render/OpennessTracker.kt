package com.example.test_face.render

/**
 * Decide cuánto atenuar (o si ocultar) la pestaña por parpadeo, con un
 * umbral RELATIVO al propio ojo de la persona en vez de una constante
 * absoluta.
 *
 * ## El problema que resuelve
 *
 * Antes se comparaba [EyeLandmarks.opennessRatio] (alto/ancho del ojo)
 * contra [RendererConfiguration.EYE_CLOSED_OPENNESS_THRESHOLD] = 0.12 y
 * `EYE_OPEN_...` = 0.22, fijos para todo el mundo. Pero esa relación depende
 * de la FORMA del ojo, no solo de cuánto lo abriste: un ojo redondo abierto
 * da ~0.35, y uno rasgado o encapotado bien abierto puede dar 0.15.
 *
 * Medido en dispositivo (log MESH_CALIB, 2026-09-03) sobre un usuario de ojo
 * rasgado: la relación oscilaba entre 0.108 y 0.198, o sea CRUZANDO el
 * umbral de cerrado (0.12) constantemente y sin llegar nunca al de abierto
 * (0.22). Consecuencia: la pestaña quedaba permanentemente atenuada y
 * parpadeaba entre visible y oculta — se veía en logcat como `hideSlot ->
 * OCULTO` alternando con `-> VISIBLE` cada decenas de milisegundos, con un
 * solo ojo (o sea el camino de parpadeo, no el de rostro perdido).
 *
 * ## Cómo
 *
 * Se mantiene una línea base por ojo: el valor de apertura que ESA persona
 * alcanza con el ojo abierto. Sube rápido (si ves un valor más alto, es que
 * el ojo está más abierto de lo que creías) y baja MUY lento, para que un
 * parpadeo no la arrastre hacia abajo — si bajara rápido, tras un par de
 * parpadeos la base sería la del ojo cerrado y no se ocultaría nunca.
 *
 * Los umbrales pasan a ser fracciones de esa base
 * ([RendererConfiguration.OPENNESS_CLOSED_FRACTION] /
 * `OPENNESS_OPEN_FRACTION`), así que se adaptan solos a cada forma de ojo.
 *
 * Durante el calentamiento (las primeras [RendererConfiguration.
 * OPENNESS_WARMUP_SAMPLES] muestras) no se atenúa nada: sin base confiable,
 * es preferible mostrar la pestaña de más que ocultarla al aparecer el
 * rostro.
 */
class OpennessTracker {

    private var baseline = 0f
    private var samples = 0

    /**
     * Devuelve el factor de atenuación en `[0,1]` para [ratio] (0 = ojo
     * cerrado, ocultar; 1 = completamente abierto), y actualiza la línea
     * base.
     */
    fun damping(ratio: Float): Float {
        if (!ratio.isFinite() || ratio <= 0f) return 0f

        // La base sube rápido y baja muy lento (ver KDoc).
        baseline = if (ratio > baseline) {
            baseline + (ratio - baseline) * RendererConfiguration.OPENNESS_BASELINE_RISE
        } else {
            baseline * RendererConfiguration.OPENNESS_BASELINE_DECAY
        }
        samples++

        if (samples < RendererConfiguration.OPENNESS_WARMUP_SAMPLES || baseline <= 1e-4f) {
            return 1f
        }

        val closed = baseline * RendererConfiguration.OPENNESS_CLOSED_FRACTION
        val open = baseline * RendererConfiguration.OPENNESS_OPEN_FRACTION
        if (open - closed <= 1e-6f) return 1f

        val t = ((ratio - closed) / (open - closed)).coerceIn(0f, 1f)
        // Mismo smoothstep que usaba el cálculo con umbrales fijos.
        return t * t * (3f - 2f * t)
    }

    /** Al perder el rostro: la próxima persona (o la misma a otra distancia)
     * no debe heredar esta línea base. */
    fun reset() {
        baseline = 0f
        samples = 0
    }
}
