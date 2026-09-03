package com.example.test_face.render

/**
 * Suavizado temporal de los puntos del arco del párpado superior, ANTES de
 * que [LashLineCurve.fit] construya la curva a la que se dobla la malla.
 *
 * ## Por qué existe
 *
 * [EyeTrackingFilter] ya filtra la pose rígida (posición/rotación/escala) con
 * [OneEuroFilter], pero NO tocaba estos puntos: `LashLineCurve` se
 * reconstruía en cada frame desde los landmarks CRUDOS de MediaPipe. O sea
 * que la parte que hace que la pestaña se "adapte" al párpado era justamente
 * la única sin filtrar del pipeline.
 *
 * El efecto visible es distinto al del jitter de pose: la pestaña puede
 * seguir bien la cabeza y aun así vibrar de FORMA, porque el ruido de
 * ±1-2 px de cada landmark entra directo en la curva. Con un ojo de ~46 px de
 * ancho en la imagen de análisis (640x480), esos 1-2 px son 15-30% del
 * espaciado entre puntos consecutivos — no es ruido despreciable.
 *
 * ## Por qué One Euro y no una media móvil
 *
 * Mismo argumento que [OneEuroFilter] documenta para la pose: un alpha fijo
 * obliga a elegir entre jitter en reposo o lag al mover. Acá importa
 * especialmente porque un lag en la FORMA se ve como la pestaña "arrastrando"
 * detrás del párpado al parpadear, que es más molesto que un poco de jitter.
 *
 * ## Escala de los parámetros
 *
 * OJO: estos puntos están en PÍXELES DE IMAGEN (magnitudes de 0 a 640), no en
 * unidades de mundo (~0.01-0.6) como los de [EyeTrackingFilter]. El término
 * `beta * |velocidad|` de One Euro es dependiente de escala, así que reusar
 * `POSITION_MIN_CUTOFF`/`POSITION_BETA` daría un comportamiento
 * completamente distinto. Por eso tiene sus propias constantes — ver
 * [RendererConfiguration.LID_POINT_MIN_CUTOFF].
 *
 * Una instancia por OJO (viven en [EyeModelSlot]), porque el estado del
 * filtro es por punto y los dos ojos se mueven independientemente.
 */
class UpperLidFilter {

    /** Dos filtros (x, y) por punto del arco. Se crean en el primer frame y
     * se recrean si cambia la cantidad de puntos — ver [apply]. */
    private var filtersX: Array<OneEuroFilter> = emptyArray()
    private var filtersY: Array<OneEuroFilter> = emptyArray()

    /**
     * Devuelve los puntos suavizados. [tNanos] debe ser monótono creciente
     * (`System.nanoTime()`).
     *
     * Si la cantidad de puntos cambia respecto al frame anterior, se
     * reconstruyen los filtros y este frame pasa sin suavizar: los filtros
     * son por ÍNDICE, así que reusarlos con otra cantidad mezclaría el
     * historial de un punto del párpado con el de otro distinto. Pasa al
     * detectar el rostro por primera vez y en el camino de respaldo de
     * [EyeLandmarks.from] (anillo incompleto), no en operación normal.
     */
    fun apply(points: List<ImagePoint>, tNanos: Long): List<ImagePoint> {
        if (points.isEmpty()) return points
        if (filtersX.size != points.size) {
            reset(points.size)
            return points
        }
        return List(points.size) { i ->
            ImagePoint(
                x = filtersX[i].filter(points[i].x, tNanos),
                y = filtersY[i].filter(points[i].y, tNanos),
            )
        }
    }

    /** Limpia el historial — al perder el rostro, para que al redetectarlo no
     * arrastre la forma del párpado de hace varios segundos. */
    fun reset() {
        filtersX = emptyArray()
        filtersY = emptyArray()
    }

    private fun reset(size: Int) {
        filtersX = Array(size) {
            OneEuroFilter(
                RendererConfiguration.LID_POINT_MIN_CUTOFF,
                RendererConfiguration.LID_POINT_BETA,
                RendererConfiguration.ONE_EURO_D_CUTOFF,
            )
        }
        filtersY = Array(size) {
            OneEuroFilter(
                RendererConfiguration.LID_POINT_MIN_CUTOFF,
                RendererConfiguration.LID_POINT_BETA,
                RendererConfiguration.ONE_EURO_D_CUTOFF,
            )
        }
    }
}
