package com.example.test_face.render

/** Selects static closed-eye geometry independently of the last open-eye
 * contour. It never changes a rigid pose, openness detection or tracking. */
class ClosedLidContour {
    companion object {
        fun shouldMeasure(lidShapeTrusted: Boolean, normalizedOpenness: Float): Boolean =
            normalizedOpenness.isFinite() && (!lidShapeTrusted || normalizedOpenness < 0.3f)
    }

    private var measuredSinceNanos: Long? = null

    fun resolve(
        held: LashLineCurve?,
        measured: LashLineCurve?,
        transientWeight: Float,
        nowNanos: Long,
    ): LashLineCurve? {
        if (measured == null) {
            reset()
            return held
        }
        val started = measuredSinceNanos
        if (started == null || nowNanos < started) measuredSinceNanos = nowNanos
        if (held == null) return measured
        // Brief closures retain the existing transition. A sustained closed
        // eye must settle onto its own contour, not a previous person's arc.
        val elapsed = nowNanos - (measuredSinceNanos ?: nowNanos)
        val t = ((elapsed - 100_000_000L).toFloat() / 150_000_000f).coerceIn(0f, 1f)
        val settledWeight = t * t * (3f - 2f * t)
        val weight = maxOf(transientWeight.coerceIn(0f, 1f), settledWeight)
        return held.blendShape(measured, weight)
    }

    fun reset() {
        measuredSinceNanos = null
    }
}
