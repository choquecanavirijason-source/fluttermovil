package com.example.test_face

import android.content.Context
import android.util.Log
import android.util.Size
import com.example.test_face.render.PoseInterpolator
import com.example.test_face.render.RendererConfiguration
import java.io.File
import java.util.Locale
import java.util.Properties

/**
 * Interruptores de DIAGNÓSTICO de rendimiento, leídos de
 * `perf_flags.properties` en `getExternalFilesDir(null)` al iniciar la
 * cámara ([CameraXManager.start]) y de nuevo en caliente cada vez que el
 * archivo cambia mientras la cámara corre — para aislar qué etapa hace lenta
 * la inferencia sin recompilar. Se manda con `adb push` (no requiere
 * permisos).
 *
 * Sin archivo, o con una clave ausente o inválida, cada valor queda en su
 * default, que es EXACTAMENTE el comportamiento de siempre. Ninguno de estos
 * modos es para producción: `blendshapes=false` y `overlay=off` degradan el
 * efecto a propósito para medir.
 *
 * Los valores viven en UNA instantánea inmutable ([config]) que se reemplaza
 * entera: quien lee desde otro hilo nunca ve una mezcla de la lectura vieja y
 * la nueva.
 */
object PerfFlags {

    enum class FlutterEvents { ON, OFF, THROTTLED }

    const val FILE_NAME = "perf_flags.properties"

    /** Resoluciones de análisis aceptadas por `analysis_size`. */
    private val ANALYSIS_SIZES = mapOf(
        "640x480" to Size(640, 480),
        "480x360" to Size(480, 360),
        "320x240" to Size(320, 240),
    )
    val DEFAULT_ANALYSIS_SIZE = Size(640, 480)

    /** Resoluciones de preview aceptadas por `preview_size` (además de
     * `default`, que deja el selector de siempre). */
    private val PREVIEW_SIZES = mapOf("960x720" to Size(960, 720))

    /** FPS aceptados por `fps_range` (además de `default`). */
    private val FPS_VALUES = setOf(30, 60)

    /** Umbrales de MediaPipe de siempre (ver [FaceLandmarkerHelper]). */
    const val DEFAULT_CONFIDENCE = 0.5f

    data class Config(
        /** `delegate=cpu`: [FaceLandmarkerHelper] construye directo con CPU. */
        val forceCpu: Boolean = false,
        /** `blendshapes=false`: sin blendshapes en MediaPipe y apertura fija
         * en 1.0 (ver [com.example.test_face.render.FaceRenderPipeline]). */
        val blendshapes: Boolean = true,
        val analysisSize: Size = DEFAULT_ANALYSIS_SIZE,
        /** `overlay=off`: SceneView oculto, sin escribir pose ni
         * calcular/subir malla — solo cámara + detección. */
        val overlay: Boolean = true,
        val flutterEvents: FlutterEvents = FlutterEvents.ON,
        /** `use_cases=minimal`: solo Preview + ImageAnalysis, sin
         * VideoCapture ni ImageCapture (ver [CameraXManager.applyBinding]). */
        val useCasesMinimal: Boolean = false,
        /** `preview_size`: `null` = selector de siempre (~1440x1080). */
        val previewSize: Size? = null,
        /** `fps_range`: `null` = CameraX elige; si no, se pide `[n, n]`. */
        val fpsRange: Int? = null,
        /** `lock_release=start`: ver [FaceLandmarkerHelper] (cómputo en un
         * hilo dedicado con "gana el último"). */
        val lockReleaseAtStart: Boolean = false,
        val detectConf: Float = DEFAULT_CONFIDENCE,
        val presenceConf: Float = DEFAULT_CONFIDENCE,
        val trackConf: Float = DEFAULT_CONFIDENCE,
        /** `flutter_overlays=off`: Flutter no pinta sus painters sobre la
         * cámara. Lo consulta Dart por el MethodChannel (`getPerfFlags`). */
        val flutterOverlays: Boolean = true,
        /** `analysis_rotation=camerax` (default): CameraX entrega el frame de
         * análisis ya rotado (libyuv, nativo) y el Canvas solo espeja.
         * `canvas`: la rotación por Canvas de software de antes. */
        val analysisRotationCameraX: Boolean = true,
        /** `extrapolation=soft` (default): pasado el tope de extrapolación la
         * pose sigue avanzando con velocidad que decae, en vez de quedar
         * fija hasta el próximo resultado. `hard`: el tope duro de antes.
         * Ver [com.example.test_face.render.PoseInterpolator]. */
        val softExtrapolation: Boolean = true,
        /** `sample_blend=on` (default): al llegar una muestra nueva, la
         * corrección respecto de la pose extrapolada se reparte en el tiempo
         * en vez de aplicarse de golpe. `off`: el escalón de antes. Ver
         * [com.example.test_face.render.PoseInterpolator]. */
        val sampleBlend: Boolean = true,
        /** `forward_age=on` (default): el horizonte de predicción suma la
         * antigüedad del frame previa a `detectAsync` y resta la del preview.
         * `off`: el horizonte de antes. Ver
         * [com.example.test_face.render.LashRenderer]. */
        val forwardAge: Boolean = true,
        // ── Calibración en caliente (se leen en cada frame/vsync) ──────────
        /** `euro_pos_ref`: anchos de ojo/s a los que el corte del One Euro de
         * posición llega a 20 Hz (más bajo = más reactivo y más ruido en
         * movimiento). Default = el valor de RendererConfiguration. */
        val euroPosRef: Float = RendererConfiguration.FAST_MOTION_POSITION_SPANS_PER_SEC,
        /** `euro_rot_ref`: lo mismo para rotación (componentes de cuaternión/s). */
        val euroRotRef: Float = RendererConfiguration.FAST_MOTION_ROTATION_VELOCITY,
        /** `interval_margin` (ms): el margen del tope dinámico `H + margen`. */
        val intervalMarginMs: Float = PoseInterpolator.INTERVAL_MARGIN_NANOS / 1_000_000f,
        /** `abs_max_extrap` (ms): techo absoluto del tope dinámico. */
        val absMaxExtrapMs: Float = PoseInterpolator.ABSOLUTE_MAX_EXTRAPOLATION_NANOS / 1_000_000f,
        /** `preview_latency` (ms): latencia del preview que se resta del
         * horizonte con `forward_age=on`. */
        val previewLatencyMs: Float = RendererConfiguration.PREVIEW_PATH_LATENCY_NANOS / 1_000_000f,
        /** `closed_shift=follower` (default): la bajada de la pestaña con el
         * ojo cerrado se aplica en cada vsync sobre la pose resuelta, con el
         * cierre suavizado y sin extrapolar. `anchor`: dentro del ancla, como
         * antes (pasa por One Euro y extrapolación). Ver
         * [com.example.test_face.render.LashRenderer]. */
        val closedShiftInFollower: Boolean = true,
    )

