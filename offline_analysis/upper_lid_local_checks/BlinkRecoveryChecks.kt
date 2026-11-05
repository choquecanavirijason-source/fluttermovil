package com.example.test_face.render

import kotlin.math.abs

fun checkBlinkRecovery() {
    val tracker = OpennessTracker()
    check(tracker.updateFromBlendshape(1f))
    check(tracker.normalizedOpenness == 1f)
    check(!tracker.updateFromBlendshape(0.1f))
    check(tracker.normalizedOpenness == 0f)
    // Reopening must gradually release the rotation/anchor/band compensation
    // while the shape remains held until the open hysteresis threshold.
    check(!tracker.updateFromBlendshape(0.55f))
    check(abs(tracker.normalizedOpenness - 0.5f) < 1e-5f)
    check(tracker.updateFromBlendshape(0.7f))
    check(tracker.normalizedOpenness == 1f)
    // The same intermediate opening has the same visual amount on closing;
    // the shape gate alone retains its hysteresis.
    check(tracker.updateFromBlendshape(0.55f))
    check(abs(tracker.normalizedOpenness - 0.5f) < 1e-5f)
    check(!tracker.updateFromBlendshape(0.4f))
    val before = tracker.normalizedOpenness
    check(!tracker.updateFromBlendshape(Float.NaN))
    check(tracker.normalizedOpenness == before)
    tracker.reset()
    check(tracker.updateFromBlendshape(0.8f))
    check(tracker.normalizedOpenness == 1f)
    // Test independent per-eye state: a blink must not rotate the other eye.
    val otherEye = OpennessTracker()
    check(otherEye.updateFromBlendshape(0.7f))
    tracker.updateFromBlendshape(0f)
    check(otherEye.normalizedOpenness == 1f)
    println("PASS: continuous blink recovery, shape hysteresis, invalid sample, reset, independent eyes")
}
