package com.example.test_face.render

/**
 * Índices canónicos de la topología de 478 puntos de MediaPipe Face
 * Landmarker, reutilizables por cualquier feature de AR facial (pestañas
 * hoy; cejas, labios, etc. más adelante) sin tener que volver a buscarlos.
 *
 * Los anillos de ojo son el conjunto completo de 16 puntos (párpado superior
 * + inferior) — superset del subconjunto de 8 puntos que ya usa
 * [com.example.test_face.EyeTrackingResultMapper] para el contrato con
 * Flutter (ese contrato no cambia).
 */
object FaceLandmarkIndices {
    val LEFT_EYE_RING = intArrayOf(33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246)
    val RIGHT_EYE_RING = intArrayOf(362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398)

    val LEFT_IRIS = intArrayOf(468, 469, 470, 471, 472)
    val RIGHT_IRIS = intArrayOf(473, 474, 475, 476, 477)

    // ── Fase 2 (MeshEyeTransformCalculator): 3 puntos por ojo para derivar
    // posición/rotación/escala directo de la malla de 468 puntos, en vez de
    // pose de cabeza + residuo 2D. Ya están incluidos en LEFT/RIGHT_EYE_RING
    // de arriba — se nombran acá aparte porque cumplen un ROL distinto (base
    // ortonormal 3D, no el anillo completo). Son de los landmarks más
    // estándar/citados de MediaPipe (usados en cualquier cálculo de EAR).
    const val LEFT_EYE_MEDIAL_CANTHUS = 133
    const val LEFT_EYE_LATERAL_CANTHUS = 33
    const val LEFT_EYE_UPPER_APEX = 159

    const val RIGHT_EYE_MEDIAL_CANTHUS = 362
    const val RIGHT_EYE_LATERAL_CANTHUS = 263
    const val RIGHT_EYE_UPPER_APEX = 386
}
