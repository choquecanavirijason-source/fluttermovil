package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3

/**
 * Única fuente de verdad para todos los parámetros ajustables del motor de
 * renderizado de pestañas 3D. Ajustar SOLO acá — ninguna otra clase del
 * paquete `render` debe declarar constantes de tuning propias.
 */
object RendererConfiguration {

    // ── Suavizado temporal: One Euro Filter (Casiez, Roussel & Vogel 2012) ───
    const val ONE_EURO_D_CUTOFF = 1.0f

    const val POSITION_MIN_CUTOFF = 1.0f
    const val POSITION_BETA = 0.3f // Si notas vibración, reduce a 0.2f 

    const val ROTATION_MIN_CUTOFF = 1.0f
    const val ROTATION_BETA = 0.15f

    const val SCALE_MIN_CUTOFF = 1.0f
    const val SCALE_BETA = 0.05f

    // ── Profundidad dinámica (reemplaza FIXED_DEPTH) ──────────────────────────
    const val MIN_DEPTH = -2.2f
    const val MAX_DEPTH = -0.35f

    const val FACE_DISTANCE_MULTIPLIER = 1.0f

    // ── Escala del modelo de pestañas ──────────────────────────────────────────
    const val WIDTH_MULTIPLIER = 1.65f

    /** Ajustado de 0.14f a 0.11f para bajar el ancla al borde del párpado[cite: 54]. */
    const val HEIGHT_OFFSET = 0.53f

    const val HEAD_TILT_MULTIPLIER = 1.0f

   // ── Corrección fina por ojo (calibración en dispositivo) ─────────────────────
    /** * Rango efectivo: [-0.05f, 0.05f]. 
     * -0.02f es un movimiento sutil pero firme hacia la sien.
     */
    
   const val RIGHT_EYE_X_NUDGE = 0.08f  // Positivo para mover a la derecha (sien)
   const val LEFT_EYE_X_NUDGE = -0.08f  // Negativo para mover a la izquierda (sien)

    
    // ── Apertura del ojo / parpadeo ─────────────
    const val EYE_CLOSED_OPENNESS_THRESHOLD = 0.12f
    const val EYE_OPEN_OPENNESS_THRESHOLD = 0.22f

    // ── Iluminación de estudio sintética ──────────────────────
    const val INDIRECT_LIGHT_INTENSITY = 15000f
    const val KEY_LIGHT_INTENSITY = 100000f

    val KEY_LIGHT_COLOR = Float3(1f, 0.97f, 0.90f)
    val KEY_LIGHT_DIRECTION = Float3(-0.35f, -0.7f, -0.6f)

    // ── Calidad de render (Filament View) ────────────────────────────────────────
    const val MSAA_SAMPLE_COUNT = 4
}