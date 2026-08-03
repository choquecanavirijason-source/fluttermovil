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
     * ajuste — ver [fit]. [deviationAt]/[slopeAt] hacen clamp de su entrada
     * a este rango antes de evaluar: una cuadrática evaluada MÁS ALLÁ de
     * donde se ajustó diverge rápido (por diseño de cualquier polinomio),
     * y [LashMeshBender] necesita evaluar hasta los BORDES de la malla del
     * modelo (± mitad del ancho del ojo, MÁS `anchorOffsetPx` — ver
     * [EyeAnchorCalculator.lashCurveAnchorOffsetPx] — que puede llevar esos
     * bordes bien lejos del rango angosto de los landmarks reales del
     * párpado usados en [fit]).
     *
     * CORRECCIÓN 2026-08-02 (BEND_DIAG_4): antes, más allá de este rango,
     * [deviationAt] seguía sumando `pendiente_del_borde × distancia` — una
     * extrapolación LINEAL, más segura que dejar seguir la parábola (que
     * acelera), pero que IGUAL crece sin límite con la distancia. Con
     * `anchorOffsetPx` grande (~68% del ancho del ojo, `NOSE_AVOID_SHIFT`)
     * y estilos "wing" (Cat Eye) que extienden el mesh bien más allá del
     * ancho natural del ojo, la mayoría de los vértices caían LEJOS del
     * rango — la extrapolación lineal, sobre esa distancia, se disparaba a
     * decenas de píxeles de desviación: la pestaña salía como una raya recta
     * hacia la ceja/frente en vez de una pestaña curva (confirmado en
     * dispositivo real con `LASH_BEND_STRENGTH=1.0`, ver ESTADO_ACTUAL.md).
     * Ahora [deviationAt] se sostiene PLANA (el valor exacto del borde, sin
     * ningún término adicional) más allá del rango fitteado — no hay datos
     * reales del párpado ahí, así que no hay base para asumir que la curva
     * SIGUE cambiando; sostenerla plana es la única opción que no puede
     * explotar sin importar cuán lejos esté `localX` del rango. La pendiente
     * ([slopeAt]) sigue sosteniendo el valor del borde (no cero) para que la
     * normal no tenga un salto brusco de iluminación justo en el borde del
     * clamp — eso no crece con la distancia, así que es seguro dejarlo.
     */
    private val minLocalX: Float,
    private val maxLocalX: Float,
) {
    /** Plana (constante) más allá de `[minLocalX, maxLocalX]` — ver nota de
     * la clase. Nunca devuelve más que el máximo/mínimo que la parábola
     * alcanza DENTRO del rango realmente ajustado. */
    fun deviationAt(localX: Float): Float {
        val clamped = localX.coerceIn(minLocalX, maxLocalX)
        return a * clamped * clamped + b * clamped + c
    }

    /** Pendiente local (derivada de la parábola en el punto clampeado) —
     * usada para inclinar la normal del vértice al doblar, no solo
     * desplazarlo (ver [LashMeshBender]; si no, la iluminación se ve plana/
     * incorrecta). Se mantiene en el valor del borde más allá del rango
     * fitteado — a diferencia de [deviationAt], esto no crece con la
     * distancia (es un valor fijo), así que no hace falta aplanarlo también;
     * mantenerlo evita un salto visual de iluminación justo en el borde del
     * clamp. */
    fun slopeAt(localX: Float): Float {
        val clamped = localX.coerceIn(minLocalX, maxLocalX)
        return 2f * a * clamped + b
    }

    companion object {
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
