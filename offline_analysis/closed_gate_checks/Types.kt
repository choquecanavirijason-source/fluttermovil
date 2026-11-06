package com.example.test_face.render
data class ImagePoint(val x:Float,val y:Float)
object RendererConfiguration {
const val EYE_BLINK_CLOSED_ABOVE = 0.50f
const val EYE_BLINK_OPEN_BELOW = 0.30f
const val EYE_CLOSED_OPENNESS_THRESHOLD = 0.12f
const val EYE_GEO_CLOSED_RATIO = 0.135f
const val EYE_GEO_OPEN_RATIO = 0.19f
const val OPENNESS_BASELINE_DECAY = 0.9995f
const val OPENNESS_BASELINE_RISE = 0.15f
const val OPENNESS_CLOSED_FRACTION = 0.30f
const val OPENNESS_OPEN_FRACTION = 0.60f
const val OPENNESS_WARMUP_SAMPLES = 15
const val SHAPE_TRUST_DROP_BELOW = 0.25f
const val SHAPE_TRUST_RESTORE_ABOVE = 0.45f
const val LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER = 0.5f
}
