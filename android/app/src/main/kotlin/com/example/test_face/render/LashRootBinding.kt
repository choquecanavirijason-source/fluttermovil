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
            val q = rotation
            val mapped = world.map { p ->
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
                val d = world[i] - world[i - 1]
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
