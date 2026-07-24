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
) {
    fun deviationAt(localX: Float): Float = a * localX * localX + b * localX + c

    /** Pendiente local (derivada de [deviationAt]) — usada para inclinar la
     * normal del vértice al doblar, no solo desplazarlo (ver
     * [LashMeshBender]; si no, la iluminación se ve plana/incorrecta). */
    fun slopeAt(localX: Float): Float = 2f * a * localX + b

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

            var s0 = 0.0
            var s1 = 0.0
            var s2 = 0.0
            var s3 = 0.0
            var s4 = 0.0
            var t0 = 0.0
            var t1 = 0.0
            var t2 = 0.0
            for (p in points) {
                val dx = (p.x - anchor.x).toDouble()
                val dy = (p.y - anchor.y).toDouble()
                val localX = dx * tangent.x + dy * tangent.y
                val localY = dx * perpX + dy * perpY

                val x2 = localX * localX
                s0 += 1.0
                s1 += localX
                s2 += x2
                s3 += x2 * localX
                s4 += x2 * x2
                t0 += localY
                t1 += localY * localX
                t2 += localY * x2
            }

            // Ecuaciones normales de mínimos cuadrados para y = a·x² + b·x + c.
            val solved = solve3x3(
                doubleArrayOf(s4, s3, s2, t2),
                doubleArrayOf(s3, s2, s1, t1),
                doubleArrayOf(s2, s1, s0, t0),
            ) ?: return null

            return LashLineCurve(a = solved[0].toFloat(), b = solved[1].toFloat(), c = solved[2].toFloat())
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
