package com.example.test_face.render

/** Coordinates shared by camera rotation and the external texture sampling. */
object CameraUvTransform {
    fun sensorUv(u: Float, v: Float, rotationDegrees: Int, mirror: Boolean): Pair<Float, Float> {
        val x = if (mirror) 1f - u else u
        return when (((rotationDegrees % 360) + 360) % 360) {
            90 -> v to 1f - x
            180 -> 1f - x to 1f - v
            270 -> 1f - v to x
            else -> x to v
        }
    }

    fun textureUv(
        u: Float, v: Float, rotationDegrees: Int, mirror: Boolean,
        flipTextureU: Boolean, flipTextureV: Boolean,
    ): Pair<Float, Float> {
        val (s, t) = sensorUv(u, v, rotationDegrees, mirror)
        // The horizontal correction was calibrated for the selfie path.
        // Applying it to the unmirrored rear camera reverses panning and
        // displays the opposite side from the analysis landmarks.
        return (if (flipTextureU && mirror) 1f - s else s) to
            (if (flipTextureV) 1f - t else t)
    }
}
