package com.example.test_face.render

import kotlin.math.abs

fun main() {
    var frontCases = 0
    for (rotation in listOf(-90, 0, 90, 180, 270, 360, 450)) {
        for (u in listOf(0f, 0.2f, 0.5f, 0.8f, 1f)) {
            for (v in listOf(0f, 0.3f, 0.5f, 0.7f, 1f)) {
                // Independent original selfie recipe: preserve existing output.
                val x = 1f - u
                val original = when (((rotation % 360) + 360) % 360) {
                    90 -> v to 1f - x
                    180 -> 1f - x to 1f - v
                    270 -> 1f - v to x
                    else -> x to v
                }
                val expected = 1f - original.first to 1f - original.second
                val actual = CameraUvTransform.textureUv(u, v, rotation, true, true, true)
                check(actual == expected) { "Selfie regression: $rotation $u $v" }
                frontCases++
            }
        }
    }
    // Current rear stream advertises rotation 0: U must increase left to right.
    val left = CameraUvTransform.textureUv(0f, 0.5f, 0, false, true, true)
    val right = CameraUvTransform.textureUv(1f, 0.5f, 0, false, true, true)
    check(left.first == 0f && right.first == 1f)
    for (angle in listOf(0, 90, 180, 270)) {
        val (s, t) = CameraUvTransform.sensorUv(0.2f, 0.3f, angle, false)
        val uv = CameraUvTransform.textureUv(0.2f, 0.3f, angle, false, true, true)
        check(uv.first == s && abs(uv.second - (1f - t)) < 1e-6f)
    }
    check(CameraUvTransform.sensorUv(0f, 0f, 90, false) == (0f to 1f))
    check(CameraUvTransform.sensorUv(0f, 0f, 270, false) == (1f to 0f))
    println("PASS: $frontCases unchanged selfie mappings; unmirrored rear U; quarter-turn rotations")
}
