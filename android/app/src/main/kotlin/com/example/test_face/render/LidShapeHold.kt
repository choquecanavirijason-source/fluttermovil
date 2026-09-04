package com.example.test_face.render

/**
 * Descriptores de FORMA del párpado superior, normalizados por el tamaño del
 * ojo y relativos al eje esquina-a-esquina — o sea, lo que describe "cómo es
 * este párpado" sin incluir dónde está ni cuán grande se ve en la imagen.
 *
 * ## Por qué existe (fix de parpadeo)
 *
 * Todo el pipeline de pestañas se reconstruía desde los landmarks del arco
 * del párpado superior EN CADA FRAME: el centroide (`meanX`/`meanY`), la
 * altura del anillo, la tangente ajustada y la curva de [LashLineCurve]. Al
 * parpadear, ese arco baja hasta juntarse con el párpado inferior, así que
 * las cuatro cantidades cambian a la vez — pero NO todas por el mismo
 * motivo, y ahí está la clave del arreglo:
 *
 *  - El **centroide baja** porque el borde del párpado REALMENTE baja. Eso
 *    es movimiento legítimo y hay que seguirlo: una extensión pegada al
 *    párpado baja con él. Por eso el centroide NO es parte de esta clase —
 *    se mide vivo siempre (ver [EyeAnchorCalculator]).
 *  - La **altura del anillo** cae a ~0, así que el término de elevación
 *    `height * heightOffset` del ancla se evapora — un salto hacia abajo
 *    EXTRA, encima del movimiento real del párpado.
 *  - La **tangente** por mínimos cuadrados pasa a ajustarse sobre una nube
 *    casi plana, o sea que su pendiente queda dominada por el ruido de
 *    ±1-2 px de cada landmark: la pestaña tiembla de orientación.
 *  - Y la **curva** del párpado se aplana y llega a INVERTIR su curvatura
 *    cuando el párpado se pliega, con lo que [LashMeshBender] deforma el
 *    abanico de fibras hacia el otro lado.
 *
 * Las últimas tres son las que desarmaban la pestaña al parpadear (se
 * aplastaba, temblaba y cambiaba de forma). Esas son las que se congelan.
 *
 * ## Cómo se arregla
 *
 * Mientras el ojo NO esté claramente abierto (ver [OpennessTracker.update]),
 * se dejan de medir estas cantidades y se reusan las últimas tomadas con el
 * ojo abierto. La clave para que eso no congele también el SEGUIMIENTO es
 * que sean adimensionales y relativas al eje del ojo:
 *
 *  - ese eje esquina-a-esquina se recalcula VIVO en cada frame (los dos
 *    cantos son las esquinas donde se juntan los párpados: prácticamente no
 *    se mueven al parpadear, a diferencia del arco),
 *  - `heightOverWidth` se multiplica por el ancho VIVO,
 *  - y `tangentResidualRad` se suma al ángulo VIVO de ese eje.
 *
 * Resultado: con el ojo cerrado la pestaña sigue rotando con la cabeza,
 * bajando con el párpado y escalando con la distancia — solo deja de
 * re-deducir su forma de unos puntos que en ese instante no describen un
 * párpado abierto.
 */
data class LidShape(
    /** `EyeLandmarks.height / EyeLandmarks.width` — la proporción del ojo,
     * de la que sale el término de elevación del ancla
     * ([LashStyleConfig.heightOffset]). El ancho NO colapsa al parpadear, así
     * que congelar la RAZÓN (y no la altura en píxeles) mantiene la elevación
     * correcta aunque la persona se acerque o se aleje con el ojo cerrado. */
    val heightOverWidth: Float,
    /** Ángulo de la tangente del párpado RELATIVO a la línea esquina-a-
     * esquina, en radianes y normalizado a `[-π, π]`. Relativo, no absoluto,
     * para que el roll de cabeza siga aplicándose vivo mientras esto está
     * congelado. Es también lo que [EyePlaneCalculator] consume como
     * residuo. */
    val tangentResidualRad: Float,
)

/**
 * Memoria por ojo de la última [LidShape] y la última [LashLineCurve]
 * medidas con el ojo abierto — ver el KDoc de [LidShape] para el problema
 * que resuelve.
 *
 * Una instancia por OJO (viven en [EyeModelSlot], igual que
 * [UpperLidFilter]/[OpennessTracker]): los dos ojos parpadean por separado,
 * y de hecho un guiño es exactamente el caso donde uno queda congelado y el
 * otro no.
 */
class LidShapeHold {

    /** Última forma medida con el ojo abierto, o `null` si todavía no hubo
     * ninguna (rostro recién detectado). El llamador debe tratar `null` como
     * "medí en vivo", nunca como error. */
    var shape: LidShape? = null
        private set

    /** Última curva del párpado ajustada con el ojo abierto — ver
     * [LashLineCurve]. Se conserva aparte de [shape] porque no es un puñado
     * de escalares sino el spline completo, y porque [LashMeshBender] la
     * consume directamente. */
    var curve: LashLineCurve? = null
        private set

    fun latchShape(measured: LidShape) {
        shape = measured
    }

    /** No-op con `null`: un frame sin curva ajustable (menos de 2 puntos
     * distinguibles) no debe BORRAR la última buena. */
    fun latchCurve(fitted: LashLineCurve?) {
        if (fitted != null) curve = fitted
    }

    /** Al perder el rostro — la próxima persona no debe heredar la forma del
     * párpado de la anterior. NO se llama al parpadear: conservar la forma
     * durante el parpadeo es justamente el punto de esta clase. */
    fun reset() {
        shape = null
        curve = null
    }
}
