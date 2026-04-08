package com.example.test_face

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker

class FaceLandmarkerHelper(
    private val context: Context,
    private val onResult: (Map<String, Any?>) -> Unit,
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
                .setResultListener { result, image ->
                    val mapped = EyeTrackingResultMapper.map(
                        result,
                        image.width,
                        image.height
                    )
                    onResult(mapped)
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