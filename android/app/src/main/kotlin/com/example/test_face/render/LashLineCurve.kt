package com.example.test_face.render

import kotlin.math.abs

/**
 * Curva del párpado superior real ("Upper Lash Line"), en un sistema de
 * coordenadas local alineado con la tangente promedio del párpado — la
 * misma que ya usa [EyePlaneCalculator] para el residual de rotación. Por
 * eso [LashLineCurve] captura SOLO la curvatura ADICIONAL respecto a esa
 * inclinación promedio, sin duplicar la rotación que el transform rígido
 * ([EyeTransformCalculator]) ya aplica.
 *
 * CAMBIO 2026-08-10 (de parábola aproximada a spline exacto): hasta acá esta
 * clase ajustaba una PARÁBOLA por mínimos cuadrados — una aproximación que
 * en general NO pasa exactamente por ninguno de los 8 landmarks reales del
 * párpado, solo captura la tendencia general. El usuario pidió explícitamente
 * que el modelo 3D siga "la forma de esta línea tal cual" señalando la
 * polilínea verde del debug painter ([LidLandmarkDebugPainter], línea que
 * conecta los 8 puntos reales del párpado superior) — no una aproximación.
 * Ahora [fit] construye un spline de Hermite cúbico que interpola
 * EXACTAMENTE los 8 puntos, con continuidad C1 en cada nodo interno (sin
 * los quiebres que tendría conectar los puntos con segmentos rectos) — es
 * la curva suave más simple que puede pasar por todos los puntos reales sin
 * reintroducir el bug de "pico/pliegue" ya corregido (ver sección 5.6 del
 * doc, sobre discontinuidad de derivada en el borde del ajuste).
 *
 * CAMBIO 2026-08-10 (tangentes monótonas, sin overshoot): las tangentes ya
 * no son Catmull-Rom puro (diferencia centrada) sino el limitador de
 * Fritsch-Carlson (ver [monotoneTangents]) — garantiza que la curva nunca
 * "se pasa" por encima/debajo de dos landmarks consecutivos entre ellos,
 * incluso donde la curvatura del párpado cambia de signo entre segmentos
 * (el caso donde Catmull-Rom puro sí puede overshootear).
 *
 * `deviationAt(localX)` da el desvío perpendicular (en píxeles de imagen) de
 * la curva real respecto a la línea recta promedio, en el punto `localX`
 * (distancia proyectada desde el ancla a lo largo de la tangente del
 * párpado).
 */