    /** Resultado de una lectura del archivo, para [CameraXManager]'s
     * `PERF_CONFIG`. */
    data class FileInfo(val path: String, val exists: Boolean, val entries: String)

    @Volatile var config = Config()
        private set

    @Volatile var fileInfo = FileInfo("?", false, "")
        private set

    val forceCpu get() = config.forceCpu
    val blendshapes get() = config.blendshapes
    val analysisSize get() = config.analysisSize
    val overlay get() = config.overlay
    val flutterEvents get() = config.flutterEvents

    /** Lee el archivo, lo publica en [config] y loguea (tag `CameraXManager`)
     * ruta y valores. */
    fun load(context: Context) {
        val (cfg, info) = read(context, log = true)
        config = cfg
        fileInfo = info
        Log.i(TAG, "PERF_FLAGS archivo=${info.path} ${if (info.exists) "leído" else "no existe -> valores por defecto"}")
        Log.i(TAG, "PERF_FLAGS ${describe(cfg)}")
        if (!cfg.blendshapes) {
            Log.w(
                TAG,
                "PERF_FLAGS blendshapes=false: SOLO EXPERIMENTO — la apertura del ojo queda fija en 1.0 " +
                    "(la pestaña no reacciona al parpadeo)",
            )
        }
    }

    /** Parsea el archivo SIN publicarlo: lo usa también Dart (vía
     * `getPerfFlags`), que puede preguntar antes de que [load] haya corrido. */
    fun read(context: Context, log: Boolean = false): Pair<Config, FileInfo> {
        val file = context.getExternalFilesDir(null)?.let { File(it, FILE_NAME) }
        val path = file?.absolutePath ?: "(sin almacenamiento externo)"
        if (file == null || !file.isFile) return Config() to FileInfo(path, false, "")

        val props = Properties()
        try {
            file.inputStream().use { props.load(it) }
        } catch (e: Exception) {
            if (log) Log.w(TAG, "PERF_FLAGS archivo=$path no se pudo leer -> valores por defecto", e)
            return Config() to FileInfo(path, true, "(ilegible)")
        }

        fun value(key: String): String? = props.getProperty(key)?.trim()?.lowercase(Locale.US)
        fun invalid(key: String, v: String) {
            if (log) Log.w(TAG, "PERF_FLAGS valor inválido $key=$v -> se usa el default")
        }
        fun onOff(key: String, default: Boolean, on: String = "on", off: String = "off"): Boolean {
            val v = value(key) ?: return default
            return when (v) {
                on -> true
                off -> false
                else -> default.also { invalid(key, v) }
            }
        }
        fun number(key: String, default: Float, range: ClosedFloatingPointRange<Float>): Float {
            val v = value(key) ?: return default
            val f = v.toFloatOrNull()
            return if (f != null && f in range) f else default.also { invalid(key, v) }
        }
        fun confidence(key: String): Float {
            val v = value(key) ?: return DEFAULT_CONFIDENCE
            val f = v.toFloatOrNull()
            return if (f != null && f in 0f..1f) f else DEFAULT_CONFIDENCE.also { invalid(key, v) }
        }

        val cfg = Config(
            forceCpu = !onOff("delegate", default = true, on = "gpu", off = "cpu"),
            blendshapes = onOff("blendshapes", default = true, on = "true", off = "false"),
            analysisSize = value("analysis_size")?.let { v ->
                ANALYSIS_SIZES[v] ?: DEFAULT_ANALYSIS_SIZE.also { invalid("analysis_size", v) }
            } ?: DEFAULT_ANALYSIS_SIZE,
            overlay = onOff("overlay", default = true),
            flutterEvents = value("flutter_events")?.let { v ->
                when (v) {
                    "on" -> FlutterEvents.ON
                    "off" -> FlutterEvents.OFF
                    "throttled" -> FlutterEvents.THROTTLED
                    else -> FlutterEvents.ON.also { invalid("flutter_events", v) }
                }
            } ?: FlutterEvents.ON,
            useCasesMinimal = !onOff("use_cases", default = true, on = "all", off = "minimal"),
            previewSize = value("preview_size")?.let { v ->
                if (v == "default") null else PREVIEW_SIZES[v].also { if (it == null) invalid("preview_size", v) }
            },
            fpsRange = value("fps_range")?.let { v ->
                if (v == "default") null else v.toIntOrNull()?.takeIf { it in FPS_VALUES }
                    .also { if (it == null) invalid("fps_range", v) }
            },
            lockReleaseAtStart = !onOff("lock_release", default = true, on = "end", off = "start"),
            detectConf = confidence("detect_conf"),
            presenceConf = confidence("presence_conf"),
            trackConf = confidence("track_conf"),
            flutterOverlays = onOff("flutter_overlays", default = true),
            analysisRotationCameraX = onOff("analysis_rotation", default = true, on = "camerax", off = "canvas"),
            softExtrapolation = onOff("extrapolation", default = true, on = "soft", off = "hard"),
            sampleBlend = onOff("sample_blend", default = true),
            forwardAge = onOff("forward_age", default = true),
            euroPosRef = number("euro_pos_ref", Config().euroPosRef, 0.05f..20f),
            euroRotRef = number("euro_rot_ref", Config().euroRotRef, 0.05f..20f),
            intervalMarginMs = number("interval_margin", Config().intervalMarginMs, 0f..500f),
            absMaxExtrapMs = number("abs_max_extrap", Config().absMaxExtrapMs, 50f..1000f),
            previewLatencyMs = number("preview_latency", Config().previewLatencyMs, 0f..300f),
            closedShiftInFollower = onOff("closed_shift", default = true, on = "follower", off = "anchor"),
        )
        val entries = props.stringPropertyNames().sorted()
            .joinToString(",") { "$it=${props.getProperty(it).trim()}" }
        return cfg to FileInfo(path, true, entries)
    }

