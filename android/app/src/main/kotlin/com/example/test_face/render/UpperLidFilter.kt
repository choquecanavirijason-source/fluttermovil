package com.example.test_face.render

import kotlin.math.hypot

/** Filters deformation in the eye's local frame. Translation, roll and scale
 * follow the current frame instead of mixing old points with the new anchor.
 * Reference-width coordinates make beta independent of analysis resolution
 * and distance from the camera. One instance per eye. */
class UpperLidFilter {
    private var filtersX: Array<OneEuroFilter> = emptyArray()
    private var filtersY: Array<OneEuroFilter> = emptyArray()
    private var lastNanos: Long? = null

    fun apply(
        points: List<ImagePoint>,
        tNanos: Long,
        origin: ImagePoint,
        tangent: ImagePoint,
        eyeWidthPx: Float,
    ): List<ImagePoint> {
        val length = hypot(tangent.x, tangent.y)
        if (points.isEmpty() || !eyeWidthPx.isFinite() || eyeWidthPx <= 1e-3f ||
            !length.isFinite() || length <= 1e-6f ||
            !origin.x.isFinite() || !origin.y.isFinite() ||
            points.any { !it.x.isFinite() || !it.y.isFinite() }
        ) {
            reset()
            return points
        }
        val previous = lastNanos
        if (filtersX.size != points.size ||
            (previous != null && (tNanos <= previous || tNanos - previous > MAX_GAP_NANOS))
        ) {
            reset()
            filtersX = Array(points.size) { newFilter() }
            filtersY = Array(points.size) { newFilter() }
        }
        lastNanos = tNanos
        val tx = tangent.x / length
        val ty = tangent.y / length
        val toLocal = REFERENCE_EYE_WIDTH_PX / eyeWidthPx
        val toImage = eyeWidthPx / REFERENCE_EYE_WIDTH_PX
        // Seed on the first frame too, so the second sample is filtered.
        return List(points.size) { i ->
            val dx = points[i].x - origin.x
            val dy = points[i].y - origin.y
            val x = filtersX[i].filter((dx * tx + dy * ty) * toLocal, tNanos) * toImage
            val y = filtersY[i].filter((-dx * ty + dy * tx) * toLocal, tNanos) * toImage
            ImagePoint(origin.x + x * tx - y * ty, origin.y + x * ty + y * tx)
        }
    }

    fun reset() {
        filtersX = emptyArray()
        filtersY = emptyArray()
        lastNanos = null
    }

    private fun newFilter() = OneEuroFilter(
        RendererConfiguration.LID_POINT_MIN_CUTOFF,
        RendererConfiguration.LID_POINT_BETA,
        RendererConfiguration.ONE_EURO_D_CUTOFF,
    )

    companion object {
        // Approximate eye width in the original 640px analysis calibration.
        const val REFERENCE_EYE_WIDTH_PX = 46f
        // Discard stale shape after a long blink or tracking interruption.
        const val MAX_GAP_NANOS = 250_000_000L
    }
}