class LashLineCurve private constructor(
    /** Nodos (localX, localY), ordenados por localX estrictamente creciente
     * — ver [fit]. Los mismos 8 puntos reales del párpado, sin aproximar. */
    private val nodeX: FloatArray,
    private val nodeY: FloatArray,
    /** Tangente (dy/dx) en cada nodo, limitada con Fritsch-Carlson para
     * garantizar monotonía por tramo (sin overshoot) — ver
     * [Companion.monotoneTangents]. */
    private val nodeSlope: FloatArray,
) {
    private val minLocalX: Float get() = nodeX[0]
    private val maxLocalX: Float get() = nodeX[nodeX.size - 1]

    /** Dentro de `[minLocalX, maxLocalX]`: el spline de Hermite cúbico,
     * exacto en los nodos. Más allá: se sostiene con el valor/pendiente del
     * borde, con la pendiente decayendo suavemente a cero (mismo mecanismo
     * de falloff C1-continuo que ya tenía la versión de parábola — ver nota
     * de clase y [slopeAt]), para que nunca explote lejos de datos reales. */
    fun deviationAt(localX: Float): Float {
        if (localX <= minLocalX || localX >= maxLocalX) {
            val edge = localX.coerceIn(minLocalX, maxLocalX)
            val edgeIdx = if (localX <= minLocalX) 0 else nodeX.size - 1
            val edgeVal = nodeY[edgeIdx]
            val edgeSlope = nodeSlope[edgeIdx]
            val falloffDist = falloffDistancePx()
            val signedDist = localX - edge
            val u = (abs(signedDist) / falloffDist).coerceIn(0f, 1f)
            // Misma integral cerrada de edgeSlope·(1 − smoothstep(u')) que
            // usaba la versión anterior — ver esa nota para la derivación.
            val integral = u - u * u * u + 0.5f * u * u * u * u
            val sign = if (signedDist < 0f) -1f else 1f
            return edgeVal + sign * edgeSlope * falloffDist * integral
        }
        val seg = segmentIndexFor(localX)
        return hermiteValue(seg, localX)
    }

    /** Pendiente local — usada para inclinar la normal del vértice al
     * doblar (ver [LashMeshBender]). Dentro del rango, la derivada real del
     * segmento de Hermite que contiene a `localX`. Más allá, decae
     * suavemente a cero con un smoothstep sobre [falloffDistancePx]. */
    fun slopeAt(localX: Float): Float {
        if (localX <= minLocalX || localX >= maxLocalX) {
            val edge = localX.coerceIn(minLocalX, maxLocalX)
            val edgeIdx = if (localX <= minLocalX) 0 else nodeX.size - 1
            val edgeSlope = nodeSlope[edgeIdx]
            val falloffDist = falloffDistancePx()
            val u = (abs(localX - edge) / falloffDist).coerceIn(0f, 1f)
            val smoothstep = u * u * (3f - 2f * u)
            return edgeSlope * (1f - smoothstep)
        }
        val seg = segmentIndexFor(localX)
        return hermiteSlope(seg, localX)
    }

    /** Progreso de la caída hacia la meseta, en `[0,1]` — `0f` en cualquier
     * punto DENTRO de `[minLocalX, maxLocalX]` (datos reales, sin caída), y
     * el mismo `smoothstep(u)` que ya usa [slopeAt] para decaer la pendiente
     * más allá del borde. Expuesto para que [LashMeshBender] pueda amortiguar
     * la extrapolación (zona SIN landmarks reales, ej. la punta del ala de
     * un Cat Eye) de forma distinta a la interpolación (zona CON los 8
     * puntos reales, donde no hace falta amortiguar nada — ver
     * [RendererConfiguration.LASH_BEND_WING_STRENGTH]).
     *
     * Por qué esto no reintroduce el bug de "pico" (sección 5.6): `u²(3−2u)`
     * tiene derivada CERO en `u=0` y `u=1` por construcción (la propiedad
     * que define un smoothstep) — así que blendear una fuerza con esto como
     * peso no le agrega ninguna pendiente extra exactamente en el borde
     * (`u=0`, donde arranca la extrapolación), que es el único punto donde
     * "dentro" y "fuera" del rango se tocan. */
    fun wingBlend(localX: Float): Float {
        if (localX in minLocalX..maxLocalX) return 0f
        val edge = localX.coerceIn(minLocalX, maxLocalX)
        val falloffDist = falloffDistancePx()
        val u = (abs(localX - edge) / falloffDist).coerceIn(0f, 1f)
        return u * u * (3f - 2f * u)
    }

    /** Índice `i` tal que `localX` cae en `[nodeX[i], nodeX[i+1]]`. Asume
     * `localX` ya clampeado a `[minLocalX, maxLocalX]` por el llamador. */
    private fun segmentIndexFor(localX: Float): Int {
        var i = 0
        while (i < nodeX.size - 2 && localX > nodeX[i + 1]) i++
        return i
    }

    private fun hermiteValue(seg: Int, localX: Float): Float {
        val x0 = nodeX[seg]; val x1 = nodeX[seg + 1]
        val p0 = nodeY[seg]; val p1 = nodeY[seg + 1]
        val m0 = nodeSlope[seg]; val m1 = nodeSlope[seg + 1]
        val h = x1 - x0
        val t = (localX - x0) / h
        val t2 = t * t
        val t3 = t2 * t
        val h00 = 2f * t3 - 3f * t2 + 1f
        val h10 = t3 - 2f * t2 + t
        val h01 = -2f * t3 + 3f * t2
        val h11 = t3 - t2
        return h00 * p0 + h10 * h * m0 + h01 * p1 + h11 * h * m1
    }

    private fun hermiteSlope(seg: Int, localX: Float): Float {
        val x0 = nodeX[seg]; val x1 = nodeX[seg + 1]
        val p0 = nodeY[seg]; val p1 = nodeY[seg + 1]
        val m0 = nodeSlope[seg]; val m1 = nodeSlope[seg + 1]
        val h = x1 - x0
        val t = (localX - x0) / h
        val t2 = t * t
        // Derivadas de las funciones base de Hermite respecto a t.
        val dh00 = 6f * t2 - 6f * t
        val dh10 = 3f * t2 - 4f * t + 1f
        val dh01 = -6f * t2 + 6f * t
        val dh11 = 3f * t2 - 2f * t
        // dp/dx = (dp/dt) / h.
        return (dh00 * p0 + dh10 * h * m0 + dh01 * p1 + dh11 * h * m1) / h
    }

    /** Distancia (en `localX`, píxeles) sobre la que la pendiente del borde
     * decae a cero — proporcional al ancho real del rango interpolado (ver
     * [RendererConfiguration.LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER]), no una
     * constante inventada. [MIN_FALLOFF_PX] es solo un piso de seguridad
     * numérica, no un parámetro de ajuste visual. */
    private fun falloffDistancePx(): Float =
        ((maxLocalX - minLocalX) * RendererConfiguration.LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER)
            .coerceAtLeast(MIN_FALLOFF_PX)

    companion object {
        /** Piso de seguridad numérica para [falloffDistancePx] — no un
         * parámetro de ajuste visual, ver esa función. */
        private const val MIN_FALLOFF_PX = 1e-2f

        /** Distancia mínima en `localX` entre dos landmarks consecutivos
         * para tratarlos como nodos distintos del spline — landmarks casi
         * coincidentes en X (ruido de tracking) harían `h → 0` y el término
         * `1/h` de [hermiteSlope] explotaría; se fusionan en un solo nodo
         * (promediando Y) en vez de eso. No es un parámetro de ajuste
         * visual, es un piso de estabilidad numérica. */
        private const val MIN_NODE_SPACING_PX = 0.5f

        /**
         * `null` si no hay al menos 2 puntos distinguibles (menos de eso no
         * define ninguna curva) — el llamador debe tratarlo como "sin
         * curvatura adicional para este frame", no como error (ver uso en
         * [FaceRenderPipeline.computeEye]).
         */
        fun fit(points: List<ImagePoint>, anchor: ImagePoint, tangent: ImagePoint): LashLineCurve? {
            if (points.size < 2) return null

            // Proyecta cada punto a (localX, localY) relativos a `anchor` a
            // lo largo de la tangente del párpado — mismo sistema de
            // coordenadas que ya usaba la versión de parábola, y el mismo
            // que espera [LashMeshBender] (pixelLocalX).
            val perpX = -tangent.y
            val perpY = tangent.x
            val locals = ArrayList<Pair<Float, Float>>(points.size)
            for (p in points) {
                val dx = p.x - anchor.x
                val dy = p.y - anchor.y
                val localX = dx * tangent.x + dy * tangent.y
                val localY = dx * perpX + dy * perpY
                locals.add(localX to localY)
            }
            locals.sortBy { it.first }

            // Fusiona nodos casi coincidentes en X (ver MIN_NODE_SPACING_PX)
            // promediando su Y, para que el spline quede bien definido.
            val mergedX = ArrayList<Float>(locals.size)
            val mergedY = ArrayList<Float>(locals.size)
            for ((lx, ly) in locals) {
                if (mergedX.isNotEmpty() && lx - mergedX.last() < MIN_NODE_SPACING_PX) {
                    val n = mergedY.size - 1
                    mergedY[n] = (mergedY[n] + ly) / 2f
                } else {
                    mergedX.add(lx)
                    mergedY.add(ly)
                }
            }
            val n = mergedX.size
            if (n < 2) return null

            val nodeX = mergedX.toFloatArray()
            val nodeY = mergedY.toFloatArray()

            return LashLineCurve(nodeX, nodeY, monotoneTangents(nodeX, nodeY))
        }

        /**
         * Tangentes por nodo con el limitador de Fritsch-Carlson — variante
         * de Hermite cúbico que GARANTIZA que la curva es monótona en cada
         * tramo donde los propios landmarks lo son (nunca sube/baja de más
         * entre dos puntos consecutivos, a diferencia de un Catmull-Rom
         * puro, que puede "overshootear" — pasarse por encima/debajo de los
         * puntos vecinos — cuando la curvatura cambia de signo entre
         * segmentos). Para el párpado esto importa: un overshoot ahí se ve
         * como la pestaña abombándose más allá de lo que el propio párpado
         * dibuja, entre dos landmarks reales.
         *
         * Algoritmo estándar (Fritsch & Carlson, 1980):
         * 1. Secante de cada segmento `Δ_k = (y[k+1]-y[k])/(x[k+1]-x[k])`.
         * 2. Estimación inicial de tangente en cada nodo interno = promedio
         *    de las dos secantes adyacentes (igual que Catmull-Rom); en los
         *    extremos, la propia secante del único segmento adyacente.
         * 3. Por cada segmento, si la secante es 0 (tramo plano), sus dos
         *    tangentes se fuerzan a 0 (una tangente no nula ahí garantiza
         *    overshoot en un tramo que debería ser constante). Si no, se
         *    normalizan `α=m_k/Δ_k`, `β=m_{k+1}/Δ_k`: negativas se recortan a
         *    0 (tangente apuntando en contra de la secante — inconsistente,
         *    fuente directa de overshoot), y si `α²+β²>9` se escalan ambas
         *    por `3/√(α²+β²)` — el límite exacto que asegura monotonía
         *    dentro del segmento (más allá de ese radio, el cúbico de
         *    Hermite dejar de ser monótono incluso con secante consistente).
         */
        private fun monotoneTangents(nodeX: FloatArray, nodeY: FloatArray): FloatArray {
            val n = nodeX.size
            val secants = FloatArray(n - 1)
            for (k in 0 until n - 1) {
                secants[k] = (nodeY[k + 1] - nodeY[k]) / (nodeX[k + 1] - nodeX[k])
            }

            val tangents = FloatArray(n)
            tangents[0] = secants[0]
            tangents[n - 1] = secants[n - 2]
            for (i in 1 until n - 1) {
                tangents[i] = (secants[i - 1] + secants[i]) / 2f
            }

            for (k in 0 until n - 1) {
                val delta = secants[k]
                if (delta == 0f) {
                    tangents[k] = 0f
                    tangents[k + 1] = 0f
                    continue
                }
                var alpha = tangents[k] / delta
                var beta = tangents[k + 1] / delta
                if (alpha < 0f) {
                    tangents[k] = 0f
                    alpha = 0f
                }
                if (beta < 0f) {
                    tangents[k + 1] = 0f
                    beta = 0f
                }
                val s = alpha * alpha + beta * beta
                if (s > 9f) {
                    val tau = 3f / kotlin.math.sqrt(s)
                    tangents[k] = tau * alpha * delta
                    tangents[k + 1] = tau * beta * delta
                }
            }

            return tangents
        }
    }
}