    /** Texto crudo del archivo, o `null` si no existe — para detectar
     * cambios en caliente ([CameraXManager]). Se compara el CONTENIDO y no
     * la fecha: `adb push` conserva la fecha del archivo de origen. */
    fun rawContent(context: Context): String? {
        val file = context.getExternalFilesDir(null)?.let { File(it, FILE_NAME) } ?: return null
        if (!file.isFile) return null
        return try {
            file.readText()
        } catch (_: Exception) {
            null
        }
    }

    /** Todos los valores efectivos, en formato `clave=valor`. */
    fun describe(cfg: Config = config): String =
        "delegate=${if (cfg.forceCpu) "cpu" else "gpu"} blendshapes=${cfg.blendshapes} " +
            "analysis_size=${cfg.analysisSize.width}x${cfg.analysisSize.height} " +
            "overlay=${if (cfg.overlay) "on" else "off"} flutter_events=${cfg.flutterEvents.name.lowercase(Locale.US)} " +
            "use_cases=${if (cfg.useCasesMinimal) "minimal" else "all"} " +
            "preview_size=${cfg.previewSize?.let { "${it.width}x${it.height}" } ?: "default"} " +
            "fps_range=${cfg.fpsRange ?: "default"} " +
            "lock_release=${if (cfg.lockReleaseAtStart) "start" else "end"} " +
            "detect_conf=${cfg.detectConf} presence_conf=${cfg.presenceConf} track_conf=${cfg.trackConf} " +
            "flutter_overlays=${if (cfg.flutterOverlays) "on" else "off"} " +
            "analysis_rotation=${if (cfg.analysisRotationCameraX) "camerax" else "canvas"} " +
            "extrapolation=${if (cfg.softExtrapolation) "soft" else "hard"} " +
            "sample_blend=${if (cfg.sampleBlend) "on" else "off"} " +
            "forward_age=${if (cfg.forwardAge) "on" else "off"} " +
            "euro_pos_ref=${cfg.euroPosRef} euro_rot_ref=${cfg.euroRotRef} " +
            "interval_margin=${cfg.intervalMarginMs} abs_max_extrap=${cfg.absMaxExtrapMs} " +
            "preview_latency=${cfg.previewLatencyMs} " +
            "closed_shift=${if (cfg.closedShiftInFollower) "follower" else "anchor"}"

    private const val TAG = "CameraXManager"
}
