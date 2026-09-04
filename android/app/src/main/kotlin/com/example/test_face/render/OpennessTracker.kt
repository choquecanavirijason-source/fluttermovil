package com.example.test_face.render

/**
 * Decide, con un umbral RELATIVO al propio ojo de la persona en vez de una
 * constante absoluta, si el ojo está lo bastante abierto como para confiar
 * en la geometría del párpado de este frame.
 *
 * ## Qué NO decide (2026-09-04)
 *
 * Ya no decide si la pestaña se ve. Antes devolvía un factor continuo en
 * `[0,1]` con el que [LashRenderer] MULTIPLICABA LA ESCALA del modelo y, al
 * llegar a cero, lo ocultaba: al parpadear la pestaña se encogía hacia cero
 * y desaparecía. Las dos cosas están mal para este producto:
 *
 *  - una extensión real no se achica al cerrar el ojo, y
 *  - con el ojo CERRADO es justamente cuando más se ve una extensión —
 *    ocultarla ahí es lo contrario de lo que la usuaria quiere ver al
 *    probarse un diseño.
 *
 * Ahora la pestaña se dibuja siempre que haya rostro (solo [LashRenderer.
 * onFaceLost] la oculta), y lo único que sale de acá es si la FORMA del
 * párpado de este frame es confiable — ver [LidShape].
 *
 * ## El problema del umbral (por qué es relativo)
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
 * (0.22).
 *
 * Se mantiene una línea base por ojo: el valor de apertura que ESA persona
 * alcanza con el ojo abierto. Sube rápido (si ves un valor más alto, es que
 * el ojo está más abierto de lo que creías) y baja MUY lento, para que un
 * parpadeo no la arrastre hacia abajo — si bajara rápido, tras un par de
 * parpadeos la base sería la del ojo cerrado y el tracker no detectaría
 * ningún parpadeo más. Los umbrales pasan a ser fracciones de esa base
 * ([RendererConfiguration.OPENNESS_CLOSED_FRACTION] /
 * `OPENNESS_OPEN_FRACTION`), así que se adaptan solos a cada forma de ojo.
 *
 * Durante el calentamiento (las primeras [RendererConfiguration.
 * OPENNESS_WARMUP_SAMPLES] muestras) se reporta el ojo como abierto: sin
 * base confiable es preferible medir la forma de más que congelarla en la
 * primera forma que se vea al aparecer el rostro.
 *
 * ## Histéresis
 *
 * La salida tiene DOS umbrales (uno para dejar de confiar y otro más alto
 * para volver a confiar) para que no oscile frame a frame en la frontera —
 * ese chattering ya se vio en logcat en la versión anterior, como
 * `hideSlot -> OCULTO` alternando con `-> VISIBLE` cada decenas de
 * milisegundos.
 */
class OpennessTracker {

    private var baseline = 0f
    private var samples = 0
    private var shapeTrusted = true

    /**
     * Actualiza la línea base con [ratio] (la apertura de ESTE frame, ya
     * corregida por escorzo — ver
     * [FaceRenderPipeline.foreshorteningCorrectedOpenness]) y devuelve si se
     * puede confiar en la geometría del párpado de este frame: `true` = medir
     * la forma en vivo, `false` = reusar la última buena ([LidShapeHold]).
     *
     * Debe llamarse EXACTAMENTE UNA VEZ por frame y por ojo: muta la línea
     * base y el estado de la histéresis.
     */
    fun update(ratio: Float): Boolean {
        if (!ratio.isFinite() || ratio <= 0f) {
            shapeTrusted = false
            return false
        }

        // La base sube rápido y baja muy lento (ver KDoc).
        baseline = if (ratio > baseline) {
            baseline + (ratio - baseline) * RendererConfiguration.OPENNESS_BASELINE_RISE
        } else {
            baseline * RendererConfiguration.OPENNESS_BASELINE_DECAY
        }
        samples++

        if (samples < RendererConfiguration.OPENNESS_WARMUP_SAMPLES || baseline <= 1e-4f) {
            shapeTrusted = true
            return true
        }

        val closed = baseline * RendererConfiguration.OPENNESS_CLOSED_FRACTION
        val open = baseline * RendererConfiguration.OPENNESS_OPEN_FRACTION
        // Apertura normalizada: 0 = cerrado, 1 = completamente abierto. Un
        // ojo en reposo se clampea a 1 con margen de sobra (ratio ≈ baseline
        // da 2.33 antes del clamp), así que sólo baja de 1 cuando el ojo
        // realmente se está cerrando.
        val t = if (open - closed <= 1e-6f) 1f else ((ratio - closed) / (open - closed)).coerceIn(0f, 1f)

        // Histéresis: confiando, hace falta caer por debajo del umbral BAJO
        // para dejar de confiar; sin confiar, hace falta superar el ALTO.
        shapeTrusted = if (shapeTrusted) {
            t > RendererConfiguration.SHAPE_TRUST_DROP_BELOW
        } else {
            t > RendererConfiguration.SHAPE_TRUST_RESTORE_ABOVE
        }
        return shapeTrusted
    }

    /**
     * Al perder el rostro: la próxima persona (o la misma a otra distancia)
     * no debe heredar esta línea base.
     *
     * OJO — NO llamar al parpadear. Hasta el fix de 2026-09-04 esto se
     * llamaba desde `LashRenderer.hideSlot`, que se usaba TANTO para rostro
     * perdido COMO para ojo cerrado: cada parpadeo borraba la línea base de
     * la persona y volvía a meter al tracker en calentamiento, así que
     * durante ~15 muestras (≈0.5 s) se forzaba "abierto" mientras el ojo
     * apenas se estaba reabriendo, y la base nueva se aprendía de valores de
     * ojo medio cerrado. O sea que el umbral quedaba peor calibrado un poco
     * más después de cada parpadeo — la degradación progresiva que se veía
     * en dispositivo.
     */
    fun reset() {
        baseline = 0f
        samples = 0
        shapeTrusted = true
    }
}
