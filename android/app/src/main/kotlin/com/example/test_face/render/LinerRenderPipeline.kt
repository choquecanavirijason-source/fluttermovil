package com.example.test_face.render

import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult

/**
 * Orquesta, para el delineado, el mismo cálculo por ojo que
 * [FaceRenderPipeline] hace para las pestañas — a propósito DUPLICADO en vez
 * de parametrizar [FaceRenderPipeline] (ver plan Fase 4: "duplicar
 * esqueleto, no tocar código de pestañas ya probado"), para que
 * [RendererConfiguration.EYELINER_ANCHOR_FROM_FACE_MESH] sea independiente
 * de [RendererConfiguration.LASH_ANCHOR_FROM_FACE_MESH] sin editar ese
 * archivo. Reutiliza SIN cambios [EyeAnchorCalculator]/[EyePlaneCalculator]/
 * [EyeTransformCalculator]/[MeshEyeTransformCalculator]/[LashLineCurve] — la
 * única diferencia real con [FaceRenderPipeline] es de dónde lee el flag, y
 * que acá no hay bitmap/[LashEdgeDetector] (el delineado no lo necesita,
 * no tiene detección de borde real todavía).
 */
object LinerRenderPipeline {

    data class Result(val left: EyeTransform?, val right: EyeTransform?)

    fun compute(
        result: FaceLandmarkerResult,
        imageWidth: Int,
        imageHeight: Int,
        leftNaturalSpan: Float,
        rightNaturalSpan: Float,
        camera: CameraProjection,
        leftRootLocalY: Float = 0f,
        rightRootLocalY: Float = 0f,
        styleConfig: LashStyleConfig = LashStyleConfig.DEFAULT,
    ): Result? {
        if (result.faceLandmarks().isEmpty()) return null
        val landmarks: List<NormalizedLandmark> = result.faceLandmarks()[0]

        val matricesOptional = result.facialTransformationMatrixes()
        val headPose = if (matricesOptional.isPresent && matricesOptional.get().isNotEmpty()) {
            EyePoseEstimator.fromMediaPipeMatrix(matricesOptional.get()[0])
        } else {
            null
        } ?: EyePoseEstimator.fallback()

        val iw = imageWidth.toFloat()
        val ih = imageHeight.toFloat()

        val left = computeEye(
            landmarks, FaceLandmarkIndices.LEFT_EYE_RING,
            FaceLandmarkIndices.LEFT_EYE_MEDIAL_CANTHUS, FaceLandmarkIndices.LEFT_EYE_LATERAL_CANTHUS,
            FaceLandmarkIndices.LEFT_EYE_UPPER_APEX,
            headPose, iw, ih, leftNaturalSpan, camera, leftRootLocalY, styleConfig,
        )
        val right = computeEye(
            landmarks, FaceLandmarkIndices.RIGHT_EYE_RING,
            FaceLandmarkIndices.RIGHT_EYE_MEDIAL_CANTHUS, FaceLandmarkIndices.RIGHT_EYE_LATERAL_CANTHUS,
            FaceLandmarkIndices.RIGHT_EYE_UPPER_APEX,
            headPose, iw, ih, rightNaturalSpan, camera, rightRootLocalY, styleConfig,
        )
        return Result(left, right)
    }

    private fun computeEye(
        landmarks: List<NormalizedLandmark>,
        ringIndices: IntArray,
        medialCanthusIndex: Int,
        lateralCanthusIndex: Int,
        upperApexIndex: Int,
        headPose: HeadPose,
        imageWidth: Float,
        imageHeight: Float,
        naturalSpan: Float,
        camera: CameraProjection,
        rootLocalY: Float,
        styleConfig: LashStyleConfig,
    ): EyeTransform? {
        // El delineado no usa iris — EyeLandmarks.from() acepta un arreglo
        // vacío y simplemente devuelve iris=null (ver esa clase).
        val eyeLandmarks = EyeLandmarks.from(landmarks, ringIndices, IntArray(0), imageWidth, imageHeight)
            ?: return null
        val anchor = EyeAnchorCalculator.compute(eyeLandmarks, imageWidth, styleConfig) ?: return null
        val transform = if (RendererConfiguration.EYELINER_ANCHOR_FROM_FACE_MESH) {
            MeshEyeTransformCalculator.compute(
                landmarks, medialCanthusIndex, lateralCanthusIndex, upperApexIndex,
                camera, headPose, naturalSpan, rootLocalY, styleConfig,
            ) ?: return null
        } else {
            val plane = EyePlaneCalculator.compute(headPose, eyeLandmarks, anchor)
            // xNudgeNormalized=0f: el delineado no tiene su propio nudge de
            // calibración por dispositivo todavía (los de pestañas,
            // RendererConfiguration.LEFT/RIGHT_EYE_X_NUDGE, hoy también
            // están en 0 — reevaluar si hace falta separarlos cuando se
            // calibre en dispositivo real).
            EyeTransformCalculator.compute(
                headPose, plane, anchor, imageWidth, imageHeight, naturalSpan, camera, 0f, rootLocalY,
            )
        }
        val curve = LashLineCurve.fit(eyeLandmarks.upperLid, anchor.point, anchor.upperLidTangent)
        return transform.copy(
            opennessRatio = eyeLandmarks.opennessRatio,
            lashLineCurve = curve,
            eyeWidthPx = anchor.widthPx,
        )
    }
}
