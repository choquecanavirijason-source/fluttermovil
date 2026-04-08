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
        onResult = onTrackingResult,
        onError = onError,
    )

    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor by lazy { ContextCompat.getMainExecutor(activity) }

    @Volatile
    private var cameraProvider: ProcessCameraProvider? = null

    private var lensFacing = CameraSelector.LENS_FACING_FRONT
    private var previewView: PreviewView? = null

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
