package com.example.test_face

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.RectF
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
import kotlin.math.roundToInt

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
            // El timestamp lo devuelve el PROPIO resultado, no una variable
            // compartida: `lastFrameSubmitMs` guardaba el último frame
            // ENVIADO, que con cola no era el mismo cuyo resultado estaba
            // llegando — o sea que la latencia medida salía más CHICA que la
            // real justo cuando había retraso acumulado, y por eso este log
            // nunca delató el problema. `timestampMs()` es el valor exacto
            // que se pasó a detectAsync para ESTE frame.
            val submitMs = rawResult.timestampMs()
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

            // `data` ya trae "leftLashLine"/"rightLashLine" calculadas por
            // EyeTrackingResultMapper.map() con LashEdgeDetector Y suavizadas
            // con EMA entre frames.
            //
            // ELIMINADO: acá había un segundo pase de
            // `LashEdgeDetector.detectRealLashLine` sobre los MISMOS puntos
            // que sobreescribía esas dos claves con el resultado CRUDO. Tenía
            // dos efectos, los dos malos:
            //
            //   1. Pagaba la deteccion dos veces por frame (2 ojos x 2 pases),
            //      y `detectOne` recorre píxeles del bitmap por cada uno de
            //      los 8 landmarks de cada párpado.
            //   2. Descartaba por completo el suavizado EMA del mapper (ver
            //      su KDoc, que documenta en detalle por qué hace falta): los
            //      puntos llegaban a Flutter con todo el jitter de MediaPipe,
            //      que es justo lo que ese EMA existe para absorber.
            //
            // El mapper es el único dueño de esas claves ahora.
            val augmentedData: Map<String, Any?> = data
            dumpAnnotatedAnalysisFrame(resultBitmap, data)
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

    /** Ancho de buffer (con padding de fila) ya reportado en logcat, para
     * loguear el rowStride una sola vez por configuración en vez de en cada
     * frame. Ver el bloque de padding en [processFrame]. */
    /** Ver el bloque del POOL en [processFrame]. Round-robin de bitmaps de
     * salida, para no alojar ~1,2 MB por frame. */
    private val orientedPool = arrayOfNulls<Bitmap>(ORIENTED_POOL_SIZE)
    private var orientedPoolIndex = 0
    /**
     * SIN `FILTER_BITMAP_FLAG` (2026-09-04). La matriz que se le aplica a
     * este `drawBitmap` es siempre una rotación de 0/90/180/270 grados
     * (`imageProxy.imageInfo.rotationDegrees` no puede ser otra cosa) más, en
     * cámara frontal, un espejado — o sea siempre alineada a los ejes y a
     * escala 1:1. Con ese tipo de transformación cada píxel de destino cae
     * exactamente sobre uno de origen, así que el filtrado bilineal da EL
     * MISMO resultado que el vecino más cercano, pero interpolando cuatro
     * texels por píxel: costo puro por frame, sin ninguna ganancia de
     * calidad. Sale del camino crítico que decide cada cuánto puede correr
     * MediaPipe.
     */
    private val orientedPaint = Paint()

    private var loggedBufferWidth = -1

    /** DIAGNÓSTICO temporal (ronda de alineación del overlay): loguear una
     * sola vez la rotación aplicada y las dimensiones del bitmap orientado
     * que MediaPipe analiza — son las que Flutter recibe como
     * `imageWidth`/`imageHeight` y usa para el mapeo imagen→pantalla. */
    private var loggedOrientedDims = false

    /** Ver [dumpAnnotatedAnalysisFrame] — diagnóstico temporal. */
    private var analysisDumpsWritten = 0
    private var analysisDumpFrameCounter = 0


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
                // DIAGNÓSTICO alineación overlay: el overlay de Flutter asume
                // que preview y análisis comparten encuadre (mismo aspect +
                // mismo cropRect). Si CameraX resolvió resoluciones de aspect
                // distinto, o recorta distinto cada surface, el FOV difiere y
                // los landmarks caen desplazados por más que el mapeo de
                // Flutter esté bien.
                Log.i(
                    TAG,
                    "RESINFO preview=${preview.resolutionInfo} analysis=${imageAnalysis.resolutionInfo} " +
                        "targetRotation=$rotation previewViewSize=${pv.width}x${pv.height}",
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
        // Ya hay un frame en vuelo en MediaPipe: se descarta este ENTERO, sin
        // pagar la conversión del bitmap (dos pasadas de ~1,2 MB: el
        // copyPixelsFromBuffer de más abajo y el Canvas rotado/espejado). Sin
        // esto, la cola interna de MediaPipe crecía sin límite y el retraso
        // llegaba a varios segundos — ver el KDoc de
        // [FaceLandmarkerHelper.detectAsync], que es donde vive el cerrojo
        // real. Este chequeo es sólo la optimización de saltear el trabajo.
        if (helper.isInferenceInFlight()) {
            imageProxy.close()
            return
        }

        try {
            val width = imageProxy.width
            val height = imageProxy.height

            // ── Padding de fila (rowStride) ───────────────────────────────
            // `copyPixelsFromBuffer` copia el buffer LINEALMENTE, asumiendo
            // que cada fila ocupa exactamente `bitmap.width * 4` bytes. Pero
            // CameraX entrega el plano RGBA_8888 con `rowStride` alineado por
            // el HAL, que en muchos dispositivos es MAYOR que `width * 4`.
            // Con un bitmap de ancho `width`, esos bytes de relleno se leen
            // como píxeles reales y cada fila queda corrida unos píxeles
            // respecto a la anterior: la imagen que analiza MediaPipe sale
            // CIZALLADA en diagonal frente a lo que muestra el PreviewView, y
            // por eso los landmarks (y el overlay de debug que los dibuja)
            // caen desplazados sobre la frente en vez de sobre el párpado.
            //
            // Se copia con el ancho REAL del buffer (`rowStride/pixelStride`)
            // y se recorta a `width` al construir el bitmap orientado — el
            // `Bitmap.createBitmap(src, 0, 0, width, height, matrix, ...)` de
            // más abajo ya toma solo esa subregión, así que el recorte del
            // relleno y la rotación/espejo ocurren en un único paso.
            val plane = imageProxy.planes[0]
            val pixelStride = if (plane.pixelStride > 0) plane.pixelStride else 4
            val bufferWidth = plane.rowStride / pixelStride
            // `coerceAtLeast(width)`: si el HAL reportara un rowStride menor
            // que width*pixelStride (no debería), copiar con un ancho menor
            // desbordaría el recorte de abajo — mejor caer al comportamiento
            // sin padding que producir un bitmap inválido.
            val rawWidth = bufferWidth.coerceAtLeast(width)
            if (rawWidth != loggedBufferWidth) {
                loggedBufferWidth = rawWidth
                Log.i(
                    TAG,
                    "análisis ${width}x$height rowStride=${plane.rowStride} " +
                        "pixelStride=$pixelStride → anchoBuffer=$rawWidth " +
                        "(padding=${rawWidth - width}px)",
                )
            }

            var raw = rawFrameBitmap
            if (raw == null || raw.isRecycled || raw.width != rawWidth || raw.height != height) {
                raw?.recycle()
                raw = Bitmap.createBitmap(rawWidth, height, Bitmap.Config.ARGB_8888)
                rawFrameBitmap = raw
            }
            plane.buffer.rewind()
            raw.copyPixelsFromBuffer(plane.buffer)

            val matrix =
                Matrix().apply {
                    postRotate(imageProxy.imageInfo.rotationDegrees.toFloat())
                    if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
                        // Reflexión en x tras la rotación. El pivote es
                        // irrelevante: `Bitmap.createBitmap` mapea el rect de
                        // origen y luego traslada por -left/-top, así que
                        // cualquier eje vertical produce el mismo bitmap. Se
                        // usa 0 para no sugerir un pivote "correcto" que en
                        // realidad no se respeta (antes usaba width/height,
                        // que además eran las dimensiones PRE-rotación).
                        postScale(-1f, 1f, 0f, 0f)
                    }
                }

            // POOL de bitmaps de salida, en vez de `Bitmap.createBitmap(...)`
            // por frame.
            //
            // `Bitmap.createBitmap` SIEMPRE aloja: eran ~1,2 MB (480x640
            // ARGB_8888) por frame de análisis a ~30 fps ≈ 37 MB/s de basura.
            // El código anterior lo asumía ("se confia en que el GC maneje
            // estos bitmaps pequeños"), pero a ese ritmo el GC se vuelve
            // constante y, si llega a fallar la reserva, el
            // `OutOfMemoryError` resultante NO es una `Exception`: se escapaba
            // del catch de abajo y mataba el hilo de `analysisExecutor` (que
            // es uno solo), con lo que el análisis se detenía en silencio
            // para siempre — el preview seguía, pero el modelo quedaba
            // congelado en su última pose.
            //
            // No se puede reusar UN solo bitmap: `detectAsync` es asíncrono y
            // MediaPipe puede seguir leyendo el bitmap después de que esta
            // función retorne, así que sobrescribirlo en el frame siguiente
            // produciría desgarro. Con [ORIENTED_POOL_SIZE] buffers en
            // round-robin, cada uno se reutiliza recién varios frames
            // después — muy por encima de la latencia real de MediaPipe
            // (~20-30 ms medidos), y el uso de memoria queda ACOTADO.
            val srcRect = RectF(0f, 0f, width.toFloat(), height.toFloat())
            val dstRect = RectF()
            matrix.mapRect(dstRect, srcRect)
            val outWidth = dstRect.width().roundToInt().coerceAtLeast(1)
            val outHeight = dstRect.height().roundToInt().coerceAtLeast(1)

            val slot = orientedPoolIndex
            orientedPoolIndex = (orientedPoolIndex + 1) % ORIENTED_POOL_SIZE
            var out = orientedPool[slot]
            if (out == null || out.isRecycled || out.width != outWidth || out.height != outHeight) {
                out?.recycle()
                out = Bitmap.createBitmap(outWidth, outHeight, Bitmap.Config.ARGB_8888)
                orientedPool[slot] = out
            }

            // `Bitmap.createBitmap(src, ..., matrix, ...)` normalizaba la
            // traslación internamente (mapea el rect y desplaza por
            // -left/-top); acá hay que hacerlo a mano para dibujar dentro del
            // buffer reusado.
            val drawMatrix = Matrix(matrix)
            drawMatrix.postTranslate(-dstRect.left, -dstRect.top)

            val canvas = Canvas(out)
            canvas.drawColor(Color.BLACK, PorterDuff.Mode.SRC)
            canvas.save()
            canvas.concat(drawMatrix)
            // Recorta el padding de fila: `raw` puede ser más ancho que
            // `width` (ver el bloque de rowStride arriba) y `drawBitmap`
            // dibujaría también esas columnas de relleno. El clip se aplica
            // en el espacio de coordenadas de `raw`, ya con la matriz puesta.
            canvas.clipRect(srcRect)
            canvas.drawBitmap(raw, 0f, 0f, orientedPaint)
            canvas.restore()

            val finalOriented = out
            latestFrameBitmap = finalOriented
            if (!loggedOrientedDims) {
                loggedOrientedDims = true
                Log.i(
                    TAG,
                    "ORIENTED rotationDegrees=${imageProxy.imageInfo.rotationDegrees} " +
                        "raw=${width}x$height → oriented=${finalOriented.width}x${finalOriented.height} " +
                        "cropRect=${imageProxy.cropRect} lensFacing=$lensFacing",
                )
            }

            val mpImage = BitmapImageBuilder(finalOriented).build()
            helper.detectAsync(mpImage, SystemClock.uptimeMillis())
        } catch (e: Throwable) {
            // Throwable, NO Exception: un OutOfMemoryError es un Error, se
            // escapaba de acá y mataba el hilo de `analysisExecutor` — y como
            // ese executor es de UN solo hilo, el análisis se detenía para
            // siempre sin ningún mensaje. Se loguea explícitamente para que,
            // si vuelve a pasar, quede la causa en logcat en vez de un
            // congelamiento mudo.
            Log.e(TAG, "processFrame: fallo procesando el frame de análisis", e)
            onError(e.message ?: "Error procesando frame")
        } finally {
            imageProxy.close()
        }
    }

    /**
     * DIAGNÓSTICO TEMPORAL (ronda de alineación del overlay). Guarda el
     * bitmap EXACTO que analizó MediaPipe con los landmarks del párpado
     * superior dibujados encima, en las coordenadas de píxel que el mapper
     * envió a Flutter.
     *
     * Sirve para separar dos causas que desde un screenshot de la pantalla se
     * confunden:
     *   - Si los puntos caen SOBRE el párpado en esta imagen, los landmarks
     *     y la conversión a píxeles son correctos, y el desplazamiento que se
     *     ve en pantalla viene del mapeo imagen->pantalla (encuadre o lag).
     *   - Si NO caen sobre el párpado acá, el problema es anterior
     *     (rotación/espejo del bitmap, o la conversión normalizado->píxel).
     *
     * Solo escribe [ANALYSIS_DUMP_COUNT] archivos, espaciados
     * [ANALYSIS_DUMP_EVERY] frames, y después no hace nada más — así no
     * agrega costo sostenido al pipeline mientras se mide.
     *
     * Se recuperan con:
     *   adb pull /sdcard/Android/data/com.example.test_face/files/analysis_NN.png
     */
    private fun dumpAnnotatedAnalysisFrame(bitmap: Bitmap?, data: Map<String, Any?>) {
        if (analysisDumpsWritten >= ANALYSIS_DUMP_COUNT) return
        if (bitmap == null || data["faceDetected"] != true) return
        analysisDumpFrameCounter++
        if (analysisDumpFrameCounter % ANALYSIS_DUMP_EVERY != 0) return

        try {
            @Suppress("UNCHECKED_CAST")
            fun points(key: String): List<Pair<Float, Float>> =
                (data[key] as? List<*>)?.mapNotNull { pt ->
                    val m = pt as? Map<*, *> ?: return@mapNotNull null
                    val x = (m["x"] as? Double)?.toFloat() ?: return@mapNotNull null
                    val y = (m["y"] as? Double)?.toFloat() ?: return@mapNotNull null
                    x to y
                } ?: emptyList()

            val annotated = bitmap.copy(Bitmap.Config.ARGB_8888, true) ?: return
            val canvas = android.graphics.Canvas(annotated)
            val fill = android.graphics.Paint().apply { isAntiAlias = true }
            val stroke = android.graphics.Paint().apply {
                isAntiAlias = true
                style = android.graphics.Paint.Style.STROKE
                strokeWidth = 1f
                color = android.graphics.Color.BLACK
            }

            // Verde = párpado superior (lo que el motor usa como línea de
            // pestañas); naranja = pestaña real detectada por LashEdgeDetector.
            for ((key, color) in listOf(
                "leftUpperLid" to android.graphics.Color.GREEN,
                "rightUpperLid" to android.graphics.Color.GREEN,
                "leftLashLine" to android.graphics.Color.rgb(255, 153, 0),
                "rightLashLine" to android.graphics.Color.rgb(255, 153, 0),
            )) {
                fill.color = color
                for ((x, y) in points(key)) {
                    canvas.drawCircle(x, y, 3f, fill)
                    canvas.drawCircle(x, y, 3f, stroke)
                }
            }

            val dir = activity.getExternalFilesDir(null) ?: return
            val file = File(dir, "analysis_%02d.png".format(analysisDumpsWritten))
            file.outputStream().use { out ->
                annotated.compress(Bitmap.CompressFormat.PNG, 100, out)
            }
            annotated.recycle()
            analysisDumpsWritten++
            Log.i(
                TAG,
                "DUMP escrito ${file.absolutePath} (${bitmap.width}x${bitmap.height}) " +
                    "— quedan ${ANALYSIS_DUMP_COUNT - analysisDumpsWritten}",
            )
        } catch (e: Exception) {
            Log.w(TAG, "DUMP fallo al guardar el frame de análisis anotado", e)
            analysisDumpsWritten = ANALYSIS_DUMP_COUNT // no reintentar en loop
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

        /** Buffers de salida en round-robin (ver [processFrame]). 3 alcanza
         * de sobra: MediaPipe devuelve el resultado en ~20-30 ms medidos, o
         * sea menos de un frame, y acá un buffer se reutiliza recién 3
         * frames (~100 ms) después. */
        private const val ORIENTED_POOL_SIZE = 3

        /** Ver [dumpAnnotatedAnalysisFrame] — cuántos frames anotados
         * guardar y cada cuántos frames con rostro. Diagnóstico temporal:
         * poner ANALYSIS_DUMP_COUNT en 0 lo desactiva por completo. */
        private const val ANALYSIS_DUMP_COUNT = 0
        private const val ANALYSIS_DUMP_EVERY = 30
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
