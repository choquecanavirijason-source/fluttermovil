package com.example.test_face.render

import kotlin.math.abs

/**
 * Curva de ajuste (mínimos cuadrados, cuadrática) al párpado superior real
 * ("Upper Lash Line"), en un sistema de coordenadas local alineado con la
 * tangente promedio del párpado — la misma que ya usa [EyePlaneCalculator]
 * para el residual de rotación. Por eso [LashLineCurve] captura SOLO la
 * curvatura ADICIONAL respecto a esa inclinación promedio, sin duplicar la
 * rotación que el transform rígido ([EyeTransformCalculator]) ya aplica.
 *
 * `f(localX) = a·localX² + b·localX + c` da el desvío perpendicular (en
 * píxeles de imagen) de la curva real respecto a la línea recta promedio,
 * en el punto `localX` (distancia proyectada desde el ancla a lo largo de
 * la tangente del párpado).
 */
class LashLineCurve private constructor(
    private val a: Float,
    private val b: Float,
    private val c: Float,
    /** Rango real (en `localX`, píxeles) de los puntos usados para el
     * ajuste — ver [fit]. Más allá de este rango no hay datos reales del
     * párpado; [deviationAt]/[slopeAt] hacen decaer la influencia de la
     * parábola suavemente en vez de evaluarla sin límite (diverge rápido,
     * por diseño de cualquier polinomio) o cortarla en seco.
     *
     * CORRECCIÓN 2026-08-02 (BEND_DIAG_4): la primera versión de este fix
     * sostenía la desviación PLANA (constante, igual al valor del borde)
     * más allá de este rango — evitaba que una extrapolación lineal previa
     * se disparara sin límite (con `anchorOffsetPx` grande, ~68% del ancho
     * del ojo, y estilos "wing" como Cat Eye, la mayoría de los vértices
     * caían lejos del rango fitteado y esa extrapolación lineal se disparaba
     * a decenas de píxeles — la pestaña salía como una raya recta hacia la
     * ceja/frente, confirmado en dispositivo real). Sostener PLANO evitaba
     * eso, pero es continuo en VALOR (C0) y discontinuo en DERIVADA (la
     * pendiente cae de golpe a 0 justo en el borde) — geométricamente, un
     * shear vertical con esa discontinuidad produce, en la silueta del mesh,
     * un pico/esquina justo en `minLocalX`/`maxLocalX` en vez de una curva
     * redonda continua ("se doblan, se deforman" en vez de una pestaña
     * redondeada).
     *
     * CORRECCIÓN 2026-08-07 (BEND_DIAG_5, con fix de signo — ver
     * [deviationAt]): la PENDIENTE ahora decae suavemente a cero con un
     * smoothstep (`u²(3−2u)`, la misma función que ya usa
     * `LashRenderer.opennessDamping`) sobre una distancia derivada del
     * propio ancho ajustado (mitad de `[minLocalX,maxLocalX]`, ni una
     * constante inventada ni un valor fijo en píxeles), y la desviación es
     * la integral CERRADA de esa pendiente decayente. Resultado:
     * continuidad C1 EXACTA en el borde (mismo valor y misma pendiente que
     * la parábola ahí mismo — no una aproximación) y la desviación sigue
     * acotada más allá de la zona de transición (se aplana en una meseta),
     * preservando la garantía original de que nunca puede explotar.
     */
    private val minLocalX: Float,
    private val maxLocalX: Float,
) {
    /** Ver nota de la clase. Dentro de `[minLocalX, maxLocalX]`, la parábola
     * tal cual. Más allá, el valor del borde más/menos la integral de la
     * pendiente decayente — continuidad C1 exacta en el borde, acotada
     * (meseta) más allá de la zona de transición. */
    fun deviationAt(localX: Float): Float {
        if (localX in minLocalX..maxLocalX) {
            return a * localX * localX + b * localX + c
        }
        val edge = localX.coerceIn(minLocalX, maxLocalX)
        val edgeVal = a * edge * edge + b * edge + c
        val edgeSlope = 2f * a * edge + b
        val falloffDist = falloffDistancePx()
        val signedDist = localX - edge
        val u = (abs(signedDist) / falloffDist).coerceIn(0f, 1f)
        // Integral cerrada de edgeSlope·(1 − smoothstep(u')) du', de 0 a u,
        // reescalada por falloffDist (smoothstep(u) = u²(3−2u)):
        //   ∫₀ᵘ (1 − u'²(3−2u')) du' = u − u³ + u⁴/2
        val integral = u - u * u * u + 0.5f * u * u * u * u
        // Del lado de maxLocalX, `localX` crece en la MISMA dirección en
        // que se integra la pendiente (hacia +x) → el término se SUMA. Del
        // lado de minLocalX, `localX` decrece (se aleja del borde hacia -x)
        // → recorrer esa dirección acumula la integral con signo CONTRARIO
        // (equivalente a integrar "hacia atrás"). Sin este signo, F'(minLocalX⁻)
        // saldría -edgeSlope en vez de +edgeSlope — un salto de signo en la
        // derivada justo en el borde, exactamente donde se buscaba
        // continuidad C1 — y se ve como un pliegue/deformación en ese lado
        // en vez de una curva redondeada continua.
        val sign = if (signedDist < 0f) -1f else 1f
        return edgeVal + sign * edgeSlope * falloffDist * integral
    }

    /** Pendiente local — usada para inclinar la normal del vértice al
     * doblar (ver [LashMeshBender]; si no, la iluminación se ve plana/
     * incorrecta). Dentro del rango, la derivada real de la parábola. Más
     * allá, decae suavemente a cero con un smoothstep sobre
     * [falloffDistancePx] — para que [deviationAt] se aplane gradualmente
     * en vez de con un quiebre de derivada (ver nota de la clase). */
    fun slopeAt(localX: Float): Float {
        if (localX in minLocalX..maxLocalX) {
            return 2f * a * localX + b
        }
        val edge = localX.coerceIn(minLocalX, maxLocalX)
        val edgeSlope = 2f * a * edge + b
        val falloffDist = falloffDistancePx()
        val u = (abs(localX - edge) / falloffDist).coerceIn(0f, 1f)
        val smoothstep = u * u * (3f - 2f * u)
        return edgeSlope * (1f - smoothstep)
    }

    /** Distancia (en `localX`, píxeles) sobre la que la pendiente del borde
     * decae a cero — proporcional al ancho real del rango ajustado (ver
     * [RendererConfiguration.LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER]), no una
     * constante inventada: un ala más ancha (ojo más grande / más
     * landmarks) obtiene una zona de transición proporcionalmente más
     * ancha. [MIN_FALLOFF_PX] es solo un piso de seguridad numérica (evitar
     * división por cero si el rango fitteado fuera degeneradamente angosto),
     * no un parámetro de ajuste visual. */
    private fun falloffDistancePx(): Float =
        ((maxLocalX - minLocalX) * RendererConfiguration.LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER)
            .coerceAtLeast(MIN_FALLOFF_PX)

    companion object {
        /** Piso de seguridad numérica para [falloffDistancePx] — no un
         * parámetro de ajuste visual, ver esa función. */
        private const val MIN_FALLOFF_PX = 1e-2f

        /**
         * `null` si no hay suficientes puntos para un ajuste significativo
         * (menos de 3) o si el sistema resulta degenerado — el llamador
         * debe tratarlo como "sin curvatura adicional para este frame", no
         * como error (ver uso en [FaceRenderPipeline.computeEye]).
         */
        fun fit(points: List<ImagePoint>, anchor: ImagePoint, tangent: ImagePoint): LashLineCurve? {
            if (points.size < 3) return null

            // Perpendicular a la tangente, en el mismo plano 2D.
            val perpX = -tangent.y
            val perpY = tangent.x

            // Primera pasada: proyectar a (localX, localY) relativos a
            // `anchor` y calcular su media en X. `anchor` puede estar MUY
            // lejos del centro real de la nube de puntos del párpado — no es
            // un descuido, es a propósito: EyeAnchorCalculator desplaza el
            // ancla ~68% del ancho del ojo hacia la esquina externa
            // (NOSE_AVOID_SHIFT), para que el modelo 3D no invada la nariz al
            // posicionarse. Pero ajustar mínimos cuadrados con datos tan
            // descentrados mal-condiciona las ecuaciones normales (el
            // término x⁴ crece muchísimo más rápido que los demás cuando |x|
            // es grande) y dispara coeficientes a/b/c grandes e inestables
            // — confirmado en dispositivo real (BEND_DIAG, 2026-07-29):
            // desviación fuertemente asimétrica entre ambos bordes del ojo,
            // firma clásica de mal condicionamiento numérico, no de curvatura
            // anatómica real.
            val locals = ArrayList<Pair<Double, Double>>(points.size)
            var sumLocalX = 0.0
            for (p in points) {
                val dx = (p.x - anchor.x).toDouble()
                val dy = (p.y - anchor.y).toDouble()
                val localX = dx * tangent.x + dy * tangent.y
                val localY = dx * perpX + dy * perpY
                locals.add(localX to localY)
                sumLocalX += localX
            }
            val meanLocalX = sumLocalX / points.size

            // Segunda pasada: arma las ecuaciones normales con X CENTRADO en
            // la media real de los puntos (no en `anchor`) — el mismo truco
            // de estabilidad numérica que cualquier regresión polinómica
            // (centering). El resultado (aC, bC, cC) describe la curva en
            // ESE sistema centrado.
            var s0 = 0.0
            var s1 = 0.0
            var s2 = 0.0
            var s3 = 0.0
            var s4 = 0.0
            var t0 = 0.0
            var t1 = 0.0
            var t2 = 0.0
            var minLocalX = Float.POSITIVE_INFINITY
            var maxLocalX = Float.NEGATIVE_INFINITY
            for ((localXRaw, localY) in locals) {
                val localX = localXRaw - meanLocalX
                val x2 = localX * localX
                s0 += 1.0
                s1 += localX
                s2 += x2
                s3 += x2 * localX
                s4 += x2 * x2
                t0 += localY
                t1 += localY * localX
                t2 += localY * x2

                val localXf = localXRaw.toFloat()
                if (localXf < minLocalX) minLocalX = localXf
                if (localXf > maxLocalX) maxLocalX = localXf
            }

            // Ecuaciones normales de mínimos cuadrados para y = aC·x'² + bC·x' + cC,
            // con x' = localX - meanLocalX (centrado).
            val solved = solve3x3(
                doubleArrayOf(s4, s3, s2, t2),
                doubleArrayOf(s3, s2, s1, t1),
                doubleArrayOf(s2, s1, s0, t0),
            ) ?: return null
            val aC = solved[0]
            val bC = solved[1]
            val cC = solved[2]

            // Expande de vuelta a coordenadas relativas a `anchor` (sin
            // centrar) — el contrato externo de LashLineCurve (deviationAt/
            // slopeAt reciben localX relativo a `anchor`, igual que
            // LashMeshBender ya espera) no cambia, solo el CÁLCULO interno
            // fue más estable. Álgebra: aC·(x-m)² + bC·(x-m) + cC
            //   = aC·x² + (bC - 2·aC·m)·x + (aC·m² - bC·m + cC)
            val m = meanLocalX
            val a = aC
            val b = bC - 2.0 * aC * m
            val c = aC * m * m - bC * m + cC

            return LashLineCurve(
                a = a.toFloat(),
                b = b.toFloat(),
                c = c.toFloat(),
                minLocalX = minLocalX,
                maxLocalX = maxLocalX,
            )
        }

        /** Resuelve un sistema lineal 3x3 (`m·x = b`, última columna de cada
         * fila) por eliminación gaussiana con pivoteo parcial. `null` si el
         * sistema es singular (párpado degenerado — puntos casi colineales
         * en X, por ejemplo con muy poca varianza horizontal). */
        private fun solve3x3(row0: DoubleArray, row1: DoubleArray, row2: DoubleArray): DoubleArray? {
            val m = arrayOf(row0.copyOf(), row1.copyOf(), row2.copyOf())
            for (col in 0..2) {
                var pivotRow = col
                for (r in col + 1..2) {
                    if (abs(m[r][col]) > abs(m[pivotRow][col])) pivotRow = r
                }
                if (abs(m[pivotRow][col]) < 1e-9) return null
                val tmp = m[col]
                m[col] = m[pivotRow]
                m[pivotRow] = tmp

                for (r in 0..2) {
                    if (r == col) continue
                    val factor = m[r][col] / m[col][col]
                    for (cc in col..3) m[r][cc] -= factor * m[col][cc]
                }
            }
            return doubleArrayOf(m[0][3] / m[0][0], m[1][3] / m[1][1], m[2][3] / m[2][2])
        }
    }
}
