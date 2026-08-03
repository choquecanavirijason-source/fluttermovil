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
        /** [EyeModelSlot.rootLocalY] de cada ojo — ver [EyeTransformCalculator]. */
        leftRootLocalY: Float = 0f,
        rightRootLocalY: Float = 0f,
    ): Result? {
        if (result.faceLandmarks().isEmpty()) return null
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
            headPose, iw, ih, leftNaturalSpan, camera, RendererConfiguration.LEFT_EYE_X_NUDGE, leftRootLocalY,
        )
        val right = computeEye(
            landmarks, FaceLandmarkIndices.RIGHT_EYE_RING, FaceLandmarkIndices.RIGHT_IRIS,
            headPose, iw, ih, rightNaturalSpan, camera, RendererConfiguration.RIGHT_EYE_X_NUDGE, rightRootLocalY,
        )
        // Log.v eliminado — corría en CADA frame y agregaba latencia I/O
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
        rootLocalY: Float,
    ): EyeTransform? {
        val eyeLandmarks = EyeLandmarks.from(landmarks, ringIndices, irisIndices, imageWidth, imageHeight)
            ?: return null
        val anchor = EyeAnchorCalculator.compute(eyeLandmarks, imageWidth) ?: return null
        val plane = EyePlaneCalculator.compute(headPose, eyeLandmarks, anchor)
        val transform = EyeTransformCalculator.compute(
            headPose, plane, anchor, imageWidth, imageHeight, naturalSpan, camera, xNudgeNormalized, rootLocalY,
        )
        // Curva del párpado superior para el doblado del mesh (ver
        // LashMeshBender) — se ajusta acá porque eyeLandmarks/anchor ya
        // están calculados en este punto, sin duplicar ese trabajo.
        // Origen = anchor.lidCenter (centroide SIN el shift de
        // NOSE_AVOID_SHIFT), NO anchor.point — ver la nota de
        // EyeAnchorCalculator (2026-08-02): ajustar la curva alrededor del
        // ancla de render (desplazada) dejaba casi todos los vértices del
        // mesh fuera del rango que la curva realmente ajustó, cayendo en la
        // extrapolación lineal de LashLineCurve en vez de la parábola real
        // — eso se veía como pestaña recta/sin doblar.
        val curve = LashLineCurve.fit(eyeLandmarks.upperLid, anchor.lidCenter, anchor.upperLidTangent)
        return transform.copy(
            opennessRatio = eyeLandmarks.opennessRatio,
            lashLineCurve = curve,
            eyeWidthPx = anchor.widthPx,
            lashCurveAnchorOffsetPx = anchor.lashCurveAnchorOffsetPx,
        )
    }

    private const val TAG = "FaceRenderPipeline"
}
