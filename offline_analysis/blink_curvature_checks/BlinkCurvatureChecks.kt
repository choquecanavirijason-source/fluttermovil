package com.example.test_face.render

import kotlin.math.abs
import kotlin.math.cos

private fun projected(scale: Float, closed: Float): Float {
    val degrees = RendererConfiguration.LASH_CLOSED_DROP_DEGREES * LidDropRotation.dropAmount(closed)
    return scale * cos(Math.toRadians(degrees.toDouble())).toFloat()
}

fun main() {
    var previous = LidDropRotation.bandCompensation(0f)
    var maxStep = 0f
    repeat(10_001) { i ->
        val closed = i / 10_000f
        val scale = LidDropRotation.bandCompensation(closed)
        check(scale.isFinite() && abs(scale) <= RendererConfiguration.LASH_CLOSED_BAND_COMPENSATION_MAX)
        check(projected(scale, closed) >= -1e-5f)
        maxStep = maxOf(maxStep, abs(scale - previous))
        previous = scale
    }
    check(maxStep < 0.02f) { "Compensation discontinuity: $maxStep" }
    // Replay sparse closure samples: the node and mesh must cross 90°
    // together even when a blink skips intermediate analysis frames.
    var oldScale = LidDropRotation.bandCompensation(0f)
    var correctedScale = oldScale
    var lastTarget = oldScale
    var reproducedInversion = false
    for (closed in listOf(0f, 0.3f, 0.5f, 1f, 0.5f, 0.3f, 0f)) {
        val target = LidDropRotation.bandCompensation(closed)
        val changed = abs(target - lastTarget) > 1e-3f
        val oldAlpha = RendererConfiguration.LASH_BEND_SMOOTHING
        oldScale = oldScale * (1f - oldAlpha) + target * oldAlpha
        if (projected(oldScale, closed) < -1e-3f) reproducedInversion = true
        val alpha = LidDropRotation.deformationSmoothing(oldAlpha, changed)
        correctedScale = correctedScale * (1f - alpha) + target * alpha
        check(projected(correctedScale, closed) >= -1e-5f) { "Blink inverted at $closed" }
        lastTarget = target
    }
    check(reproducedInversion) { "Fixture did not reproduce the extra-smoothing bug" }
    check(LidDropRotation.deformationSmoothing(0.3f, false) == 0.3f)
    check(LidDropRotation.bandCompensation(Float.NaN).isFinite())
    println("PASS: 10001 closure samples; sparse blink reproduced old inversion and retained curvature with synchronized compensation; resting smoothing unchanged")
}
