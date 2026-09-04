package com.example.test_face.render

import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult

/**
 * Apertura de cada ojo en `[0,1]` leída de los blendshapes de MediaPipe
 * (`eyeBlinkLeft`/`eyeBlinkRight`, habilitados en
 * [com.example.test_face.FaceLandmarkerHelper]).
 *
 * ## Por qué existe (fix de "desde abajo la pestaña no se adapta")
 *
 * La señal de cierre de párpado que usaba [OpennessTracker] era
 * [EyeLandmarks.opennessRatio]: alto/ancho del anillo del ojo MEDIDO EN LA
 * IMAGEN. Esa relación no depende solo de cuánto abriste el ojo — depende
 * también del ÁNGULO DE CÁMARA, porque al mirar el teléfono desde abajo el
 * ojo se escorza verticalmente y el alto proyectado se encoge con el coseno
 * del cabeceo.
 *
 * Había una corrección geométrica para eso
 * ([FaceRenderPipeline.foreshorteningCorrectedOpenness], dividir por
 * `cos(cabeceo)` estimado de [HeadPose]), pero es una compensación
 * aproximada y con tope: en ángulos marcados se queda corta, y entonces un
 * ojo abierto y escorzado se lee como un ojo cerrándose. La consecuencia
 * concreta, reportada en dispositivo con la cámara desde abajo: el motor
 * creía que la persona estaba parpadeando, CONGELABA la forma de la pestaña
 * (ver [LidShape]) y dejaba de adaptarla al párpado — encima de forma
 * persistente, porque la línea base de [OpennessTracker] decae muy lento
 * (~1.5 %/s) y un ángulo sostenido la mantiene mal calibrada varios
 * segundos.
 *
 * Los blendshapes salen del ajuste 3D del rostro que ya hace MediaPipe, no
 * de medir píxeles en la imagen, así que son esencialmente invariantes al
 * ángulo: `eyeBlinkX` responde a que el párpado baje, no a que la cara se
 * escorce. Con eso, la decisión de congelar deja de depender del ángulo de
 * cámara — que es lo que nunca debió haber pasado.
 *
 * ## Izquierda/derecha (ojo con esto)
 *
 * Los nombres de blendshape de MediaPipe son desde el punto de vista del
 * SUJETO: `eyeBlinkLeft` es el ojo izquierdo DE LA PERSONA. Los anillos de
 * este proyecto están nombrados al revés, por lado de IMAGEN: ver
 * [FaceLandmarkIndices], donde `LEFT_EYE_RING` arranca en los índices
 * 33/133/159 — que en la malla canónica de MediaPipe son el ojo DERECHO del
 * sujeto (el par 362/263/386 del `RIGHT_EYE_RING` es el izquierdo del
 * sujeto). Por eso [openness] cruza los dos: el ojo "LEFT" del proyecto se
 * alimenta de `eyeBlinkRight` y viceversa.
 *
 * Si esto estuviera cruzado al revés no se notaría parpadeando normal (los
 * dos ojos se cierran juntos), sólo al guiñar un ojo: se congelaría la forma
 * del ojo equivocado.
 */
object EyeBlinkBlendshapes {

    /** Nombre canónico del coeficiente de cierre del ojo IZQUIERDO DEL
     * SUJETO — o sea el ojo "RIGHT" de este proyecto (ver KDoc de clase). */
    private const val SUBJECT_LEFT_BLINK = "eyeBlinkLeft"

    /** Ojo DERECHO DEL SUJETO = ojo "LEFT" de este proyecto. */
    private const val SUBJECT_RIGHT_BLINK = "eyeBlinkRight"

    /**
     * Apertura por ojo, ya traducida a la convención de nombres de ESTE
     * proyecto (lado de imagen) y en la misma orientación que
     * [EyeLandmarks.opennessRatio]: **1 = ojo bien abierto, 0 = cerrado**.
     */
    data class Openness(val left: Float, val right: Float)

    /**
     * `null` si este resultado no trae blendshapes — porque no se habilitaron
     * al construir el `FaceLandmarker`, o porque falta alguno de los dos
     * coeficientes. El llamador debe caer al camino geométrico en ese caso
     * (ver [FaceRenderPipeline.computeEye]), no tratarlo como error.
     */
    fun openness(result: FaceLandmarkerResult): Openness? {
        val optional = result.faceBlendshapes()
        if (!optional.isPresent) return null
        val categories = optional.get().firstOrNull() ?: return null

        var subjectLeft = Float.NaN
        var subjectRight = Float.NaN
        for (category in categories) {
            when (category.categoryName()) {
                SUBJECT_LEFT_BLINK -> subjectLeft = category.score()
                SUBJECT_RIGHT_BLINK -> subjectRight = category.score()
            }
        }
        if (!subjectLeft.isFinite() || !subjectRight.isFinite()) return null

        // `score` es CIERRE (1 = ojo cerrado); acá se devuelve APERTURA, para
        // que entre a OpennessTracker en la misma orientación que la señal
        // geométrica a la que reemplaza.
        return Openness(
            left = 1f - subjectRight.coerceIn(0f, 1f),
            right = 1f - subjectLeft.coerceIn(0f, 1f),
        )
    }
}
