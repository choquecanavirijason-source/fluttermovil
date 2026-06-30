package com.example.test_face

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.os.SystemClock
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
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import io.github.sceneview.SceneView
import io.github.sceneview.math.Position
import io.github.sceneview.node.ModelNode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.google.mediapipe.framework.image.BitmapImageBuilder
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class CameraXManager(
    private val activity: Activity,
    private val onTrackingResult: (Map<String, Any?>) -> Unit,
    private val onError: (String) -> Unit,
) {
    private val helper = FaceLandmarkerHelper(
        context = activity,
        onResult = { data ->
            onTrackingResult(data)      // sigue enviando datos a Flutter
            updateModelPosition(data)   // también mueve el nodo 3D
        },
        onError = onError,
    )

    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor by lazy { ContextCompat.getMainExecutor(activity) }

    @Volatile
    private var cameraProvider: ProcessCameraProvider? = null

    private var lensFacing = CameraSelector.LENS_FACING_FRONT
    private var previewView: PreviewView? = null
    private var sceneView: SceneView? = null
    @Volatile private var current3DModel: ModelNode? = null

    // Posición suavizada — se acumula en el hilo de MediaPipe y se aplica en UI thread
    private var smoothX = 0f
    private var smoothY = 0f

    private var imageAnalysisUseCase: ImageAnalysis? = null

    private val stopped = AtomicBoolean(true)
    private val bindGeneration = AtomicLong(0L)
    private var pendingBindRunnable: Runnable? = null

    fun attachPreview(view: PreviewView) {
        previewView = view
        mainHandler.post {
            if (!stopped.get()) {
                scheduleRebind()
            }
        }
    }

    fun detachPreview() {
        previewView = null
        mainHandler.post {
            if (!stopped.get()) {
                scheduleRebind()
            }
        }
    }

    fun attachSceneView(view: SceneView) {
        sceneView = view
    }

    fun detachSceneView() {
        current3DModel?.let { old ->
            sceneView?.removeChildNode(old)
            old.destroy()
            current3DModel = null
        }
        sceneView = null
    }

    /**
     * Carga un archivo .glb en el [SceneView] superpuesto a la cámara.
     *
     * Llamado desde el hilo principal (MethodChannel corre en UI thread).
     * La lectura del archivo ocurre en [Dispatchers.IO]; la construcción
     * del nodo y la inserción en la escena vuelven al hilo principal.
     */
    fun load3DModel(path: String) {
        val sv = sceneView ?: run {
            android.util.Log.w("CameraXManager", "load3DModel: SceneView todavía no disponible")
            return
        }
        val scope = (activity as? LifecycleOwner)?.lifecycleScope ?: run {
            android.util.Log.w("CameraXManager", "load3DModel: Activity no es LifecycleOwner")
            return
        }

        // Retirar y destruir el modelo previo antes de cargar el nuevo
        current3DModel?.let { old ->
            sv.removeChildNode(old)
            old.destroy()
            current3DModel = null
        }

        scope.launch {
            try {
                val fileUri = "file://$path"
                android.util.Log.d("CameraXManager", "Cargando modelo 3D: $fileUri")

                // La lectura del archivo .glb es I/O bloqueante → hilo IO
                val modelInstance = withContext(Dispatchers.IO) {
                    sv.modelLoader.createModelInstance(fileUri)
                }

                if (modelInstance == null) {
                    android.util.Log.e("CameraXManager", "createModelInstance devolvió null — $fileUri")
                    return@launch
                }

                // Construcción del nodo e inserción en escena → hilo principal (Filament/GL)
                val node = ModelNode(
                    modelInstance = modelInstance,
                    scaleToUnits = 0.1f,   // ~10 cm; ajustar con landmarks de MediaPipe
                    autoAnimate = true
                )
                sv.addChildNode(node)
                current3DModel = node

                android.util.Log.d("CameraXManager", "✅ Modelo 3D añadido a SceneView: $path")
            } catch (e: Exception) {
                android.util.Log.e("CameraXManager", "Error cargando modelo 3D: ${e.message}", e)
            }
        }
    }

    /**
     * Mueve [current3DModel] para que siga el punto medio entre ambos iris.
     *
     * Llamado desde el hilo interno de MediaPipe en cada frame donde hay cara.
     * El lerp se acumula aquí para no bloquear el UI thread con operaciones
     * matemáticas; solo la escritura de [position] se despacha al UI thread.
     *
     * Sistema de coordenadas Filament: Y hacia arriba, Z negativo hacia el fondo.
     * Los landmarks vienen ya volteados en X (bitmap espejado en [processFrame])
     * así que no se necesita inversión adicional de eje X.
     */
    private fun updateModelPosition(data: Map<String, Any?>) {
        if (data["faceDetected"] != true) return
        if (current3DModel == null) return

        val imageWidth  = (data["imageWidth"]  as? Int)?.toFloat() ?: return
        val imageHeight = (data["imageHeight"] as? Int)?.toFloat() ?: return

        val leftIris  = data["leftIris"]  as? Map<*, *> ?: return
        val rightIris = data["rightIris"] as? Map<*, *> ?: return

        val lx = (leftIris["x"]  as? Double)?.toFloat() ?: return
        val ly = (leftIris["y"]  as? Double)?.toFloat() ?: return
        val rx = (rightIris["x"] as? Double)?.toFloat() ?: return
        val ry = (rightIris["y"] as? Double)?.toFloat() ?: return

        // Punto medio entre ambos iris, normalizado a [0, 1]
        val nx = ((lx + rx) * 0.5f) / imageWidth
        val ny = ((ly + ry) * 0.5f) / imageHeight

        // Espacio de Filament: X→derecha, Y→arriba → invertir Y de pantalla
        val targetX = (nx - 0.5f) * WORLD_SCALE_X
        val targetY = (0.5f - ny) * WORLD_SCALE_Y

        // Lerp acumulado en hilo de MediaPipe (evita temblores)
        smoothX += (targetX - smoothX) * LERP_ALPHA
        smoothY += (targetY - smoothY) * LERP_ALPHA

        val sx = smoothX
        val sy = smoothY

        mainHandler.post {
            current3DModel?.position = Position(sx, sy, FIXED_DEPTH)
        }
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
                )
            } else {
                provider.bindToLifecycle(
                    lifecycleOwner,
                    selector,
                    imageAnalysis,
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
        private const val REBIND_DELAY_MS       = 280L
        private const val STOP_UNBIND_DELAY_MS  = 220L

        // ── Tracking 3D ──────────────────────────────────────────────────────
        /** Factor de suavizado lerp: 0 = congelado, 1 = sin suavizado. */
        private const val LERP_ALPHA    = 0.15f
        /** Ancho del espacio de mundo que cubre toda la pantalla (unidades Filament). */
        private const val WORLD_SCALE_X = 0.6f
        /** Alto del espacio de mundo que cubre toda la pantalla (unidades Filament). */
        private const val WORLD_SCALE_Y = 0.8f
        /** Profundidad fija del modelo 3D delante de la cámara (metros negativos). */
        private const val FIXED_DEPTH   = -1.0f

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
