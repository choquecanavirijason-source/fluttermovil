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
import com.example.test_face.render.FaceMeshRenderer
import com.example.test_face.render.LashRenderer
import com.example.test_face.render.LinerRenderer
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

    /** Fase 1 del plan de migración a face-mesh (ver FaceMeshRenderer) —
     * completamente en paralelo a [lashRenderer], no interfiere con él. */
    private val faceMeshRenderer = FaceMeshRenderer(mainHandler)

    /** Fase 4 (ver plan) — segundo efecto sobre la malla, delineado. En
     * paralelo a [lashRenderer]/[faceMeshRenderer], sin depender de ninguno
     * de los dos. */
    private val linerRenderer = LinerRenderer(mainHandler)

    /** Media móvil exponencial de la latencia real de MediaPipe en ms.
     * Se usa como offset de predicción forward en PoseInterpolator para
     * compensar EXACTAMENTE la latencia de ESTE dispositivo, no un valor
     * fijo adivinado. */
    @Volatile private var smoothedLatencyMs = 35f  // seed razonable

    // ── LOG DE DIAGNÓSTICO TEMPORAL (ronda "flote") ──────────────────────
    @Volatile private var debugFrameCount = 0
    @Volatile private var debugLastResultMs = 0L

    private val helper = FaceLandmarkerHelper(
        context = activity,
        onResult = { data, rawResult, resultBitmap ->
            // Medir la latencia REAL de MediaPipe en este dispositivo
            val submitMs = lastFrameSubmitMs
            val nowMs = SystemClock.uptimeMillis()
            if (submitMs > 0L) {
                val latencyMs = (nowMs - submitMs).toFloat()
                // EMA con alpha=0.3 — se adapta en ~3-4 frames pero no salta
                // con un solo outlier
                smoothedLatencyMs = smoothedLatencyMs * 0.7f + latencyMs * 0.3f
            }
            debugFrameCount++
            if (debugFrameCount % 30 == 0) {
                val intervalMs = if (debugLastResultMs > 0L) nowMs - debugLastResultMs else -1L
                Log.i(
                    "FloteDebug",
                    "smoothedLatencyMs=$smoothedLatencyMs intervalDesde30FramesAtras=${intervalMs}ms " +
                        "fps≈${if (intervalMs > 0) 30_000f / intervalMs else -1f}",
                )
            }
            debugLastResultMs = nowMs

            // Calcular posición REAL de las pestañas con LashEdgeDetector
            // (busca el píxel más oscuro cerca de cada landmark del párpado superior)
            // y añadirla al mapa antes de enviarlo a Flutter.
            val augmentedData: Map<String, Any?> = if (resultBitmap != null && data["faceDetected"] == true) {
                fun toImagePoints(key: String): List<com.example.test_face.render.ImagePoint> =
                    (data[key] as? List<*>)?.mapNotNull { pt ->
                        val m = pt as? Map<*, *> ?: return@mapNotNull null
                        val x = (m["x"] as? Double)?.toFloat() ?: return@mapNotNull null
                        val y = (m["y"] as? Double)?.toFloat() ?: return@mapNotNull null
                        com.example.test_face.render.ImagePoint(x, y)
                    } ?: emptyList()

                fun toMapList(pts: List<com.example.test_face.render.ImagePoint>) =
                    pts.map { mapOf("x" to it.x.toDouble(), "y" to it.y.toDouble()) }

                val leftLash = com.example.test_face.render.LashEdgeDetector
                    .detectRealLashLine(resultBitmap, toImagePoints("leftUpperLid"))
                val rightLash = com.example.test_face.render.LashEdgeDetector
                    .detectRealLashLine(resultBitmap, toImagePoints("rightUpperLid"))

                data + mapOf(
                    "leftLashLine" to toMapList(leftLash),
                    "rightLashLine" to toMapList(rightLash),
                )
            } else {
                data
            }
            onTrackingResult(augmentedData)
            val imageWidth = (augmentedData["imageWidth"] as? Int) ?: 0
            val imageHeight = (augmentedData["imageHeight"] as? Int) ?: 0
            if (augmentedData["faceDetected"] == true && imageWidth > 0 && imageHeight > 0) {
                lashRenderer.onFaceResult(rawResult, imageWidth, imageHeight, smoothedLatencyMs, resultBitmap)
                faceMeshRenderer.onFaceResult(rawResult)
                linerRenderer.onFaceResult(rawResult, imageWidth, imageHeight)
            } else {
                lashRenderer.onFaceLost()
                faceMeshRenderer.onFaceLost()
                linerRenderer.onFaceLost()
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

    /** Buffer crudo (pre-rotación/espejo) reusado entre frames — nunca se
     * expone fuera de [processFrame], así que reutilizarlo en el sitio es
     * seguro y evita reasignar ~width*height*4 bytes de memoria nativa en
     * cada frame de análisis (a diferencia del bitmap "oriented", que sí se
     * expone vía [latestFrameBitmap] y por eso debe seguir siendo una
     * instantánea nueva cada vez, ver [processFrame]). */
    private var rawFrameBitmap: Bitmap? = null

    /** Timestamp (uptimeMillis) del último frame enviado a `detectAsync`,
     * para medir en logcat cuánto tarda MediaPipe en devolver el resultado
     * (ver el log de latencia en el `onResult` de [helper] arriba). */
    @Volatile
    private var lastFrameSubmitMs = 0L

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
        faceMeshRenderer.attachSceneView(view)
        linerRenderer.attachSceneView(view)
    }

    /** Ver la nota de [detachPreview] — misma protección para el SceneView. */
    fun detachSceneView(view: SceneView) {
        Log.i(TAG, "detachSceneView manager=${System.identityHashCode(this)} view=${System.identityHashCode(view)}")
        lashRenderer.detachSceneView(view)
        faceMeshRenderer.detachSceneView(view)
        linerRenderer.detachSceneView(view)
    }

    /** Ver [LashRenderer.loadEyeModels]. */
    fun loadEyeModels(leftPath: String?, rightPath: String?) {
        Log.i(TAG, "loadEyeModels manager=${System.identityHashCode(this)} left=$leftPath right=$rightPath")
        lashRenderer.loadEyeModels(leftPath, rightPath)
    }

    /** Ver [LashRenderer.setStyle]. */
    fun setLashStyle(styleId: String?) {
        Log.i(TAG, "setLashStyle manager=${System.identityHashCode(this)} styleId=$styleId")
        lashRenderer.setStyle(styleId)
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
        faceMeshRenderer.onFaceLost()
        linerRenderer.onFaceLost()

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
            val width = imageProxy.width
            val height = imageProxy.height

            var raw = rawFrameBitmap
            if (raw == null || raw.isRecycled || raw.width != width || raw.height != height) {
                raw?.recycle()
                raw = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                rawFrameBitmap = raw
            }
            imageProxy.planes[0].buffer.rewind()
            raw.copyPixelsFromBuffer(imageProxy.planes[0].buffer)

            val matrix =
                Matrix().apply {
                    postRotate(imageProxy.imageInfo.rotationDegrees.toFloat())
                    if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
                        postScale(-1f, 1f, width.toFloat(), height.toFloat())
                    }
                }

            // Crear el oriented bitmap. Intentamos reusar cuando es posible,
            // pero Bitmap.createBitmap con matrix puede cambiar las dimensiones
            // (rotación de 90°), así que usamos la API estándar y confiamos en
            // que el GC maneje los bitmaps pequeños eficientemente.
            val oriented = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, matrix, true)
            val finalOriented = if (oriented === raw) {
                raw.copy(Bitmap.Config.ARGB_8888, false)
            } else {
                oriented
            }
            latestFrameBitmap = finalOriented

            val mpImage = BitmapImageBuilder(finalOriented).build()
            val frameTimeMs = SystemClock.uptimeMillis()
            lastFrameSubmitMs = frameTimeMs
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
         * Preview: resolución moderada (4:3, igual que [analysisResolutionSelector]
         * para mantener el mismo encuadre). Antes pedía 4032x3024 — prácticamente
         * resolución de foto fija, no de video — y con 3 surfaces simultáneos
         * (Preview + ImageAnalysis + VideoCapture) eso puede hacer que el HAL de
         * cámara del dispositivo limite el framerate real de captura muy por
         * debajo de 30fps, desincronizando el preview de video contra el modelo
         * 3D (que sí actualiza a vsync completo, ver `LashRenderer.frameCallback`).
         * 1440x1080 sigue siendo nítido en pantalla y es un tamaño que
         * prácticamente cualquier HAL de cámara puede entregar a framerate
         * completo en una sesión multi-surface.
         *
         * REVERTIDO (misma sesión): se probó subir esto en dos pasos (1920x1440,
         * luego HIGHEST_AVAILABLE_STRATEGY) por un reporte de "calidad horrible" —
         * ninguno de los dos cambió el síntoma, y terminó describiéndose como
         * colores raros/apagados/oscuros, no como falta de nitidez o resolución.
         * Eso apunta a que la resolución de preview NUNCA fue la causa real — se
         * revierte al valor original para sacar esta variable de la ecuación y
         * confirmar si el problema de color es anterior a esta sesión (no
         * introducido por estos cambios) antes de seguir investigando otra cosa
         * (candidatos: `PreviewView.ImplementationMode`, procesamiento de color del
         * propio HAL en distintas resoluciones — ninguno de los dos se tocó todavía).
         */
        private val previewResolutionSelector: ResolutionSelector =
            ResolutionSelector.Builder()
                .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
                .setResolutionStrategy(
                    ResolutionStrategy(
                        Size(1440, 1080),
                        ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                    ),
                )
                .build()

        /** Análisis ML acotado a 640x480: libera ancho de banda para que el
         * preview no quede pixelado, y reduce la latencia de inferencia de
         * MediaPipe ~40-60% vs 960x720 (menos píxeles → resultado más rápido
         * → menos delay entre movimiento real y reacción del modelo 3D). */
        private val analysisResolutionSelector: ResolutionSelector =
            ResolutionSelector.Builder()
                .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
                .setResolutionStrategy(
                    ResolutionStrategy(
                        Size(640, 480),
                        ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER,
                    ),
                )
                .build()
    }
}
