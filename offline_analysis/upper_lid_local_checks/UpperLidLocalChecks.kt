package com.example.test_face.render

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

private fun near(a: List<ImagePoint>, b: List<ImagePoint>) {
    check(a.size == b.size)
    a.zip(b).forEach { (x, y) ->
        check(abs(x.x - y.x) < 0.001f && abs(x.y - y.y) < 0.001f) { "$x != $y" }
    }
}

fun main() {
    checkBlinkRecovery()
    val shape = listOf(ImagePoint(-20f, 0f), ImagePoint(0f, -6f), ImagePoint(20f, 0f))
    val origin = ImagePoint(0f, 0f)
    val tangent = ImagePoint(1f, 0f)
    val stationary = UpperLidFilter()
    val moving = UpperLidFilter()
    // Camera motion must not alter the filtered local shape, even while
    // landmarks jitter. Includes changing distance and large roll angles.
    repeat(120) { i ->
        val angle = i * 0.04f
        val scale = 0.5f + i / 60f
        val tx = cos(angle)
        val ty = sin(angle)
        val center = ImagePoint(100f + i * 3f, 200f - i * 2f)
        fun move(p: ImagePoint) = ImagePoint(
            center.x + scale * (p.x * tx - p.y * ty),
            center.y + scale * (p.x * ty + p.y * tx),
        )
        val noisy = shape.mapIndexed { index, p ->
            ImagePoint(p.x, p.y + if (index == 1) sin(i * 1.7f) else 0f)
        }
        val time = 1_000_000_000L + i * 33_333_333L
        val expected = stationary.apply(noisy, time, origin, tangent, 46f).map(::move)
        near(expected, moving.apply(noisy.map(::move), time, center, ImagePoint(tx, ty), 46f * scale))
    }
    val filter = UpperLidFilter()
    near(shape, filter.apply(shape, 0, origin, tangent, 46f))
    val perturbed = shape.map { ImagePoint(it.x, it.y + 1f) }
    val second = filter.apply(perturbed, 33_333_333, origin, tangent, 46f)
    check(second[1].y > shape[1].y && second[1].y < perturbed[1].y) {
        "Second sample must already suppress jitter"
    }
    // A long blink, explicit loss, changed topology and clock restart must
    // seed from the new observation rather than drag an obsolete shape.
    near(perturbed, filter.apply(perturbed, 1_000_000_000, origin, tangent, 46f))
    filter.reset()
    near(shape, filter.apply(shape, 2_000_000_000, origin, tangent, 46f))
    near(perturbed, filter.apply(perturbed, 1, origin, tangent, 46f))
    near(shape.take(2), filter.apply(shape.take(2), 2, origin, tangent, 46f))
    filter.apply(shape, 3, origin, tangent, 0f)
    near(perturbed, filter.apply(perturbed, 4, origin, tangent, 46f))
    println("PASS: local-shape invariance, second-frame smoothing, gap/loss/topology/clock/invalid-frame recovery")
}
