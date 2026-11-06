package com.example.test_face.render

import kotlin.math.roundToInt

/** Rest depth of the attachment band, cached once per asset. The supplied
 * assets have a flat minimum-Y root row, but a curved, nonzero Z profile. */
object LashRootDepth {
    fun perVertex(raw: RawMesh): FloatArray {
        val bins = 64
        val sums = FloatArray(bins)
        val counts = IntArray(bins)
        val span = (raw.maxX - raw.minX).coerceAtLeast(1e-6f)
        val height = raw.vertices.maxOf { it.position.y } - raw.minY
        val tolerance = (height * 0.005f).coerceAtLeast(1e-6f)
        for (v in raw.vertices) {
            val p = v.position
            if (p.y - raw.minY > tolerance) continue
            val bin = (((p.x - raw.minX) / span) * (bins - 1)).roundToInt().coerceIn(0, bins - 1)
            sums[bin] += p.z
            counts[bin]++
        }
        val known = (0 until bins).filter { counts[it] > 0 }
        if (known.isEmpty()) return FloatArray(raw.vertices.size)
        for (i in known) sums[i] /= counts[i].toFloat()
        for (i in 0 until bins) {
            if (counts[i] > 0) continue
            val left = known.lastOrNull { it < i } ?: known.first()
            val right = known.firstOrNull { it > i } ?: known.last()
            sums[i] = if (left == right) sums[left] else {
                val t = (i - left).toFloat() / (right - left)
                sums[left] + (sums[right] - sums[left]) * t
            }
        }
        return FloatArray(raw.vertices.size) { i ->
            val t = ((raw.vertices[i].position.x - raw.minX) / span * (bins - 1)).coerceIn(0f, (bins - 1).toFloat())
            val a = t.toInt().coerceAtMost(bins - 2)
            sums[a] + (sums[a + 1] - sums[a]) * (t - a)
        }
    }
}
