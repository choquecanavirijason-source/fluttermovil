package com.example.test_face

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import com.google.mediapipe.framework.image.BitmapExtractor
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult

class FaceLandmarkerHelper(
    private val context: Context,
    /** [Map] con el contrato 2D que ya consume Flutter, el [FaceLandmarkerResult]
     * crudo (landmarks + matriz de transformación facial) para el motor de
     * render 3D nativo (ver paquete `render`), y el [Bitmap] EXACTO que
     * MediaPipe analizó para este resultado (vía [BitmapExtractor], no un
     * bitmap guardado aparte que podría no corresponder al mismo frame) —
     * lo usa [com.example.test_face.render.LashEdgeDetector] para anclar el
     * modelo 3D sobre la pestaña real visible, no solo sobre el landmark
     * estimado. `null` si el image no envuelve un Bitmap (no debería pasar
     * con [com.google.mediapipe.framework.image.BitmapImageBuilder], que es
     * como se construye en [com.example.test_face.CameraXManager]). */
    private val onResult: (Map<String, Any?>, FaceLandmarkerResult, Bitmap?) -> Unit,
    private val onError: (String) -> Unit
) {
    private var faceLandmarker: FaceLandmarker? = null

    // Instancia propia del mapper para que pueda mantener estado EMA
    // entre llamadas (ver EyeTrackingResultMapper — ahora es class, no object).
    private val mapper = EyeTrackingResultMapper()

    /**
     * Intenta GPU primero: la inferencia de FaceLandmarker con
     * `outputFacialTransformationMatrixes(true)` en CPU agrega decenas de ms
     * de latencia por frame antes de que el resultado llegue al motor de
     * render — eso es retraso que ningún filtro de suavizado puede
     * compensar (ver `RendererConfiguration`, sección de suavizado
     * temporal: el filtro solo puede suavizar datos que ya llegaron). Si el
     * delegado GPU falla al inicializar en este dispositivo (poco común,
     * pero MediaPipe no lo garantiza en todo el parque Android), se cae a
     * CPU — igual que el comportamiento anterior, así que nunca se pierde
     * la capacidad de arrancar por esto.
     */
    fun setup() {
        try {
            context.assets.open(MODEL_ASSET).use { /* ensure packaged */ }
        } catch (e: Exception) {
            Log.e(TAG, "FaceLandmarker init failed (modelo no empaquetado)", e)
            onError(e.message ?: "No se pudo inicializar FaceLandmarker")
            return
        }

        faceLandmarker = try {
            buildLandmarker(Delegate.GPU).also { Log.i(TAG, "Delegado GPU activo (diagnóstico flote)") }
        } catch (e: Exception) {
            Log.w(TAG, "Delegado GPU no disponible en este dispositivo, fallback a CPU", e)
            try {
                buildLandmarker(Delegate.CPU)
            } catch (e2: Exception) {
                Log.e(TAG, "FaceLandmarker init failed (CPU fallback)", e2)
                onError(e2.message ?: "No se pudo inicializar FaceLandmarker")
                null
            }
        }
    }

    private fun buildLandmarker(delegate: Delegate): FaceLandmarker {
        val baseOptions = BaseOptions.builder()
            .setDelegate(delegate)
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
                try {
                    // BitmapExtractor.extract() sobre el MISMO `image` que
                    // MediaPipe acaba de analizar para `result` — garantiza
                    // que el bitmap corresponde EXACTO a este resultado, sin
                    // depender de un bitmap guardado aparte que podría
                    // pertenecer a un frame distinto (ver CameraXManager).
                    // Extraído ANTES de EyeTrackingResultMapper.map() porque
                    // ese mapper también lo usa (para exponer a Flutter
                    // dónde detecta LashEdgeDetector la pestaña real).
                    val bitmap = try {
                        BitmapExtractor.extract(image)
                    } catch (e: Exception) {
                        Log.w(TAG, "BitmapExtractor.extract falló — detección de pestaña real desactivada para este frame", e)
                        null
                    }
                    val mapped = mapper.map(
                        result,
                        image.width,
                        image.height,
                        bitmap,
                    )
                    onResult(mapped, result, bitmap)
                } catch (e: Exception) {
                    Log.e(TAG, "Exception in result listener", e)
                    onError(e.message ?: "Error processing FaceLandmarker result")
                }
            }
            .setErrorListener { error ->
                onError(error.message ?: "Unknown error")
            }
            .build()

        return FaceLandmarker.createFromOptions(context, options)
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