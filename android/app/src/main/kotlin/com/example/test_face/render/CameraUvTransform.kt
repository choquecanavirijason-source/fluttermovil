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
        // The horizontal correction was calibrated for the selfie path with a
        // buffer the producer already transformed (rotation 0: rotated AND
        // mirrored by CameraX, so the mirror above must be undone). Applying
        // it to the unmirrored rear camera reverses panning and displays the
        // opposite side from the analysis landmarks.
        //
        // In photo mode (assistant framing) the front buffer arrives
        // untransformed (1440x1080, rotation 270): the math above already
        // mirrors it, and this correction flipped it again along `s`, which
        // at 90/270 is the screen's VERTICAL axis — the preview showed
        // upside down. So it only applies to the pre-transformed buffer.
        val producerTransformed = ((rotationDegrees % 360) + 360) % 360 == 0
        return (if (flipTextureU && mirror && producerTransformed) 1f - s else s) to
            (if (flipTextureV) 1f - t else t)
    }
}
