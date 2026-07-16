package com.example.test_face

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult

class FaceLandmarkerHelper(
    private val context: Context,
    /** [Map] con el contrato 2D que ya consume Flutter, y el [FaceLandmarkerResult]
     * crudo (landmarks + matriz de transformación facial) para el motor de
     * render 3D nativo (ver paquete `render`). */
    private val onResult: (Map<String, Any?>, FaceLandmarkerResult) -> Unit,
    private val onError: (String) -> Unit
) {
    private var faceLandmarker: FaceLandmarker? = null

    fun setup() {
        try {
            context.assets.open(MODEL_ASSET).use { /* ensure packaged */ }

            val baseOptions = BaseOptions.builder()
                .setDelegate(Delegate.CPU)
                .setModelAssetPath(MODEL_ASSET)
                .build()

            val options = FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setNumFaces(1)
                .setMinFaceDetectionConfidence(0.5f)
                .setMinFacePresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setRunningMode(RunningMode.LIVE_STREAM)
                // Necesario para el motor de render 3D (paquete `render`): MediaPipe
                // resuelve la pose 3D completa de la cabeza (rotación + profundidad)
                // ajustando su modelo facial canónico — mucho más robusto que derivar
                // yaw/pitch/roll a mano desde dos landmarks.
                .setOutputFacialTransformationMatrixes(true)
                .setResultListener { result, image ->
                    val mapped = EyeTrackingResultMapper.map(
                        result,
                        image.width,
                        image.height
                    )
                    onResult(mapped, result)
                }
                .setErrorListener { error ->
                    onError(error.message ?: "Unknown error")
                }
                .build()

            faceLandmarker = FaceLandmarker.createFromOptions(context, options)
        } catch (e: Exception) {
            Log.e(TAG, "FaceLandmarker init failed", e)
            onError(e.message ?: "No se pudo inicializar FaceLandmarker")
        }
    }

    fun close() {
        faceLandmarker?.close()
        faceLandmarker = null
    }

    fun getLandmarker(): FaceLandmarker? = faceLandmarker

    private companion object {
        private const val TAG = "FaceLandmarkerHelper"
        private const val MODEL_ASSET = "face_landmarker.task"
    }
}