package com.example.test_face.render

import android.util.Log
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import kotlin.math.atan2

/**
 * TEMPORAL — diagnóstico de orientación con cámara trasera / clienta
 * acostada. Filtrar logcat por `OrientDebug`. Borrar este archivo y sus dos
 * llamadas (CameraXManager, LashRenderer) cuando quede confirmado.
 *
 * Todo se loguea en coordenadas del PREVIEW (ya desrotadas), normalizadas
 * 0..1, y cada [EVERY_N] resultados para no saturar.
 */
object OrientDebug {
    const val ENABLED = true
    private const val TAG = "OrientDebug"
    private const val EVERY_N = 15
    private var frame = 0
    private var lashFrame = 0

    fun logResult(result: FaceLandmarkerResult, lensFront: Boolean, analysisRotated180: Boolean) {
        if (!ENABLED || frame++ % EVERY_N != 0) return
        val lm = result.faceLandmarks().firstOrNull() ?: return
        if (lm.size < 468) return
        fun p(i: Int) = "(%.3f,%.3f)".format(lm[i].x(), lm[i].y())
        // Frente (10) → mentón (152): con la cara derecha y≈+; cabeza abajo y≈−.
        val fx = lm[152].x() - lm[10].x()
        val fy = lm[152].y() - lm[10].y()
        // Párpado superior (159) menos inferior (145) del ojo LEFT, proyectado
        // sobre frente→mentón: NEGATIVO = el "superior" está del lado de la
        // frente (ajuste correcto); POSITIVO = malla dada vuelta.
        val lidDx = lm[159].x() - lm[145].x()
        val lidDy = lm[159].y() - lm[145].y()
        val lidAlongFace = lidDx * fx + lidDy * fy
        val blink = result.faceBlendshapes().orElse(null)?.firstOrNull()
            ?.filter { it.categoryName() == "eyeBlinkLeft" || it.categoryName() == "eyeBlinkRight" }
            ?.joinToString { "%s=%.2f".format(it.categoryName(), it.score()) }
        // Roll de la pose (eje `right` leído row-major, igual que EyePoseEstimator).
        val roll = result.facialTransformationMatrixes().orElse(null)?.firstOrNull()?.let { m ->
            Math.toDegrees(atan2(m[4].toDouble(), m[0].toDouble()))
        }
        val turns = FaceQuarterTurn.of(lm, 1f, 1f)
        Log.i(
            TAG,
            "lens=${if (lensFront) "FRONTAL" else "TRASERA"} analisisRot180=$analysisRotated180 " +
                "turns=$turns frente10=${p(10)} menton152=${p(152)} " +
                "frente→menton=(%.3f,%.3f) ".format(fx, fy) +
                "sup159=${p(159)} inf145=${p(145)} supMenosInf·frenteMenton=%.4f ".format(lidAlongFace) +
                "poseRoll=${roll?.let { "%.0f°".format(it) }} $blink",
        )
    }

    fun logLash(left: EyeTransform?, right: EyeTransform?) {
        if (!ENABLED || lashFrame++ % EVERY_N != 0) return
        fun e(t: EyeTransform?) = t?.let {
            "open=%.2f trusted=%s pos=(%.3f,%.3f)".format(it.normalizedOpenness, it.lidShapeTrusted, it.position.x, it.position.y)
        } ?: "null"
        Log.i(TAG, "lash LEFT[${e(left)}] RIGHT[${e(right)}]")
    }
}
