package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3

/**
 * Parámetros del motor de render optimizados para LATENCIA MÍNIMA.
 *
 * Filosofía: el One Euro Filter SOLO debe eliminar el micro-jitter de
 * MediaPipe, sin agregar lag perceptible. La predicción forward en
 * PoseInterpolator se encarga del resto de la compensación.
 *
 * El minCutoff alto (3.0Hz) hace que el filtro sea casi transparente:
 * señales que cambian más lento que 3Hz (movimiento lento de cabeza)
 * pasan sin casi ningún suavizado → CERO lag perceptible.
 */
object RendererConfiguration {

    // ── One Euro Filter: MÍNIMO suavizado, MÁXIMA velocidad ─────────────
    //
    // Con predicción forward adaptativa, el filtro ya NO necesita compensar
    // la latencia — solo necesita limpiar el ruido de MediaPipe.
    //
    // minCutoff = 3.0Hz → τ ≈ 53ms en reposo (solo limpia jitter)
    // Target rápido = 25Hz → τ ≈ 6.4ms (sub-frame, invisible)
    //
    // Comparación con antes:
    // - Antes: minCutoff=1.0, target=12Hz → lag de ~100ms visible
    // - Ahora: minCutoff=3.0, target=25Hz → lag de ~6ms invisible
    const val ONE_EURO_D_CUTOFF = 1.0f

    private const val FAST_MOTION_TARGET_CUTOFF_HZ = 25f

    const val POSITION_MIN_CUTOFF = 3.0f
    private const val FAST_MOTION_POSITION_VELOCITY_MPS = 1.0f
    const val POSITION_BETA =
        (FAST_MOTION_TARGET_CUTOFF_HZ - POSITION_MIN_CUTOFF) / FAST_MOTION_POSITION_VELOCITY_MPS

    const val ROTATION_MIN_CUTOFF = 2.0f
    private const val FAST_MOTION_ROTATION_VELOCITY = 1.8f
    const val ROTATION_BETA =
        (FAST_MOTION_TARGET_CUTOFF_HZ - ROTATION_MIN_CUTOFF) / FAST_MOTION_ROTATION_VELOCITY

    const val SCALE_MIN_CUTOFF = 2.0f
    private const val SCALE_TO_POSITION_BETA_RATIO = 0.05f / 0.3f
    const val SCALE_BETA = POSITION_BETA * SCALE_TO_POSITION_BETA_RATIO

    // ── Profundidad ─────────────────────────────────────────────────────
    const val MIN_DEPTH = -2.2f
    const val MAX_DEPTH = -0.35f
    const val FACE_DISTANCE_MULTIPLIER = 1.0f

    // ── Escala del modelo ───────────────────────────────────────────────
    const val WIDTH_MULTIPLIER = 1.65f
    // HEIGHT_OFFSET controla dónde queda el CENTRO del modelo 3D respecto
    // al BORDE del párpado superior (la línea de pestañas visible).
    //
    // 0.0 = centro en el borde del párpado (mitad del modelo dentro del ojo)
    // 0.3 = centro 30% de la altura del ojo ARRIBA del borde → aspecto natural
    // 0.5 = centro a media-altura del ojo por encima del borde
    //
    // Como el ojo mide ~8-10mm de altura, 0.3 equivale a ~2.5-3mm por encima
    // del borde del párpado — donde visualmente se ve el centro de las pestañas.
    const val HEIGHT_OFFSET = 0.30f
    const val HEAD_TILT_MULTIPLIER = 1.0f

    // ── Corrección por ojo ──────────────────────────────────────────────
    const val RIGHT_EYE_X_NUDGE = 0.0f
    const val LEFT_EYE_X_NUDGE = 0.0f

    // ── Parpadeo ────────────────────────────────────────────────────────
    const val EYE_CLOSED_OPENNESS_THRESHOLD = 0.12f
    const val EYE_OPEN_OPENNESS_THRESHOLD = 0.22f

    // ── Iluminación ─────────────────────────────────────────────────────
    const val INDIRECT_LIGHT_INTENSITY = 15000f
    const val KEY_LIGHT_INTENSITY = 100000f
    val KEY_LIGHT_COLOR = Float3(1f, 0.97f, 0.90f)
    val KEY_LIGHT_DIRECTION = Float3(-0.35f, -0.7f, -0.6f)

    // ── Calidad de render ───────────────────────────────────────────────
    const val MSAA_SAMPLE_COUNT = 4
}