package com.example.test_face

import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import android.view.Display
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.roundToInt

/**
 * Instrumentación de DIAGNÓSTICO por etapas del pipeline de tracking: emite
 * una línea `TIEMPOS_ETAPAS` (tag `LashRenderer`) cada [LOG_EVERY_VSYNC]
 * vsync, desde el frame loop de
 * [com.example.test_face.render.LashRenderer].
 *
 * Solo mide, no cambia nada del pipeline. Cada media móvil tiene UN solo
 * hilo que la escribe (análisis, callback de MediaPipe o principal), así que
 * `@Volatile` alcanza; los contadores que se resetean desde el hilo
 * principal son atómicos.
 */
object PerfStats {

    private const val TAG = "LashRenderer"
    private const val LOG_EVERY_VSYNC = 120
    private const val EMA_ALPHA = 0.1f

    // ── Medias móviles (ms) ────────────────────────────────────────────
    @Volatile private var inferenceMs = Float.NaN
    @Volatile private var callbackMs = Float.NaN
    @Volatile private var callbackThread = "?"
    @Volatile private var copyRawMs = Float.NaN
    @Volatile private var canvasRotMs = Float.NaN
    @Volatile private var proxyAgeMs = Float.NaN
    /** Antigüedad del frame (sensor → `detectAsync`): [proxyAgeMs] más
     * copia y Canvas. Es lo que `PRESUPUESTO_LATENCIA` NO ve. */
    @Volatile private var submitAgeMs = Float.NaN

    // Hilo principal: vsync en los que [com.example.test_face.render.PoseInterpolator]
    // pidió más allá de su tope de extrapolación (pose frenada o fija).
    private var extrapolationSamples = 0
    private var extrapolationSaturated = 0

    // Solo con `lock_release=start` (hilo de cómputo, ver
    // [FaceLandmarkerHelper]); `n/d` en el modo de siempre.
    @Volatile private var computeMs = Float.NaN
    @Volatile private var computeQueueMs = Float.NaN
    @Volatile private var computeThread = "-"
    private val computeDropped = AtomicInteger()

    /** Resumen compacto de la configuración EFECTIVA (delegado real,
     * resoluciones resueltas, casos de uso enlazados...), lo arma
     * [CameraXManager] en cada enlace. Va al principio de cada
     * `TIEMPOS_ETAPAS` para que cualquier línea suelta diga con qué se midió. */
    @Volatile var configSummary = "?"

    /** `true` si `SENSOR_INFO_TIMESTAMP_SOURCE` es REALTIME (la única base
     * de tiempo contra la que se puede medir [proxyAgeMs]); `null` mientras
     * no se consultó. Lo escribe [CameraXManager] al enlazar la cámara. */
    @Volatile var sensorTimestampRealtime: Boolean? = null

    // ── Contadores de la ventana ───────────────────────────────────────
    private val cameraFrames = AtomicInteger()
    private val results = AtomicInteger()
    private val resultsNoFace = AtomicInteger()
    private val discarded = AtomicInteger()

    // ── Estado del hilo principal (solo [onVsync]) ──────────────────────
    private var vsyncCount = 0
    private var windowStartNanos = 0L
    private var lastFrameNanos = 0L
    private var longFrames = 0
    private var intervals = 0
    private var maxIntervalNanos = 0L
    private var refreshPeriodNanos = 16_666_667L

    private var appContext: Context? = null

    fun init(context: Context) {
        appContext = context.applicationContext
        refreshPeriodNanos = readRefreshPeriodNanos()
    }

    private fun ema(prev: Float, sample: Float): Float =
        if (prev.isNaN()) sample else prev + (sample - prev) * EMA_ALPHA

    /** Hilo del callback de MediaPipe: `detectAsync` → inicio del callback. */
    fun recordInference(ms: Float) { inferenceMs = ema(inferenceMs, ms) }

    /** Hilo del callback de MediaPipe: duración completa del callback. */
    fun recordCallback(nanos: Long, thread: String) {
        callbackMs = ema(callbackMs, nanos / 1_000_000f)
        callbackThread = thread
    }

    /** Hilo de cómputo (`lock_release=start`): espera en la cola desde que
     * el callback de MediaPipe entregó el resultado, y duración del cómputo. */
    fun recordCompute(queueNanos: Long, computeNanos: Long, thread: String) {
        computeQueueMs = ema(computeQueueMs, queueNanos / 1_000_000f)
        computeMs = ema(computeMs, computeNanos / 1_000_000f)
        computeThread = thread
    }

    /** Resultado reemplazado por uno más nuevo antes de llegar a computarse
     * ("gana el último"), o descartado por timestamp no creciente. */
    fun onComputeDropped() { computeDropped.incrementAndGet() }

    /** Hilo de análisis. */
    fun recordCopyRaw(nanos: Long) { copyRawMs = ema(copyRawMs, nanos / 1_000_000f) }

    /** Hilo de análisis. */
    fun recordCanvasRot(nanos: Long) { canvasRotMs = ema(canvasRotMs, nanos / 1_000_000f) }

    /** Hilo de análisis. [sensorTimestampNanos] = `imageProxy.imageInfo.timestamp`. */
    fun recordProxyAge(sensorTimestampNanos: Long) {
        if (sensorTimestampRealtime != true || sensorTimestampNanos <= 0L) return
        val ageMs = (SystemClock.elapsedRealtimeNanos() - sensorTimestampNanos) / 1_000_000f
        proxyAgeMs = ema(proxyAgeMs, ageMs)
    }

