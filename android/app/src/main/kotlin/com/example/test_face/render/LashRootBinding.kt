package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion

/** Attachment targets in the final model's local space. They are obtained
 * from the same detected line shown by the green overlay, through the actual
 * camera projection and inverse model transform, not a pixel/scale estimate. */
class LashRootBinding(
    val points: List<Float3>,
    val knots: FloatArray,
    val sourceMinX: Float,
    val sourceMaxX: Float,
) {
    fun segment(t: Float): Int {
        var i = 0
        while (i < knots.size - 2 && t > knots[i + 1]) i++
        return i
    }

    /** Puntos y tangentes (dP/dt) planos, para muestrear sin asignar
     * objetos: [sampleInto] corre por cada vértice de la malla en cada frame.
     *
     * Los puntos ya llegan suavizados y sin encimados (ver [fromWorld]).
     * Las tangentes son diferencia
     * central sobre los knots (Catmull-Rom no uniforme), unilaterales en las
     * puntas. Con tramos rectos entre landmarks la raíz quedaba poligonal,
     * con "esquinas" en cada punto del párpado. */
    private val px = FloatArray(points.size)
    private val py = FloatArray(points.size)
    private val pz = FloatArray(points.size)
    private val tx = FloatArray(points.size)
    private val ty = FloatArray(points.size)
    private val tz = FloatArray(points.size)

    init {
        val n = points.size
        for (i in 0 until n) {
            px[i] = points[i].x; py[i] = points[i].y; pz[i] = points[i].z
        }
        for (i in 0 until n) {
            val a = (i - 1).coerceAtLeast(0)
            val b = (i + 1).coerceAtMost(n - 1)
            val dt = (knots[b] - knots[a]).coerceAtLeast(1e-6f)
            tx[i] = (px[b] - px[a]) / dt
            ty[i] = (py[b] - py[a]) / dt
            tz[i] = (pz[b] - pz[a]) / dt
        }
    }

    /** Punto suave de la línea en el parámetro [t] (0..1 = de punta a punta),
     * escrito en [out] (x, y, z) y, si [out] tiene 6 lugares, su tangente
     * dP/dt en (3, 4, 5). Fuera de ese rango sigue recto por la
     * tangente de la punta. */
    fun sampleInto(t: Float, out: FloatArray) {
        val last = px.size - 1
        if (t <= knots[0] || t >= knots[last]) {
            val e = if (t <= knots[0]) 0 else last
            val d = t - knots[e]
            out[0] = px[e] + tx[e] * d
            out[1] = py[e] + ty[e] * d
            out[2] = pz[e] + tz[e] * d
            if (out.size >= 6) { out[3] = tx[e]; out[4] = ty[e]; out[5] = tz[e] }
            return
        }
        val i = segment(t)
        val j = i + 1
        val h = (knots[j] - knots[i]).coerceAtLeast(1e-6f)
        val s = (t - knots[i]) / h
        val s2 = s * s
        val s3 = s2 * s
        val h00 = 2f * s3 - 3f * s2 + 1f
        val h10 = (s3 - 2f * s2 + s) * h
        val h01 = -2f * s3 + 3f * s2
        val h11 = (s3 - s2) * h
        out[0] = px[i] * h00 + tx[i] * h10 + px[j] * h01 + tx[j] * h11
        out[1] = py[i] * h00 + ty[i] * h10 + py[j] * h01 + ty[j] * h11
        out[2] = pz[i] * h00 + tz[i] * h10 + pz[j] * h01 + tz[j] * h11
        if (out.size >= 6) {
            // Derivada del Hermite respecto de t (= d/ds / h).
            val d00 = (6f * s2 - 6f * s) / h
            val d10 = 3f * s2 - 4f * s + 1f
            val d01 = (-6f * s2 + 6f * s) / h
            val d11 = 3f * s2 - 2f * s
            out[3] = px[i] * d00 + tx[i] * d10 + px[j] * d01 + tx[j] * d11
            out[4] = py[i] * d00 + ty[i] * d10 + py[j] * d01 + ty[j] * d11
            out[5] = pz[i] * d00 + tz[i] * d10 + pz[j] * d01 + tz[j] * d11
        }
    }

    companion object {
        fun fromWorld(
            world: List<Float3>,
            position: Float3,
            rotation: Quaternion,
            scale: Float3,
            sourceMinX: Float,
            sourceMaxX: Float,
        ): LashRootBinding? {
            if (world.size < 2 || world.any { !it.x.isFinite() || !it.y.isFinite() || !it.z.isFinite() } ||
                scale.x <= 0f || scale.y <= 0f || scale.z <= 0f ||
                !scale.x.isFinite() || !scale.y.isFinite() || !scale.z.isFinite() ||
                sourceMaxX - sourceMinX <= 1e-6f) return null
            // Suavizado [1,2,1]/4 de los puntos INTERIORES (quita el temblor
            // de los landmarks, que ondulaba la curva); las puntas quedan fijas.
            // Se hace ANTES de medir largos, para que los knots correspondan a
            // los puntos que se interpolan.
            val w = RendererConfiguration.LASH_ROOT_LINE_SMOOTHING
            val smoothed = world.mapIndexed { i, p ->
                if (i == 0 || i == world.size - 1 || w <= 0f) p
                else p + ((world[i - 1] + world[i + 1]) * 0.5f - p) * w
            }
            // Descartar puntos interiores casi encimados (p. ej. la cola de
            // la línea cuando sale corta, junto al canto): con un intervalo
            // diminuto la tangente del spline se dispara y estira las fibras
            // de la punta.
            val cum = FloatArray(smoothed.size)
            for (i in 1 until smoothed.size) {
                val d = smoothed[i] - smoothed[i - 1]
                cum[i] = cum[i - 1] + kotlin.math.sqrt(d.x*d.x + d.y*d.y + d.z*d.z)
            }
            val fullLength = cum.last()
            if (!fullLength.isFinite() || fullLength <= 1e-6f) return null
            val minGap = RendererConfiguration.LASH_ROOT_LINE_MIN_GAP * fullLength
            val kept = ArrayList<Int>(smoothed.size).apply { add(0) }
            for (i in 1 until smoothed.size - 1) {
                if (cum[i] - cum[kept.last()] >= minGap && fullLength - cum[i] >= minGap) kept.add(i)
            }
            kept.add(smoothed.size - 1)
            val line = kept.map { smoothed[it] }
            val q = rotation
            val mapped = line.map { p ->
                val v = p - position
                // R(conjugate(q)) * v, followed by inverse nonuniform scale.
                val tx = 2f * (-q.y * v.z + q.z * v.y)
                val ty = 2f * (-q.z * v.x + q.x * v.z)
                val tz = 2f * (-q.x * v.y + q.y * v.x)
                Float3(
                    (v.x + q.w * tx - q.y * tz + q.z * ty) / scale.x,
                    (v.y + q.w * ty - q.z * tx + q.x * tz) / scale.y,
                    (v.z + q.w * tz - q.x * ty + q.y * tx) / scale.z,
                )
            }
            val reversed = mapped.last().x < mapped.first().x
            val local = if (reversed) mapped.reversed() else mapped
            // Parameterize by the detected line's cumulative length. This
            // preserves unequal landmark spacing without assuming eight
            // evenly spaced points or reusing a previous open-eye curve.
            val lengths = FloatArray(local.size)
            for (i in 1 until local.size) {
                // World distances are invariant to the model's unequal scale.
                val d = line[i] - line[i - 1]
                lengths[i] = lengths[i - 1] + kotlin.math.sqrt(d.x*d.x + d.y*d.y + d.z*d.z)
            }
            val total = lengths.last()
            if (!total.isFinite() || total <= 1e-6f) return null
            val knots = FloatArray(local.size) { i ->
                if (reversed) 1f - lengths[lengths.size - 1 - i] / total else lengths[i] / total
            }
            return LashRootBinding(local, knots, sourceMinX, sourceMaxX)
        }
    }
}
