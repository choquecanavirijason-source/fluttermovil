package com.example.test_face.render

import android.util.Log
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult

/**
 * Orquesta, para un frame de MediaPipe, el cálculo de la transformación 3D
 * final de cada ojo: pose de cabeza → landmarks del ojo → ancla → plano →
 * transformación. Stateless — el único estado (suavizado, tamaño natural)
 * vive en cada [EyeModelSlot], que el llamador ([LashRenderer]) le pasa por
 * parámetro y aplica al [io.github.sceneview.node.ModelNode] correspondiente.
 *
 * [camera] es la [CameraProjection] real extraída de `SceneView.cameraNode`
 * por [LashRenderer] — necesaria para que [EyeTransformCalculator] des-
 * proyecte con la perspectiva real en vez de un mapeo lineal (Fase 1 del
 * plan de motor).
 */
object FaceRenderPipeline {

    data class Result(val left: EyeTransform?, val right: EyeTransform?)

    fun compute(
        result: FaceLandmarkerResult,
        imageWidth: Int,
        imageHeight: Int,
        leftNaturalSpan: Float,
        rightNaturalSpan: Float,
        camera: CameraProjection,
    ): Result? {
        if (result.faceLandmarks().isEmpty()) {
            Log.v(TAG, "compute: sin landmarks (rostro no detectado en este frame)")
            return null
        }
        val landmarks: List<NormalizedLandmark> = result.faceLandmarks()[0]

        // La pose 3D completa (facialTransformationMatrixes) es lo ideal,
        // pero el anclaje NO debe depender enteramente de esa única
        // capacidad de MediaPipe: si no está disponible, se sigue
        // posicionando/orientando con los landmarks 2D del ojo (siempre
        // presentes con rostro detectado) vía una pose neutra de respaldo —
        // así el modelo nunca deja de mostrarse solo porque falte la matriz.
        val matricesOptional = result.facialTransformationMatrixes()
        val headPose = if (matricesOptional.isPresent && matricesOptional.get().isNotEmpty()) {
            EyePoseEstimator.fromMediaPipeMatrix(matricesOptional.get()[0])
        } else {
            null
        } ?: run {
            Log.w(TAG, "facialTransformationMatrixes no disponible — usando pose de respaldo (solo 2D)")
            EyePoseEstimator.fallback()
        }

        val iw = imageWidth.toFloat()
        val ih = imageHeight.toFloat()

        val left = computeEye(
            landmarks, FaceLandmarkIndices.LEFT_EYE_RING, FaceLandmarkIndices.LEFT_IRIS,
            headPose, iw, ih, leftNaturalSpan, camera, RendererConfiguration.LEFT_EYE_X_NUDGE,
        )
        val right = computeEye(
            landmarks, FaceLandmarkIndices.RIGHT_EYE_RING, FaceLandmarkIndices.RIGHT_IRIS,
            headPose, iw, ih, rightNaturalSpan, camera, RendererConfiguration.RIGHT_EYE_X_NUDGE,
        )
        Log.v(TAG, "compute OK left=${left != null} right=${right != null} imageWidth=$imageWidth imageHeight=$imageHeight")
        return Result(left, right)
    }

    private fun computeEye(
        landmarks: List<NormalizedLandmark>,
        ringIndices: IntArray,
        irisIndices: IntArray,
        headPose: HeadPose,
        imageWidth: Float,
        imageHeight: Float,
        naturalSpan: Float,
        camera: CameraProjection,
        xNudgeNormalized: Float,
    ): EyeTransform? {
        val eyeLandmarks = EyeLandmarks.from(landmarks, ringIndices, irisIndices, imageWidth, imageHeight)
            ?: return null
        val anchor = EyeAnchorCalculator.compute(eyeLandmarks) ?: return null
        val plane = EyePlaneCalculator.compute(headPose, eyeLandmarks, anchor)
        val transform = EyeTransformCalculator.compute(
            headPose, plane, anchor, imageWidth, imageHeight, naturalSpan, camera, xNudgeNormalized,
        )
        return transform.copy(opennessRatio = eyeLandmarks.opennessRatio)
    }

    private const val TAG = "FaceRenderPipeline"
}