    /** Hilo de análisis, justo antes de `detectAsync`. Misma base de tiempo
     * que [recordProxyAge]: solo con fuente REALTIME. */
    fun recordSubmitAge(sensorTimestampNanos: Long) {
        if (sensorTimestampRealtime != true || sensorTimestampNanos <= 0L) return
        submitAgeMs = ema(submitAgeMs, (SystemClock.elapsedRealtimeNanos() - sensorTimestampNanos) / 1_000_000f)
    }

    /** Hilo principal, una vez por vsync (ojo izquierdo). */
    fun onExtrapolationSample(saturated: Boolean) {
        extrapolationSamples++
        if (saturated) extrapolationSaturated++
    }

    fun onCameraFrame() { cameraFrames.incrementAndGet() }
    fun onDiscarded() { discarded.incrementAndGet() }
    fun onResult(faceDetected: Boolean) {
        results.incrementAndGet()
        if (!faceDetected) resultsNoFace.incrementAndGet()
    }

    /** Hilo principal, en cada `doFrame` del frame loop. */
    fun onVsync(frameTimeNanos: Long) {
        if (lastFrameNanos != 0L) {
            val interval = frameTimeNanos - lastFrameNanos
            intervals++
            if (interval > refreshPeriodNanos * 3 / 2) longFrames++
            if (interval > maxIntervalNanos) maxIntervalNanos = interval
        }
        lastFrameNanos = frameTimeNanos
        if (windowStartNanos == 0L) windowStartNanos = frameTimeNanos
        if (++vsyncCount < LOG_EVERY_VSYNC) return

        val windowSec = (frameTimeNanos - windowStartNanos) / 1_000_000_000f
        val frames = cameraFrames.getAndSet(0)
        val res = results.getAndSet(0)
        val noFace = resultsNoFace.getAndSet(0)
        val drop = discarded.getAndSet(0)
        val computeDrop = computeDropped.getAndSet(0)
        fun rate(n: Int) = if (windowSec > 0f) n / windowSec else Float.NaN

        val proxyAge = when (sensorTimestampRealtime) {
            true -> "${fmt(proxyAgeMs)}ms edad_envio=${fmt(submitAgeMs)}ms"
            false -> "no_medible(SENSOR_INFO_TIMESTAMP_SOURCE!=REALTIME)"
            null -> "no_medible(fuente_desconocida)"
        }
        Log.i(
            TAG,
            "TIEMPOS_ETAPAS cfg=$configSummary inferencia=${fmt(inferenceMs)}ms " +
                "cb_onresult=${fmt(callbackMs)}ms(hilo=$callbackThread) " +
                "computo=${fmt(computeMs)}ms(hilo=$computeThread) espera_cola=${fmt(computeQueueMs)}ms " +
                "descartados_computo=$computeDrop " +
                "copia_raw=${fmt(copyRawMs)}ms canvas_rot=${fmt(canvasRotMs)}ms " +
                "espera_proxy=$proxyAge " +
                "fps_camara=${fmt(rate(frames))} fps_resultados=${fmt(rate(res))} " +
                "descartados=$drop(${fmt(rate(drop))}/s) " +
                "frames_largos=$longFrames/$intervals max_intervalo=${fmt(maxIntervalNanos / 1_000_000f)}ms " +
                "periodo=${fmt(refreshPeriodNanos / 1_000_000f)}ms " +
                "sin_rostro=${if (res > 0) (noFace * 100f / res).roundToInt() else 0}% " +
                "extrap_saturada=$extrapolationSaturated/$extrapolationSamples " +
                "ventana=${fmt(windowSec)}s termico=${thermalStatus()}",
        )

        vsyncCount = 0
        windowStartNanos = frameTimeNanos
        longFrames = 0
        intervals = 0
        maxIntervalNanos = 0L
        extrapolationSamples = 0
        extrapolationSaturated = 0
        // Se relee por ventana: con refresco variable (60/90/120 Hz) el
        // período cambia y un valor fijo contaría mal los frames largos.
        refreshPeriodNanos = readRefreshPeriodNanos()
    }

    /** Una vez al iniciar la cámara (tag `CameraXManager`). */
    fun logDeviceInfo() {
        val soc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MODEL else "n/d(API<31)"
        Log.i(
            "CameraXManager",
            "DISPOSITIVO fabricante=${Build.MANUFACTURER} modelo=${Build.MODEL} android=${Build.VERSION.RELEASE} " +
                "sdk=${Build.VERSION.SDK_INT} soc=$soc refresco=${fmt(1_000_000_000f / readRefreshPeriodNanos())}Hz",
        )
    }

    private fun readRefreshPeriodNanos(): Long {
        val dm = appContext?.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
        val hz = dm?.getDisplay(Display.DEFAULT_DISPLAY)?.refreshRate ?: 60f
        return if (hz > 1f) (1_000_000_000f / hz).toLong() else 16_666_667L
    }

    private fun thermalStatus(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "n/d(API<29)"
        val pm = appContext?.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return "?"
        return when (val s = pm.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> "NONE"
            PowerManager.THERMAL_STATUS_LIGHT -> "LIGHT"
            PowerManager.THERMAL_STATUS_MODERATE -> "MODERATE"
            PowerManager.THERMAL_STATUS_SEVERE -> "SEVERE"
            PowerManager.THERMAL_STATUS_CRITICAL -> "CRITICAL"
            PowerManager.THERMAL_STATUS_EMERGENCY -> "EMERGENCY"
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "SHUTDOWN"
            else -> s.toString()
        }
    }

    private fun fmt(v: Float): String = if (v.isNaN()) "n/d" else String.format(Locale.US, "%.1f", v)
}
