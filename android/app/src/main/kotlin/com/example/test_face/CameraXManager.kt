package com.example.test_face

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.util.Size
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.example.test_face.render.LashRenderer
import com.google.mediapipe.framework.image.BitmapImageBuilder
import io.flutter.plugin.common.MethodChannel
import io.github.sceneview.SceneView
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Coordinador delgado: solo maneja el ciclo de vida de CameraX (bind/unbind,
 * selección de cámara, orientación del frame) y el puente con MediaPipe. NO
 * contiene matemática de render — eso vive enteramente en
 * [com.example.test_face.render.LashRenderer] y el resto del paquete
 * `render` (ver plan de implementación, "CameraXManager deja de tener
 * lógica de render").
 */
class CameraXManager(
    private val activity: Activity,
    private val onTrackingResult: (Map<String, Any?>) -> Unit,
    private val onError: (String) -> Unit,
) {
    private val mainHandler = Handler(Looper.getMainLooper())

    private val lashRenderer = LashRenderer(activity, mainHandler)

    private val helper = FaceLandmarkerHelper(
        context = activity,
        onResult = { data, rawResult ->
            onTrackingResult(data) // sigue enviando datos 2D a Flutter, sin cambios
            val imageWidth = (data["imageWidth"] as? Int) ?: 0
            val imageHeight = (data["imageHeight"] as? Int) ?: 0
            if (data["faceDetected"] == true && imageWidth > 0 && imageHeight > 0) {
                lashRenderer.onFaceResult(rawResult, imageWidth, imageHeight)
            } else {
                lashRenderer.onFaceLost()
            }
        },
        onError = onError,
    )

    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private val mainExecutor by lazy { ContextCompat.getMainExecutor(activity) }

    @Volatile
    private var cameraProvider: ProcessCameraProvider? = null

    private var lensFacing = CameraSelector.LENS_FACING_FRONT
    private var previewView: PreviewView? = null

    private var imageAnalysisUseCase: ImageAnalysis? = null

    private var videoCapture: VideoCapture<Recorder>? = null
    @Volatile private var activeRecording: Recording? = null
    @Volatile private var pendingStopResult: MethodChannel.Result? = null

    private val stopped = AtomicBoolean(true)
    private val bindGeneration = AtomicLong(0L)
    private var pendingBindRunnable: Runnable? = null

    /** Último frame orientado/espejado del análisis; fuente de [captureFrame]. */
    @Volatile
    private var latestFrameBitmap: Bitmap? = null

    fun attachPreview(view: PreviewView) {
        Log.i(TAG, "attachPreview manager=${System.identityHashCode(this)} view=${System.identityHashCode(view)}")
        previewView = view
        mainHandler.post {
            if (!stopped.get()) {
                scheduleRebind()
            }
        }
    }

    /**
     * [view] es la instancia que se está desmontando. Flutter puede crear el
     * nuevo `PlatformView` (y llamar [attachPreview] con la instancia nueva)
     * ANTES de que el anterior termine de destruirse y dispare este
     * `dispose()` — sin esta comprobación de identidad, ese `detach` tardío
     * anulaba la referencia recién asignada y la cámara se quedaba sin
     * preview (pantalla negra) aunque el nuevo `PlatformView` sí existiera.
     */
    fun detachPreview(view: PreviewView) {
        Log.i(
            TAG,
            "detachPreview manager=${System.identityHashCode(this)} view=${System.identityHashCode(view)} " +
                "isCurrent=${previewView === view}",
        )
        if (previewView !== view) return
        previewView = null
        mainHandler.post {
            if (!stopped.get()) {
                scheduleRebind()
            }
        }
    }

    fun attachSceneView(view: SceneView) {
        Log.i(TAG, "attachSceneView manager=${System.identityHashCode(this)} view=${System.identityHashCode(view)}")
        lashRenderer.attachSceneView(view)
    }

    /** Ver la nota de [detachPreview] — misma protección para el SceneView. */
    fun detachSceneView(view: SceneView) {
        Log.i(TAG, "detachSceneView manager=${System.identityHashCode(this)} view=${System.identityHashCode(view)}")
        lashRenderer.detachSceneView(view)
    }

    /** Ver [LashRenderer.loadEyeModels]. */
    fun loadEyeModels(leftPath: String?, rightPath: String?) {
        Log.i(TAG, "loadEyeModels manager=${System.identityHashCode(this)} left=$leftPath right=$rightPath")
        lashRenderer.loadEyeModels(leftPath, rightPath)
    }

    fun start() {
        analysisExecutor.execute {
            if (helper.getLandmarker() == null) {
                helper.setup()
            }
            if (helper.getLandmarker() == null) {
                return@execute
            }
            mainHandler.post {
                stopped.set(false)
                scheduleRebind()
            }
        }
    }

    fun stop(result: MethodChannel.Result? = null) {
        stopped.set(true)
        cancelPendingBind()
        bindGeneration.incrementAndGet()
        lashRenderer.onFaceLost()

        // Corta cualquier grabación en curso antes de desenlazar la cámara,
        // para que el .mp4 quede finalizado en vez de truncado por unbindAll().
        activeRecording?.stop()
        activeRecording = null
        pendingStopResult = null

        val phaseClear = Runnable {
            try {
                imageAnalysisUseCase?.clearAnalyzer()
            } catch (_: Exception) {
            }
            imageAnalysisUseCase = null

            val phaseUnbind = Runnable {
                try {
                    try {
                        cameraProvider?.unbindAll()
                    } catch (_: Exception) {
                    }
                    cameraProvider = null
                    helper.close()
                } finally {
                    result?.success(null)
                }
            }
            mainHandler.postDelayed(phaseUnbind, STOP_UNBIND_DELAY_MS)
        }
        mainHandler.post(phaseClear)
    }

    fun switchCamera() {
        lensFacing =
            if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
                CameraSelector.LENS_FACING_BACK
            } else {
                CameraSelector.LENS_FACING_FRONT
            }
        mainHandler.post {
            if (!stopped.get() && helper.getLandmarker() != null) {
                scheduleRebind()
            }
        }
    }

    fun refreshPreviewBind() {
        mainHandler.post {
            if (stopped.get()) return@post
            if (previewView == null) return@post
            scheduleRebind()
        }
    }

    /**
     * Devuelve el último frame de cámara como JPEG, con la misma orientación y
     * espejo que ve la usuaria en el preview. Flutter no puede capturar el
     * PlatformView de CameraX ([android.view.TextureView]) con
     * RepaintBoundary.toImage, así que la foto se toma aquí.
     *
     * La compresión corre en [analysisExecutor]; el result se responde en el
     * hilo principal como exige el MethodChannel.
     */
    fun captureFrame(result: MethodChannel.Result) {
        val bmp = latestFrameBitmap
        if (bmp == null || bmp.isRecycled) {
            result.success(null)
            return
        }
        analysisExecutor.execute {
            val bytes = try {
                val out = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.JPEG, 92, out)
                out.toByteArray()
            } catch (_: Exception) {
                null
            }
            mainHandler.post { result.success(bytes) }
        }
    }

    /**
     * Arranca la grabación de video local (sin audio) usando el mismo
     * [VideoCapture] enlazado en [applyBinding]. El archivo queda en
     * almacenamiento privado de la app (no requiere permisos en runtime).
     */
    fun startRecording(result: MethodChannel.Result) {
        val vc = videoCapture
        if (vc == null) {
            result.error("NO_CAMERA", "La cámara aún no está lista", null)
            return
        }
        if (activeRecording != null) {
            result.success(null)
            return
        }

        val moviesDir = activity.getExternalFilesDir(Environment.DIRECTORY_MOVIES)
        if (moviesDir != null && !moviesDir.exists()) moviesDir.mkdirs()
        val fileName =
            "beauty_tech_${SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())}.mp4"
        val outputFile = File(moviesDir, fileName)
        val outputOptions = FileOutputOptions.Builder(outputFile).build()

        try {
            activeRecording = vc.output
                .prepareRecording(activity, outputOptions)
                .start(mainExecutor) { event ->
                    if (event is VideoRecordEvent.Finalize) {
                        activeRecording = null
                        val stopResult = pendingStopResult
                        pendingStopResult = null
                        if (stopResult != null) {
                            if (event.hasError()) {
                                stopResult.error(
                                    "RECORDING_FAILED",
                                    event.cause?.message ?: "Error al finalizar la grabación",
                                    null,
                                )
                            } else {
                                stopResult.success(outputFile.absolutePath)
                            }
                        }
                    }
                }
            result.success(null)
        } catch (e: Exception) {
            result.error("RECORDING_START_FAILED", e.message ?: "No se pudo iniciar la grabación", null)
        }
    }

    /** Detiene la grabación en curso; responde cuando [VideoRecordEvent.Finalize] confirma el archivo. */
    fun stopRecording(result: MethodChannel.Result) {
        val rec = activeRecording
        if (rec == null) {
            result.success(null)
            return
        }
        pendingStopResult = result
        rec.stop()
    }

    private fun scheduleRebind() {
        if (stopped.get()) return
        cancelPendingBind()
        val gen = bindGeneration.incrementAndGet()
        val r = Runnable {
            if (stopped.get()) return@Runnable
            if (gen != bindGeneration.get()) return@Runnable
            bindCameraUseCasesNow()
        }
        pendingBindRunnable = r
        mainHandler.postDelayed(r, REBIND_DELAY_MS)
    }

    private fun cancelPendingBind() {
        pendingBindRunnable?.let { mainHandler.removeCallbacks(it) }
        pendingBindRunnable = null
    }

    private fun bindCameraUseCasesNow() {
        if (stopped.get()) return
        val lifecycleOwner = activity as? LifecycleOwner ?: run {
            onError("Activity no es LifecycleOwner")
            return
        }

        val cached = cameraProvider
        if (cached != null) {
            applyBinding(cached, lifecycleOwner)
            return
        }

        val future = ProcessCameraProvider.getInstance(activity)
        future.addListener(
            {
                if (stopped.get()) return@addListener
                try {
                    val provider = future.get()
                    cameraProvider = provider
                    applyBinding(provider, lifecycleOwner)
                } catch (e: Exception) {
                    onError(e.message ?: "No se pudo abrir la cámara")
                }
            },
            mainExecutor,
        )
    }

    private fun applyBinding(
        provider: ProcessCameraProvider,
        lifecycleOwner: LifecycleOwner,
    ) {
        if (stopped.get()) return
        try {
            provider.unbindAll()

            val rotation = displayRotation(activity)

            val imageAnalysis =
                ImageAnalysis.Builder()
                    .setTargetRotation(rotation)
                    .setResolutionSelector(analysisResolutionSelector)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .build()

            imageAnalysis.setAnalyzer(analysisExecutor) { imageProxy ->
                processFrame(imageProxy)
            }
            imageAnalysisUseCase = imageAnalysis

            // El Recorder/VideoCapture se crea una única vez y se reenlaza en cada
            // rebind (misma instancia) para no perder la referencia usada por
            // startRecording/stopRecording.
            val vc = videoCapture ?: VideoCapture.withOutput(
                Recorder.Builder()
                    .setQualitySelector(QualitySelector.from(Quality.HD))
                    .build(),
            ).also { videoCapture = it }

            val selector =
                CameraSelector.Builder()
                    .requireLensFacing(lensFacing)
                    .build()

            val pv = previewView
            if (pv != null) {
                val preview =
                    Preview.Builder()
                        .setTargetRotation(rotation)
                        .setResolutionSelector(previewResolutionSelector)
                        .build()
                preview.setSurfaceProvider(pv.surfaceProvider)
                provider.bindToLifecycle(
                    lifecycleOwner,
                    selector,
                    preview,
                    imageAnalysis,
                    vc,
                )
            } else {
                provider.bindToLifecycle(
                    lifecycleOwner,
                    selector,
                    imageAnalysis,
                    vc,
                )
            }
        } catch (e: Exception) {
            onError(e.message ?: "No se pudo enlazar la cámara")
        }
    }

    private fun processFrame(imageProxy: ImageProxy) {
        val landmarker = helper.getLandmarker()
        if (landmarker == null || stopped.get()) {
            imageProxy.close()
            return
        }

        try {
            val bitmap =
                Bitmap.createBitmap(
                    imageProxy.width,
                    imageProxy.height,
                    Bitmap.Config.ARGB_8888,
                )
            imageProxy.planes[0].buffer.rewind()
            bitmap.copyPixelsFromBuffer(imageProxy.planes[0].buffer)

            val matrix =
                Matrix().apply {
                    postRotate(imageProxy.imageInfo.rotationDegrees.toFloat())
                    if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
                        postScale(
                            -1f,
                            1f,
                            imageProxy.width.toFloat(),
                            imageProxy.height.toFloat(),
                        )
                    }
                }
            val oriented =
                Bitmap.createBitmap(
                    bitmap,
                    0,
                    0,
                    bitmap.width,
                    bitmap.height,
                    matrix,
                    true,
                )
            if (oriented != bitmap) {
                bitmap.recycle()
            }
            latestFrameBitmap = oriented

            val mpImage = BitmapImageBuilder(oriented).build()
            val frameTimeMs = SystemClock.uptimeMillis()
            landmarker.detectAsync(mpImage, frameTimeMs)
        } catch (e: Exception) {
            onError(e.message ?: "Error procesando frame")
        } finally {
            imageProxy.close()
        }
    }

    private fun displayRotation(activity: Activity): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay.rotation
        }

    private companion object {
        private const val TAG = "CameraXManager"
        private const val REBIND_DELAY_MS = 280L
        private const val STOP_UNBIND_DELAY_MS = 220L

        /**
         * Preview: pedir resolución muy alta. Importante: [ImageAnalysis] tiene su propio
         * selector moderado; si no, CameraX suele bajar el preview al tamaño del análisis.
         */
        private val previewResolutionSelector: ResolutionSelector =
            ResolutionSelector.Builder()
                .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
                .setResolutionStrategy(
                    ResolutionStrategy(
                        Size(4032, 3024),
                        ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                    ),
                )
                .build()

        /** Análisis ML acotado: libera ancho de banda para que el preview no quede pixelado. */
        private val analysisResolutionSelector: ResolutionSelector =
            ResolutionSelector.Builder()
                .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
                .setResolutionStrategy(
                    ResolutionStrategy(
                        Size(960, 720),
                        ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER,
                    ),
                )
                .build()
    }
}
