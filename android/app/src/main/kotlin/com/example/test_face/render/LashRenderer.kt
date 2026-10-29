package com.example.test_face.render

import android.app.Activity
import android.os.Handler
import android.util.Log
import android.view.Choreographer
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import com.google.android.filament.Engine
import com.google.android.filament.IndirectLight
import com.google.android.filament.RenderableManager
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import io.github.sceneview.SceneView
import io.github.sceneview.geometries.Geometry
import io.github.sceneview.node.ModelNode
import kotlinx.coroutines.launch
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.exp

/**
 * Dueño de todo lo que ocurre dentro del [SceneView]: entorno/iluminación de
 * estudio, calidad de render, carga de los `.glb` de pestañas, y aplicación
 * de la pose calculada por [FaceRenderPipeline] a los nodos de cada ojo.
 *
 * `CameraXManager` solo lo instancia y le reenvía attach/detach/loadEyeModels
 * /onFaceResult — no contiene matemática de render (ver plan de
 * implementación, "CameraXManager deja de tener lógica de render").
 */
class LashRenderer(
    private val activity: Activity,
    private val mainHandler: Handler,
) {
    private var sceneView: SceneView? = null

    private val leftSlot = EyeModelSlot()
    private val rightSlot = EyeModelSlot()
    private val bufferTraceRendererId = BufferLifetimeTelemetry.nextId()

    /** Estilo activo del diseño cargado (ver [LashStyleConfig]) — un mismo
     * estilo se aplica a los dos ojos (la asimetría izq/der la resuelve
     * [RawMesh.mirroredAcrossX] en [loadIntoSlot], no esto). Se actualiza
     * desde [setStyle], invocado por el `MethodChannel` cuando Flutter
     * cambia de diseño; se lee desde el hilo de MediaPipe en
     * [onFaceResult]/[applyTransform] — @Volatile por el mismo motivo que
     * el resto del estado compartido entre esos dos hilos. */
    @Volatile private var currentStyleConfig: LashStyleConfig = LashStyleConfig.DEFAULT

    /**
     * Corre a vsync de pantalla (~60Hz+) mientras haya un [SceneView]
     * adjuntado, INDEPENDIENTE de la frecuencia con la que llegan
     * resultados de MediaPipe — lee la pose extrapolada de
     * [EyeModelSlot.interpolator] y la escribe al nodo en cada frame. Sin
     * esto, el nodo solo se actualizaba cuando llegaba un resultado nuevo
     * de MediaPipe (potencialmente bastante más lento que la pantalla), lo
     * que se percibía como que el modelo "no está pegado en tiempo real" al
     * preview de cámara. Se arranca en [attachSceneView] y se detiene en
     * [detachSceneView] — mismo ciclo de vida que el resto del estado del
     * SceneView.
     */
    private var frameLoopRunning = false

    /** Latencia medida del pipeline (MediaPipe + preprocesado), actualizada
     * por [onFaceResult] en cada resultado. [writeInterpolatedPose] la lee
     * desde el hilo principal (Choreographer) para que [PoseInterpolator]
     * sepa cuánto predecir hacia adelante. */
    /** Ultimo coverScaleX logueado, para reportar el encuadre una sola vez
     * por configuracion en vez de en cada frame. Ver CameraProjection. */
    private var loggedCoverScaleX = Float.NaN

    @Volatile private var measuredLatencyNanos = 35_000_000L  // seed: 35ms

    /** Antigüedad del frame al entregarlo a MediaPipe (sensor →
     * `detectAsync`), ver [onFaceResult]. 0 = no medible o `forward_age=off`:
     * el horizonte queda como antes. */
    @Volatile private var measuredPreSubmitNanos = 0L

    private var trajectoryEvaluationId = 0L
    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!frameLoopRunning) return
            // El re-agendado va en `finally`, NO como última sentencia del
            // cuerpo: si `writeInterpolatedPose` lanzaba cualquier cosa, el
            // `postFrameCallback` nunca se ejecutaba y este bucle moría PARA
            // SIEMPRE — el preview de cámara seguía corriendo (es otra
            // superficie) pero el modelo quedaba congelado en su última pose.
            // Se captura Throwable, no Exception: un Error (OOM, link) también
            // mataba el bucle.
            try {
                // DIAGNÓSTICO: frames largos del hilo principal + línea
                // TIEMPOS_ETAPAS cada 120 vsync (ver PerfStats). Corre también
                // con overlay=off, que es justo cuando más interesa.
                com.example.test_face.PerfStats.onVsync(frameTimeNanos)
                if (overlayEnabled) {
                    val capture = PoseTrajectoryTelemetry.current
                    if (capture != null) trajectoryEvaluationId++
                    writeInterpolatedPose(leftSlot, frameTimeNanos, capture, trajectoryEvaluationId)
                    writeInterpolatedPose(rightSlot, frameTimeNanos, capture, trajectoryEvaluationId)
                }
            } catch (e: Throwable) {
                if (!loggedFrameLoopFailure) {
                    loggedFrameLoopFailure = true
                    Log.e(TAG, "doFrame: excepción escribiendo la pose (solo se loguea la primera)", e)
                }
            } finally {
                if (frameLoopRunning) Choreographer.getInstance().postFrameCallback(this)
            }
        }
    }

    /** Ver [frameCallback] — evita inundar logcat si el fallo se repite en
     * cada vsync. */
    private var loggedFrameLoopFailure = false

    /** Ver [writeInterpolatedPose]. */
    private var loggedNonFinitePose = false

    /** Contador del log `PRESUPUESTO_LATENCIA` de [writeInterpolatedPose] —
     * solo el ojo izquierdo lo incrementa, así que a 60 Hz sale ~1 línea cada
     * 2 s. Es la herramienta para calibrar
     * [RendererConfiguration.EXTRA_LATENCY_TRIM_NANOS] en dispositivo: muestra
     * cuánto aporta cada tramo y si el tope de extrapolación está recortando
     * el horizonte pedido. */
    private var latencyLogFrames = 0

    fun attachSceneView(view: SceneView) {
        sceneView = view
        Log.i(
            TAG,
            "attachSceneView renderer=${System.identityHashCode(this)} view=${System.identityHashCode(view)} " +
                "engine=${System.identityHashCode(view.engine)} filamentRenderer=${System.identityHashCode(view.renderer)} " +
                "modelLoader=${System.identityHashCode(view.modelLoader)}",
        )
        configureEnvironment(view)
        configureRenderQuality(view)
        configureKeyLight(view)
        startFrameLoop()
    }

    /**
     * `false` con `overlay=off` en perf_flags.properties (ver
     * [com.example.test_face.PerfFlags.overlay]): el frame loop deja de
     * escribir la pose y el SceneView se oculta, para medir si Filament
     * compite con MediaPipe por la GPU. [CameraXManager] además deja de
     * llamar a [onFaceResult], así que tampoco se calcula ni se sube la malla.
     * Default `true` = comportamiento de siempre.
     */
    @Volatile private var overlayEnabled = true

    fun setOverlayEnabled(enabled: Boolean) {
        overlayEnabled = enabled
        mainHandler.post {
            val sv = sceneView ?: return@post
            val visibility = if (enabled) android.view.View.VISIBLE else android.view.View.GONE
            // Solo si cambia: con el default (`true`) no se toca nada.
            if (sv.visibility != visibility) {
                Log.i(TAG, "setOverlayEnabled($enabled): SceneView ${if (enabled) "visible" else "oculto (perf_flags)"}")
                sv.visibility = visibility
            }
        }
    }

    private fun startFrameLoop() {
        if (frameLoopRunning) return
        frameLoopRunning = true
        mainHandler.post { Choreographer.getInstance().postFrameCallback(frameCallback) }
    }

    private fun stopFrameLoop() {
        frameLoopRunning = false
    }

    /** Escribe en [slot.node] la pose extrapolada a [nowNanos] (ver
     * [PoseInterpolator]), suavizada a tasa de pantalla por [PoseFollower] —
     * no-op si el nodo no existe o está oculto (rostro perdido o cara en
     * movimiento, ver [showSlot]/[releaseSlot]/[hideSlotWhileMoving]). */
    /** Desplazamiento total con el ojo cerrado, en píxeles de la imagen de
     * análisis (dp + px físicos de [RendererConfiguration], convertidos con
     * el encuadre). Lo escribe [onFaceResult]; lo lee el vsync. */
    @Volatile private var closedDownShiftImagePx = 0f

    /**
     * Cuánto mover la pestaña hacia la MEJILLA en este vsync, en mundo.
     *
     * ## Por qué acá y no en el ancla
     *
     * Antes este desplazamiento iba dentro del ANCLA ([EyeAnchorCalculator]),
     * o sea dentro de la pose que se filtra y se EXTRAPOLA. Con blendshapes
     * la apertura es binaria ([OpennessTracker.updateFromBlendshape]): al
     * cerrar el ojo la posición pegaba un escalón entre dos resultados, el
     * One Euro (ultra-reactivo) lo dejaba pasar como "movimiento rápido" y
     * [PoseInterpolator] lo proyectaba cientos de ms hacia adelante: la
     * pestaña se pasaba de largo y volvía. Es el mismo motivo por el que
     * [LidDropRotation] se aplica al final.
     *
     * Ahora se aplica sobre la pose ya resuelta, escalado por
     * [PoseFollower.closedAmount] — el MISMO cierre suavizado (τ del
     * seguidor) que usa el volcado, así bajada y giro van juntos, en una
     * rampa continua y sin extrapolar.
     *
     * Dirección: `−up` de la CARA, `up = R(q)·(0,1,0)` (el +Y local es
     * "hacia la ceja", ver [LidDropRotation]). Va en el plano de la cara, no
     * en profundidad: no mete la pestaña dentro del rostro, y como sigue a
     * la pose vale igual con la clienta acostada.
     *
     * Escala px → mundo: [EyeModelSlot.worldPerImagePx], medida en el mismo
     * des-proyectado con que [EyeTransformCalculator] saca el ancho real del
     * ojo — a la profundidad del ojo, sin el multiplicador de ancho ni la
     * corrección por giro (que llega a 2.2× y desplazaría de más con la
     * cabeza girada). Si no hay dato (camino de malla), cae a
     * `eyeSpanWorld / (eyeWidthPx · WIDTH_MULTIPLIER)`.
     */
    private fun applyClosedDownShift(
        slot: EyeModelSlot,
        transform: EyeTransform,
        closedAmount: Float,
        q: Quaternion,
    ): Float3 {
        if (!com.example.test_face.PerfFlags.config.closedShiftInFollower) return Float3()
        val shiftPx = closedDownShiftImagePx
        val widthPx = transform.eyeWidthPx
        if (shiftPx <= 0f || !closedAmount.isFinite() || closedAmount <= 1e-3f) return Float3()
        val measured = slot.worldPerImagePx
        val worldPerPx = when {
            measured > 0f -> measured
            widthPx.isFinite() && widthPx > 1e-3f ->
                eyeSpanWorld(slot) / (widthPx * RendererConfiguration.WIDTH_MULTIPLIER)
            else -> return Float3()
        }
        val amount = shiftPx * worldPerPx * closedAmount.coerceIn(0f, 1f)
        if (!amount.isFinite()) return Float3()
        // up = R(q)·(0,1,0)
        val upX = 2f * (q.x * q.y - q.w * q.z)
        val upY = 1f - 2f * (q.x * q.x + q.z * q.z)
        val upZ = 2f * (q.y * q.z + q.w * q.x)
        return Float3(-upX * amount, -upY * amount, -upZ * amount)
    }

    /** Ancho del ojo en unidades de mundo (misma medida que usa
     * [EyeTrackingFilter] para expresar velocidades en anchos de ojo). */
    private fun eyeSpanWorld(slot: EyeModelSlot): Float = slot.naturalSpan * slot.follower.scaleX

    // DIAGNÓSTICO `temblor=` (ver [PerfStats.onPoseJitter]): las dos poses
    // anteriores del ojo izquierdo. Solo el hilo principal.
    private var jitterPrevPos: Float3? = null
    private var jitterPrevPrevPos: Float3? = null
    private var jitterPrevRot: Quaternion? = null
    private var jitterPrevStep: Float3? = null
    private var jitterLastNanos = 0L

    /**
     * Segunda diferencia de la pose que se escribe en el nodo, por vsync: en
     * posición `|p_t − 2p_{t−1} + p_{t−2}|` en anchos de ojo, y en rotación
     * el cambio entre dos giros consecutivos (vector de rotación por vsync),
     * en grados. Una pestaña que se mueve suave da ~0 aunque vaya rápido; un
     * rebote o un temblor la disparan — es el número que compara
     * configuraciones sin depender del ojo de quien mira.
     */
    private fun recordPoseJitter(position: Float3, rotation: Quaternion, span: Float, nowNanos: Long) {
        // Tras un hueco (nodo oculto, rostro perdido) la "pose anterior" es
        // de antes del hueco: daría un pico falso. Se rearma la historia.
        if (nowNanos - jitterLastNanos > JITTER_MAX_GAP_NANOS) {
            jitterPrevPos = null
            jitterPrevPrevPos = null
            jitterPrevRot = null
            jitterPrevStep = null
        }
        jitterLastNanos = nowNanos
        val p1 = jitterPrevPos
        val p2 = jitterPrevPrevPos
        val r1 = jitterPrevRot
        val step = r1?.let { rotationVectorDegrees(rotation, it) }
        val s1 = jitterPrevStep
        if (p1 != null && p2 != null && step != null && s1 != null && span > 1e-6f) {
            val d = position - p1 * 2f + p2
            val dr = step - s1
            com.example.test_face.PerfStats.onPoseJitter(
                spans = kotlin.math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z) / span,
                degrees = kotlin.math.sqrt(dr.x * dr.x + dr.y * dr.y + dr.z * dr.z),
            )
        }
        jitterPrevPrevPos = p1
        jitterPrevPos = position
        jitterPrevRot = rotation
        jitterPrevStep = step
    }

    /** Giro de [from] a [to] como vector de rotación (eje × ángulo), en
     * grados — por el camino corto. */
    private fun rotationVectorDegrees(to: Quaternion, from: Quaternion): Float3 {
        // d = to · conj(from)
        val fx = -from.x; val fy = -from.y; val fz = -from.z; val fw = from.w
        var x = to.w * fx + to.x * fw + to.y * fz - to.z * fy
        var y = to.w * fy - to.x * fz + to.y * fw + to.z * fx
        var z = to.w * fz + to.x * fy - to.y * fx + to.z * fw
        var w = to.w * fw - to.x * fx - to.y * fy - to.z * fz
        if (w < 0f) { x = -x; y = -y; z = -z; w = -w }
        val sinHalf = kotlin.math.sqrt(x * x + y * y + z * z)
        if (sinHalf < 1e-7f) return Float3()
        val angleDeg = Math.toDegrees(2.0 * kotlin.math.atan2(sinHalf.toDouble(), w.toDouble())).toFloat()
        val k = angleDeg / sinHalf
        return Float3(x * k, y * k, z * k)
    }

    private fun writeInterpolatedPose(slot: EyeModelSlot, nowNanos: Long,
        trajectoryCapture: PoseTrajectoryTelemetry.Capture? = null, evaluationId: Long = 0L) {
        val node = slot.node
        if (node == null || !node.isVisible) {
            if (trajectoryCapture != null) slot.interpolator.traceTrajectory(trajectoryCapture,
                if (slot === leftSlot) 0 else 1, evaluationId, nowNanos,
                null, null, null, lostFrames, if (node == null) 128 else 256)
            return
        }
        // ── PRESUPUESTO DE LATENCIA COMPLETO ────────────────────────────
        // Cuánto hay que predecir hacia adelante = todo lo que la pose ya
        // atrasó desde que la cámara capturó el frame. Son cuatro tramos, y
        // hasta el fix del "delay al moverse" solo se contaban dos:
        //
        //  1. measuredLatencyNanos — captura→resultado de MediaPipe, MEDIDO
        //     en este dispositivo, +16 ms de composición (ver onFaceResult).
        //  2. EyeTrackingFilter — el One Euro por el que pasa la pose después
        //     de MediaPipe. ADAPTATIVO: ~10-25 ms moviéndose, más en reposo.
        //     No lo compensaba nadie; ver EyeTrackingFilter.groupDelayNanos.
        //  3. POSE_FOLLOW_TAU_NANOS — el retardo del seguidor de acá abajo,
        //     que se cancela pidiendo la pose un tau más adelante.
        //  4. EXTRA_LATENCY_TRIM_NANOS — el camino de preview, que no se
        //     puede medir desde acá; ajuste manual, 0 por defecto.
        //
        // El tramo 2 se lee del filtro del propio ojo (@Volatile, escrito
        // desde el hilo de MediaPipe) y se acota, porque el horizonte también
        // amplifica el ruido residual de los landmarks.
        val filterDelayNanos = slot.filter.groupDelayNanos
            .coerceIn(0L, RendererConfiguration.FILTER_DELAY_COMPENSATION_MAX_NANOS)
        // Tramo 0 (2026-10-28): la antigüedad del frame ANTES de entregarlo
        // a MediaPipe (measuredPreSubmitNanos, medida por frame contra el
        // reloj del sensor) menos la latencia del propio preview — la pestaña
        // tiene que caer sobre la cara TAL COMO SE VE en el preview, que
        // también va atrasada. Sin este tramo la pose se dibujaba ~edad_envio
        // en el pasado: el "arrastre" al girar rápido.
        // `preview_latency` de perf_flags (en caliente); default =
        // [RendererConfiguration.PREVIEW_PATH_LATENCY_NANOS].
        val previewNanos = if (measuredPreSubmitNanos > 0L) {
            (com.example.test_face.PerfFlags.config.previewLatencyMs * 1_000_000f).toLong()
        } else {
            0L
        }
        val horizonNanos = measuredLatencyNanos +
            measuredPreSubmitNanos - previewNanos +
            filterDelayNanos +
            RendererConfiguration.POSE_FOLLOW_TAU_NANOS +
            RendererConfiguration.EXTRA_LATENCY_TRIM_NANOS
        val transform = slot.interpolator.sample(
            nowNanos,
            horizonNanos.coerceAtLeast(0L),
            statsEyeSpanWorld = if (slot === leftSlot) eyeSpanWorld(slot) else 0f,
            traceEye = if (slot === leftSlot) 0 else 1,
            traceSpanWorld = if (com.example.test_face.PerfFlags.config.timestampTrace) eyeSpanWorld(slot) else 0f,
        ) ?: return
        if (slot === leftSlot) {
            com.example.test_face.PerfStats.onExtrapolationSample(slot.interpolator.lastSampleSaturated)
        }
        // Una pose NO FINITA (NaN/Inf) escrita en el nodo se queda ahí: el
        // modelo desaparece o se congela y ningún frame posterior lo
        // recupera, porque el valor malo ya está en la TransformManager de
        // Filament. Puede originarse aguas arriba (p.ej. `unproject` divide
        // por `projection.x.x`, que es 0 si la cámara todavía no está
        // configurada). Saltear el frame conserva la última pose buena y deja
        // que el siguiente la corrija.
        val p = transform.position
        val q = transform.rotation
        val sc = transform.scale
        if (!p.x.isFinite() || !p.y.isFinite() || !p.z.isFinite() ||
            !q.x.isFinite() || !q.y.isFinite() || !q.z.isFinite() || !q.w.isFinite() ||
            !sc.x.isFinite() || !sc.y.isFinite() || !sc.z.isFinite()
        ) {
            if (trajectoryCapture != null) slot.interpolator.traceTrajectory(trajectoryCapture,
                if (slot === leftSlot) 0 else 1, evaluationId, nowNanos,
                null, null, null, lostFrames, 512 or 1024)
            if (!loggedNonFinitePose) {
                loggedNonFinitePose = true
                Log.w(TAG, "writeInterpolatedPose: pose no finita descartada pos=$p quat=$q scale=$sc")
            }
            return
        }
        if (slot === leftSlot && ++latencyLogFrames >= LATENCY_LOG_EVERY_FRAMES) {
            latencyLogFrames = 0
            Log.i(
                TAG,
                "PRESUPUESTO_LATENCIA pipeline=${measuredLatencyNanos / 1_000_000}ms " +
                    "edad_previa=${measuredPreSubmitNanos / 1_000_000}ms " +
                    "preview=-${previewNanos / 1_000_000}ms " +
                    "filtro=${filterDelayNanos / 1_000_000}ms " +
                    "seguidor=${RendererConfiguration.POSE_FOLLOW_TAU_NANOS / 1_000_000}ms " +
                    "trim=${RendererConfiguration.EXTRA_LATENCY_TRIM_NANOS / 1_000_000}ms " +
                    "-> horizonte=${horizonNanos / 1_000_000}ms " +
                    "(tope=${(slot.interpolator.lastCapNanos / 1_000_000f).toInt()}ms)",
            )
        }
        slot.follower.advance(transform, nowNanos)
        if (com.example.test_face.PerfFlags.config.timestampTrace) slot.interpolator.traceFollower(slot.follower, nowNanos)
        val f = slot.follower

        var position = Float3(f.posX, f.posY, f.posZ)
        var rotation = Quaternion(f.rotX, f.rotY, f.rotZ, f.rotW)
        if (slot === leftSlot) recordPoseJitter(position, rotation, eyeSpanWorld(slot), nowNanos)

        // OJO CERRADO: la pestaña baja hacia la mejilla — ver
        // [applyClosedDownShift]. Con la orientación de la CARA (antes del
        // volcado de abajo), para que "abajo" sea el de la cara y no el de la
        // pestaña ya girada.
        position += applyClosedDownShift(slot, transform, f.closedAmount, rotation)

        // OJO CERRÁNDOSE: la pestaña gira hacia abajo con el párpado (ver
        // [LidDropRotation]). Va acá, al final de todo, y no en el cálculo de
        // la transformación, porque un parpadeo NO se puede extrapolar como
        // se extrapola la pose de la cabeza.
        LidDropRotation.apply(
            closedAmount = f.closedAmount,
            rootLocalY = slot.rootLocalY,
            scaleY = f.scaleY,
            q = rotation,
        )?.let { drop ->
            rotation = drop.rotation
            position += drop.positionDelta
        }

        node.position = position
        node.quaternion = rotation
        node.scale = Float3(f.scaleX, f.scaleY, f.scaleZ)
        if (trajectoryCapture != null) slot.interpolator.traceTrajectory(trajectoryCapture,
            if (slot === leftSlot) 0 else 1, evaluationId, nowNanos,
            f, position, rotation, lostFrames)
    }

    /**
     * [view] es la instancia que se está desmontando — ver la nota en
     * `CameraXManager.detachPreview`: si Flutter ya montó un `SceneView`
     * nuevo (y llamó [attachSceneView] con él) antes de que el anterior
     * termine de destruirse, este `detach` tardío no debe tocar el estado
     * del nuevo.
     */
    fun detachSceneView(view: SceneView) {
        if (sceneView !== view) {
            Log.w(
                TAG,
                "detachSceneView IGNORADO — view=${System.identityHashCode(view)} ya no es la sceneView " +
                    "actual (actual=${sceneView?.let { System.identityHashCode(it) }}); el nuevo PlatformView " +
                    "ya se adjuntó antes de que este dispose() tardío llegara.",
            )
            return
        }
        Log.i(
            TAG,
            "detachSceneView renderer=${System.identityHashCode(this)} view=${System.identityHashCode(view)} " +
                "engine=${System.identityHashCode(view.engine)}",
        )
        stopFrameLoop()
        for (slot in listOf(leftSlot, rightSlot)) {
            slot.node?.let { old ->
                Log.i(TAG, "detachSceneView destruyendo node=${System.identityHashCode(old)} path=${slot.path}")
                view.removeChildNode(old)
                old.destroy()
            }
            slot.reset()
        }
        sceneView = null
    }

    /**
     * Carga los .glb de pestañas de cada ojo (cateyeleft/cateyeright) en el
     * [SceneView] superpuesto a la cámara. `null` en cualquiera de los dos
     * parámetros retira el modelo de ese ojo sin tocar el otro. Si el modelo
     * ya está cargado con el mismo path no se recarga.
     */
    fun loadEyeModels(leftPath: String?, rightPath: String?) {
        // Señal EXPLÍCITA de cuándo espejar (ver RawMesh.mirroredAcrossX):
        // los diseños del backend solo guardan UN .glb por diseño (no un par
        // izq/der como el catálogo local — ver `eye_tracking_page.dart`,
        // "El backend solo guarda un .glb por diseño") y le pasan la MISMA
        // ruta a los dos ojos. En ese caso, y SOLO en ese caso, hace falta
        // espejar una de las dos copias — si el catálogo local ya carga dos
        // archivos DISTINTOS (`leftPath != rightPath`), se asume que el
        // artista ya los exportó como par espejado correcto (confirmado con
        // un script propio comparando el perfil de profundidad Z de los 5
        // pares de `assets/modelos/`: los 5 correlacionan mucho mejor en
        // orden espejado que en el mismo orden) y este mirror NO se aplica
        // — aplicarlo ahí duplicaría el espejado y volvería a romper la
        // simetría que ya está bien.
        val mirrorRightEye = leftPath != null && leftPath == rightPath
        Log.i(
            TAG,
            "loadEyeModels renderer=${System.identityHashCode(this)} " +
                "sceneView=${sceneView?.let { System.identityHashCode(it) }} left=$leftPath right=$rightPath " +
                "mirrorRightEye=$mirrorRightEye",
        )
        loadIntoSlot(leftSlot, leftPath, "LEFT", mirror = false)
        loadIntoSlot(rightSlot, rightPath, "RIGHT", mirror = mirrorRightEye)
    }

    /**
     * Actualiza [currentStyleConfig] a partir de un `styleId` enviado desde
     * Flutter (ver [LashStyleConfig.forStyleId]) — se llama junto con
     * [loadEyeModels] cuando cambia el diseño activo (mismo `MethodChannel`,
     * ver `EyeTrackingPlugin`/`CameraXManager`). No toca `node`/`rawMesh` de
     * ningún slot: el próximo [onFaceResult] ya usa el estilo nuevo para el
     * ancla (`EyeAnchorCalculator`) y el doblado (`LashMeshBender`) sin
     * necesidad de recargar el `.glb`.
     */
    fun setStyle(styleId: String?) {
        val resolved = LashStyleConfig.forStyleId(styleId)
        Log.i(TAG, "setStyle styleId=$styleId -> $resolved")
        currentStyleConfig = resolved
    }

    /**
     * Punto de entrada por frame: recibe el resultado crudo de MediaPipe
     * (para la pose 3D completa vía [FaceRenderPipeline]) y lo traduce en la
     * transformación final de cada nodo, suavizada por el filtro propio de
     * su [EyeModelSlot]. El cálculo pesado corre en el hilo llamante (el de
     * MediaPipe); solo la escritura final de la transformación en el nodo se
     * despacha al hilo principal, igual que antes, por rendimiento.
     */
    fun onFaceResult(
        result: FaceLandmarkerResult,
        imageWidth: Int,
        imageHeight: Int,
        pipelineLatencyMs: Float = 35f,
        /** Bitmap EXACTO analizado por MediaPipe para [result] (ver
         * [FaceLandmarkerHelper]) — [LashEdgeDetector] lo usa para anclar
         * sobre la pestaña real visible, no solo sobre el landmark
         * estimado. `null` degrada a solo landmarks (comportamiento
         * anterior). */
        cameraBitmap: android.graphics.Bitmap? = null,
        /** Antigüedad del frame AL ENTREGARLO a MediaPipe (espera del
         * ImageProxy + copia + Canvas), medida contra el reloj del sensor.
         * [pipelineLatencyMs] empieza a contar recién en `detectAsync`, así
         * que sin esto el horizonte no compensaba ese tramo. 0 = no medible
         * (fuente de timestamp no REALTIME) o desactivado. */
        preSubmitAgeMs: Float = 0f,
        traceContext: com.example.test_face.TrackingTimingTelemetry.Context? = null,
    ) {
        if (leftSlot.node == null && rightSlot.node == null) return

        // Actualizar la latencia medida para que writeInterpolatedPose la use
        // en el próximo vsync. +16ms para compensar la composición de
        // SurfaceFlinger (2 superficies separadas: PreviewView + SceneView).
        measuredLatencyNanos = ((pipelineLatencyMs + 16f) * 1_000_000f).toLong()
        measuredPreSubmitNanos = (preSubmitAgeMs.coerceAtLeast(0f) * 1_000_000f).toLong()

        val sv = sceneView ?: return
        // fillCenter (no el constructor directo): los landmarks vienen
        // normalizados contra la imagen de análisis, pero el SceneView cubre
        // la pantalla y el preview de abajo recorta con FILL_CENTER. Ver
        // CameraProjection.coverScaleX — sin esto el modelo se coloca a ~62%
        // de la distancia horizontal correcta respecto al centro.
        val camera = CameraProjection.fillCenter(
            projection = sv.cameraNode.projectionTransform,
            cameraToWorld = sv.cameraNode.modelTransform,
            imageWidth = imageWidth,
            imageHeight = imageHeight,
            viewportWidth = sv.width,
            viewportHeight = sv.height,
        )
        if (loggedCoverScaleX != camera.coverScaleX) {
            loggedCoverScaleX = camera.coverScaleX
            Log.i(
                TAG,
                "COVER imagen=${imageWidth}x$imageHeight viewport=${sv.width}x${sv.height} " +
                    "coverScaleX=${camera.coverScaleX} coverScaleY=${camera.coverScaleY}",
            )
        }

        // dp → píxeles de pantalla → píxeles de la imagen de análisis (el
        // preview la escala con FILL_CENTER, ver CameraProjection.fillCenter).
        val screenPxPerImagePx = if (imageWidth > 0 && imageHeight > 0 && sv.width > 0 && sv.height > 0) {
            maxOf(sv.width.toFloat() / imageWidth, sv.height.toFloat() / imageHeight)
        } else {
            0f
        }
        val closedDownShiftPx = if (screenPxPerImagePx > 0f) {
            (RendererConfiguration.LASH_CLOSED_DOWN_SHIFT_DP * sv.resources.displayMetrics.density +
                RendererConfiguration.LASH_CLOSED_DOWN_SHIFT_EXTRA_PX) / screenPxPerImagePx
        } else {
            0f
        }
        // `closed_shift=follower` (default, ver [applyClosedDownShift]): el
        // desplazamiento NO entra al ancla — se aplica en cada vsync sobre la
        // pose ya resuelta. `anchor`: el camino de antes, dentro del ancla.
        closedDownShiftImagePx = closedDownShiftPx
        val anchorShiftPx = if (com.example.test_face.PerfFlags.config.closedShiftInFollower) 0f else closedDownShiftPx

        val pipelineResult = try {
            FaceRenderPipeline.compute(
                result = result,
                imageWidth = imageWidth,
                imageHeight = imageHeight,
                leftNaturalSpan = leftSlot.naturalSpan,
                rightNaturalSpan = rightSlot.naturalSpan,
                camera = camera,
                leftRootLocalY = leftSlot.rootLocalY,
                rightRootLocalY = rightSlot.rootLocalY,
                styleConfig = currentStyleConfig,
                cameraBitmap = cameraBitmap,
                leftLidFilter = leftSlot.lidFilter,
                rightLidFilter = rightSlot.lidFilter,
                leftBlinkTracker = leftSlot.openness,
                rightBlinkTracker = rightSlot.openness,
                leftLidShape = leftSlot.lidShape,
                rightLidShape = rightSlot.lidShape,
                closedDownShiftPx = anchorShiftPx,
            )
        } catch (e: Exception) {
            Log.e(TAG, "onFaceResult: fallo calculando la transformación", e)
            null
        }
        if (pipelineResult == null) {
            onFaceLost()
            return
        }

        // Vuelve el rostro tras una retención (ver [onFaceLost]). El log es
        // el que distingue las dos causas posibles de "se congela y salta":
        // si al mover la cabeza aparece esta línea, MediaPipe está perdiendo
        // el rostro por desenfoque; si no aparece, el atraso es del filtro.
        val recovering = lostFrames > 0
        if (recovering) {
            Log.i(
                TAG,
                "rostro recuperado tras $lostFrames frames " +
                    "(${(System.nanoTime() - lostSinceNanos) / 1_000_000} ms) — mezcla suave",
            )
        }
        lostFrames = 0
        // Timestamp de CAPTURA del frame (el que se pasó a `detectAsync`, en
        // `uptimeMillis`), no la hora de llegada del resultado: ver
        // [EyeTrackingFilter.apply].
        val frameNanos = result.timestampMs() * 1_000_000L
        OrientDebug.logLash(pipelineResult.left, pipelineResult.right) // TEMPORAL
        applyTransform(leftSlot, pipelineResult.left, sv.engine, frameNanos, recovering, traceContext)
        applyTransform(rightSlot, pipelineResult.right, sv.engine, frameNanos, recovering, traceContext)
    }

    /**
     * Resultados seguidos sin rostro y desde cuándo. Solo los toca el hilo
     * de MediaPipe ([onFaceResult]/[onFaceLost]) salvo el reset de
     * [resetTracking], que llega del principal — `@Volatile` alcanza: lo peor
     * es que un frame vea el contador viejo.
     */
    @Volatile private var lostFrames = 0
    @Volatile private var lostSinceNanos = 0L

    /**
     * Sin rostro en ESTE resultado. NO oculta enseguida: durante
     * [RendererConfiguration.FACE_LOST_HOLD_NANOS] la pestaña se queda en su
     * última pose válida (el frame loop sigue muestreando el interpolador,
     * que deja de extrapolar pasado su `MAX_EXTRAPOLATION_NANOS`). Si el
     * rostro vuelve antes, se continúa sin salto ni recalentado. Recién al
     * vencer el plazo se oculta y se borra el estado (ver [releaseSlot]).
     *
     * Se usa tiempo y no un número fijo de frames porque la tasa de
     * resultados depende del dispositivo (ver el cerrojo de
     * `FaceLandmarkerHelper.detectAsync`): 6 frames son 200 ms a 30 fps pero
     * 400 ms a 15. [lostFrames] queda para el log.
     */
    fun onFaceLost() {
        val now = System.nanoTime()
        if (lostFrames == 0) lostSinceNanos = now
        lostFrames++
        if (now - lostSinceNanos < RendererConfiguration.FACE_LOST_HOLD_NANOS) return
        if (leftSlot.visibleRequested != false || rightSlot.visibleRequested != false) {
            Log.i(TAG, "onFaceLost: $lostFrames frames sin rostro (${(now - lostSinceNanos) / 1_000_000} ms) -> se oculta")
        }
        releaseSlot(leftSlot)
        releaseSlot(rightSlot)
    }

    /**
     * Oculta y borra el estado YA, sin el margen de [onFaceLost]. Para cuando
     * la cámara se detiene (`CameraXManager.stop`): ahí no hay pérdida
     * transitoria que tapar.
     */
    fun resetTracking() {
        lostFrames = 0
        releaseSlot(leftSlot)
        releaseSlot(rightSlot)
    }

    /**
     * ROSTRO PERDIDO: oculta el modelo y borra TODO el estado temporal del
     * ojo, para que al redetectar un rostro (puede ser otra persona, o la
     * misma a otra distancia) nada se herede.
     *
     * OJO — esto NO es el camino del parpadeo (ver [applyTransform]). Hasta
     * el fix de 2026-09-04 era el mismo método para los dos casos, y por eso
     * CADA parpadeo borraba:
     *  - la línea base de apertura de la persona ([OpennessTracker.reset]),
     *    con lo que el tracker volvía a calentamiento durante ~15 muestras
     *    (≈0.5 s) justo mientras el ojo se reabría, y aprendía la base nueva
     *    a partir de valores de ojo medio cerrado — o sea que el umbral
     *    quedaba peor calibrado después de cada parpadeo;
     *  - el historial de [UpperLidFilter], con lo que el primer frame tras
     *    el parpadeo doblaba la malla con puntos SIN suavizar;
     *  - y el suavizado de pose + el interpolador, con lo que la pestaña
     *    reaparecía dando un salto en vez de continuar donde estaba.
     * Esos tres borrados por parpadeo son la razón de que el efecto fuera
     * PROGRESIVO: cuanto más parpadeaba la persona, peor quedaba.
     */
    private fun releaseSlot(slot: EyeModelSlot) {
        slot.traceTrackingBoundary()
        val node = slot.node
        slot.filter.reset()
        // Mismo hilo que `filter` (ver [MotionGate]): al redetectar el rostro,
        // la puerta de movimiento vuelve a exigir su ventana de calma antes
        // del primer dibujado, en vez de heredar el "estaba visible" de la
        // persona anterior.
        slot.motionGate.reset()
        if (node != null) {
            mainHandler.post {
                // El interpolador se resetea acá (hilo principal, mismo hilo
                // que lo lee en writeInterpolatedPose vía el frame loop) para
                // que no queden muestras viejas esperando a extrapolarse
                // cuando el rostro reaparezca.
                slot.interpolator.reset()
                slot.follower.reset()
                // Mismo motivo que el interpolador: sin esto, al redetectar
                // el rostro la curva del párpado arrancaría mezclada con la
                // forma de hace varios segundos (ver UpperLidFilter).
                slot.lidFilter.reset()
                slot.openness.reset()
                slot.lidShape.reset()
                if (node.isVisible) {
                    Log.i(TAG, "releaseSlot node=${System.identityHashCode(node)} -> OCULTO (onFaceLost)")
                }
                node.isVisible = false
            }
        }
        slot.visibleRequested = false
    }

    /**
     * Muestra la pestaña, deduplicando contra la última visibilidad pedida
     * (ver [EyeModelSlot.visibleRequested]) para no encolar un `post` por
     * cada resultado de MediaPipe ni repetir el log.
     *
     * Los caminos que ocultan son [releaseSlot] (rostro perdido) y
     * [hideSlotWhileMoving] (cara en movimiento). El parpadeo NO oculta nada
     * — ver la nota en [applyTransform].
     */
    private fun showSlot(slot: EyeModelSlot) {
        if (slot.visibleRequested == true) return
        slot.visibleRequested = true
        val node = slot.node ?: return
        mainHandler.post {
            Log.i(TAG, "showSlot node=${System.identityHashCode(node)} -> VISIBLE")
            node.isVisible = true
            // El seguidor arranca de cero en la pose objetivo: si conservara
            // su estado, la pestaña reaparecería deslizándose desde donde
            // estaba antes de ocultarse en vez de aparecer ya puesta.
            slot.follower.reset()
            // El frame loop no escribe la pose mientras el nodo está oculto
            // (ver [writeInterpolatedPose]), así que el nodo todavía tiene la
            // pose de antes de ocultarse. Sin esto, el primer frame visible
            // dibujaría la pestaña en esa posición vieja — exactamente el
            // "aparece flotando" que la puerta de movimiento viene a evitar.
            // Se escribe acá, en el mismo Runnable del hilo principal, así
            // visibilidad y pose llegan juntas al mismo frame de Filament.
            writeInterpolatedPose(slot, System.nanoTime())
        }
    }

    /**
     * CARA EN MOVIMIENTO: oculta la pestaña sin tocar NADA del estado de
     * tracking — al revés que [releaseSlot], que borra filtros e
     * interpolador porque ahí el rostro se perdió de verdad.
     *
     * Acá el rostro sigue estando y el pipeline sigue corriendo con el nodo
     * oculto: filtro, interpolador, apertura, forma del párpado y doblado de
     * malla se mantienen al día. Por eso el retorno es instantáneo y en la
     * posición correcta, en vez de tener que recalentar ([PoseInterpolator]
     * necesita `WARMUP_PUSHES` muestras, [OpennessTracker] ~15) como pasaría
     * si esto reseteara el estado.
     */
    private fun hideSlotWhileMoving(slot: EyeModelSlot) {
        if (slot.visibleRequested == false) return
        slot.visibleRequested = false
        val node = slot.node ?: return
        mainHandler.post {
            Log.i(TAG, "hideSlotWhileMoving node=${System.identityHashCode(node)} -> OCULTO (movimiento)")
            node.isVisible = false
        }
    }

    /**
     * Calcula la transformación suavizada del frame y la registra en
     * [EyeModelSlot.interpolator] — el rígido (posición/rotación/escala) ya
     * NO se escribe al nodo directamente acá: eso lo hace
     * [writeInterpolatedPose] en cada vsync (ver [frameCallback]),
     * desacoplado de la frecuencia con la que llega este resultado de
     * MediaPipe. El doblado del párpado ([LashMeshBender]), en cambio, SÍ
     * se aplica una vez por resultado (no por vsync): necesita los
     * landmarks crudos del frame, que solo existen acá.
     */
    private fun applyTransform(
        slot: EyeModelSlot,
        transform: EyeTransform?,
        engine: Engine,
        frameNanos: Long,
        /** Primer resultado con rostro tras una retención (ver [onFaceLost]). */
        recovering: Boolean = false,
        traceContext: com.example.test_face.TrackingTimingTelemetry.Context? = null,
    ) {
        if (slot.node == null) return
        if (transform == null) {
            releaseSlot(slot)
            return
        }
        if (recovering) slot.traceTrackingBoundary()
        // Ver [applyClosedDownShift]: conversión px → mundo de ESTE frame.
        if (transform.worldPerImagePx > 0f && transform.worldPerImagePx.isFinite()) {
            slot.worldPerImagePx = transform.worldPerImagePx
        }
        // EL PARPADEO YA NO OCULTA NI ENCOGE LA PESTAÑA.
        //
        // Antes se calculaba un `damping` en `[0,1]` a partir de la apertura,
        // se multiplicaba `scale * damping` y, al llegar a cero, se ocultaba
        // el nodo. Las dos cosas están mal para este producto: una extensión
        // real no se achica al cerrar el ojo, y con el ojo CERRADO es
        // justamente cuando más se luce — ocultarla ahí es lo contrario de
        // lo que la usuaria quiere ver al probarse un diseño. Ahora la
        // pestaña se dibuja siempre que haya rostro: solo [onFaceLost] la
        // oculta.
        //
        // Lo único que el parpadeo decide es `lidShapeTrusted` (ver
        // [OpennessTracker]/[LidShape]), o sea si la FORMA se re-mide o se
        // reusa la última buena — eso ya lo resolvió FaceRenderPipeline, acá
        // solo se consume para saber si hay que volver a doblar la malla.
        val trajectoryCapture = PoseTrajectoryTelemetry.current
        val rawElapsedNs = if (trajectoryCapture != null) android.os.SystemClock.elapsedRealtimeNanos() else 0L
        val smoothed = slot.filter.apply(transform, frameNanos, slot.naturalSpan)
        val nowNanos = System.nanoTime()
        val euroElapsedNs = if (trajectoryCapture != null) android.os.SystemClock.elapsedRealtimeNanos() else 0L

        // REESCRITO a buffer directo con setBufferAt in-place (ver
        // LashMeshBender/EyeModelSlot) — cero Geometry.Vertex/Float3 nuevos
        // por vértice, así que ya no hace falta el throttle de
        // LASH_BEND_MIN_INTERVAL_NANOS (existía para acotar la TASA de esas
        // asignaciones, no la tasa de recálculo en sí): se recalcula en
        // CADA resultado de MediaPipe, igual que la malla facial de 468
        // puntos. bendPending sigue como única red de seguridad si el hilo
        // principal se atrasa.
        val curve = transform.lashLineCurve
        val bufferTraceModel = slot.bufferModelGeneration.get()
        val rawMesh = slot.rawMesh
        val geometry = slot.geometry
        val target = if (slot.useBufferAAsTarget) slot.positionBufferA else slot.positionBufferB
        val prior = if (slot.useBufferAAsTarget) slot.positionBufferB else slot.positionBufferA
        val restTangents = slot.restTangents
        val tangentTarget = slot.tangentBuffer
        // ── Compensación de banda con el ojo cerrándose ─────────────────
        // [LidDropRotation.apply] vuelca el NODO ENTERO, o sea que invierte
        // también el arco de la línea donde nacen las fibras y la raíz deja
        // de seguir el párpado. Doblar la malla con el desvío dividido por
        // `cos θ` cancela justo esa parte: tras el giro la banda vuelve a
        // apoyarse en el párpado y lo único volcado son las fibras.
        //
        // El cierre se suaviza acá con el mismo τ del seguidor porque el
        // giro se aplica en el hilo de render CON esa inercia; compensar
        // por el cierre crudo adelantaría la malla al giro y se vería un
        // tirón en cada parpadeo.
        val targetClosed = (1f - transform.normalizedOpenness).coerceIn(0f, 1f)
        val closedDtNanos = nowNanos - slot.bendClosedNanos
        val closedTau = RendererConfiguration.POSE_FOLLOW_TAU_NANOS.toFloat()
        val closedAlpha = if (
            slot.bendClosedNanos == 0L || closedDtNanos <= 0L || closedTau <= 0f ||
            closedDtNanos > RendererConfiguration.POSE_FOLLOW_MAX_GAP_NANOS
        ) 1f else 1f - exp(-closedDtNanos.toFloat() / closedTau)
        slot.bendClosedAmount += (targetClosed - slot.bendClosedAmount) * closedAlpha
        slot.bendClosedNanos = nowNanos
        val bandScale = LidDropRotation.bandCompensation(slot.bendClosedAmount)
        val bendCurve = curve?.withDeviationScale(bandScale)

        // `lidShapeTrusted == false` (ojo cerrándose): con la forma congelada
        // el doblado se saltea, porque ocurre en espacio LOCAL del mesh y
        // solo depende de la curva y del ancho del ojo — re-doblarlo con la
        // curva congelada daría exactamente la malla que la GPU ya tiene.
        // La excepción es que haya cambiado [bandScale]: ahí la curva
        // efectiva SÍ es otra y hay que rehacer el doblado.
        val bandScaleChanged = abs(bandScale - slot.lastBandScale) > 1e-3f
        if ((transform.lidShapeTrusted || bandScaleChanged) &&
            bendCurve != null && rawMesh != null && geometry != null && target != null &&
            restTangents != null && tangentTarget != null && !slot.bendPending
        ) {
            val bufferWrite = if (com.example.test_face.PerfFlags.config.bufferLifetimeTrace)
                BufferLifetimeTelemetry.begin(slot, bufferTraceRendererId, if (slot === leftSlot) 0 else 1,
                    bufferTraceModel, target, tangentTarget) else null
            var diagnosticBent = false
            val bent = try { LashMeshBender.bendInPlace(
                raw = rawMesh,
                target = target,
                previous = if (slot.hasBentBefore) prior else null,
                restTangents = restTangents,
                tangentTarget = tangentTarget,
                smoothing = RendererConfiguration.LASH_BEND_SMOOTHING,
                curve = bendCurve,
                styleConfig = currentStyleConfig,
                eyeWidthPx = transform.eyeWidthPx,
            ).also { diagnosticBent = it } } finally { bufferWrite?.end(diagnosticBent) }
            if (bent) {
                target.rewind()
                tangentTarget.rewind()
                slot.hasBentBefore = true
                slot.lastBandScale = bandScale
                slot.useBufferAAsTarget = !slot.useBufferAAsTarget
                slot.bendPending = true
                val vertexCount = rawMesh.vertices.size
                val bufferPosted = mainHandler.post {
                    try {
                        if (bufferWrite == null) {
                            geometry.vertexBuffer.setBufferAt(engine, 0, target, 0, vertexCount * 3)
                            geometry.vertexBuffer.setBufferAt(engine, 1, tangentTarget, 0, vertexCount * 4)
                        } else {
                            bufferWrite.upload(geometry.vertexBuffer, engine, 0, target, vertexCount * 3)
                            bufferWrite.upload(geometry.vertexBuffer, engine, 1, tangentTarget, vertexCount * 4)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "applyTransform: fallo subiendo malla doblada a GPU", e)
                    } finally {
                        slot.bendPending = false
                        bufferWrite?.finish()
                    }
                }
                if (!bufferPosted) bufferWrite?.finish()
            }
        }

        // Push directo (sin mainHandler.post): evita añadir ~16ms de latencia
        // extra por esperar al próximo despacho del hilo principal. Los campos
        // de PoseInterpolator son @Volatile, así que writeInterpolatedPose (que
        // corre en el hilo principal vía Choreographer) ve el push más reciente
        // en el próximo vsync sin problemas de visibilidad de memoria.
        // Recuperación tras retención: sin las muestras de antes del hueco
        // (ver [PoseInterpolator.dropHistory]) y con el seguidor repartiendo
        // la corrección en vez de aplicarla de golpe. Si la retención ya
        // había vencido, [releaseSlot] reseteó todo y esto no cambia nada:
        // el seguidor arranca con `snapTo` al mostrarse.
        if (recovering) {
            slot.interpolator.dropHistory()
            slot.follower.softenRecovery(nowNanos)
        }
        val publication = if (com.example.test_face.PerfFlags.config.timestampTrace && traceContext != null)
            PredictorTimingTelemetry.Publication(traceContext) else null
        val trajectory = if (trajectoryCapture != null)
            PoseTrajectoryTelemetry.Processed(trajectoryCapture.id, traceContext, transform, smoothed,
                rawElapsedNs, euroElapsedNs, recovering) else null
        trajectory?.beforePush()
        slot.interpolator.push(smoothed, nowNanos, publication, trajectory)
        trajectory?.afterPush()
        publication?.complete()

        // PUERTA DE MOVIMIENTO (ver [MotionGate]): con la cara moviéndose
        // rápido, la pestaña no se dibuja. El push al interpolador y el
        // doblado de arriba SIGUEN corriendo mientras está oculta — así, al
        // volver a mostrarse, la pose y la forma ya son las del frame actual y
        // no hay que esperar a que converjan a la vista.
        val shouldShow = if (RendererConfiguration.MOTION_GATE_ENABLED) {
            slot.motionGate.update(smoothed, slot.naturalSpan, nowNanos)
        } else {
            true
        }
        if (shouldShow) showSlot(slot) else hideSlotWhileMoving(slot)
    }

    // ── Carga de modelos ──────────────────────────────────────────────────────

    private fun loadIntoSlot(
        slot: EyeModelSlot,
        path: String?,
        eye: String,
        /** Ver [loadEyeModels] / [RawMesh.mirroredAcrossX] — `true` solo
         * cuando `leftPath == rightPath` (mismo archivo para los dos ojos,
         * caso de los diseños del backend). */
        mirror: Boolean,
    ) {
        val sv = sceneView ?: run {
            // Si esto se ve en logcat, la carga se descarta silenciosamente:
            // confirma que el SceneView todavía no se había adjuntado en el
            // momento de la llamada. Con el fix de creationParams (ver
            // CameraPreviewFactory) esta rama no debería alcanzarse nunca en
            // el flujo normal, porque attachSceneView() siempre corre antes.
            Log.w(TAG, "loadIntoSlot[$eye] SceneView todavía no disponible — path=$path descartado")
            return
        }

        slot.node?.let { old ->
            Log.i(TAG, "loadIntoSlot[$eye] reemplazando node anterior=${System.identityHashCode(old)}")
            sv.removeChildNode(old)
            old.destroy()
        }
        slot.reset()

        if (path == null) return

        val scope = (activity as? LifecycleOwner)?.lifecycleScope ?: run {
            Log.w(TAG, "loadIntoSlot[$eye]: Activity no es LifecycleOwner")
            return
        }

        val engineAtLaunch = sv.engine
        scope.launch {
            try {
                // IMPORTANTE: se lee el archivo en el hilo principal y se usa el
                // overload de Buffer (no el de File) porque el Engine de Filament
                // exige que todas sus llamadas se hagan desde el mismo hilo que lo
                // creó — ver nota original conservada de CameraXManager.
                val bytes = File(path).readBytes()
                val buffer = ByteBuffer.allocateDirect(bytes.size).apply {
                    put(bytes)
                    rewind()
                }
                val modelInstance = sv.modelLoader.createModelInstance(buffer)

                val node = ModelNode(
                    modelInstance = modelInstance,
                    scaleToUnits = null,
                    autoAnimate = true,
                )
                // NO se llama node.centerOrigin(): con los argumentos por
                // defecto (origin=Float3(0,0,0)) esa llamada es un no-op
                // matemático (`position += origin*size` con origin=0), y aun
                // si no lo fuera, writeInterpolatedPose() sobreescribe
                // node.position COMPLETO en cada vsync — cualquier ajuste que
                // centerOrigin() hiciera acá se perdería en el primer frame
                // visible. Verificado decompilando sceneview-android v2.1.1
                // (bytecode + fuente real en GitHub). El alineado real de la
                // raíz de la pestaña ahora lo hace EyeTransformCalculator
                // usando slot.rootLocalY (ver abajo), no este método.

                // Reemplaza la geometría que cargó gltfio por una propia,
                // editable frame a frame (ver LashMeshBender): ni
                // FilamentAsset ni RenderableManager exponen una forma de
                // LEER los vértices que gltfio ya cargó, solo de
                // reemplazarlos vía setGeometry. Si el parseo falla o el
                // modelo no tiene RenderableNode, el modelo se sigue
                // mostrando rígido (sin doblado) — no bloquea la carga.
                try {
                    val parsedMesh = GlbMeshReader.read(path)
                    val mirroredMesh = if (mirror) parsedMesh.mirroredAcrossX() else parsedMesh
                    if (mirror) {
                        Log.i(TAG, "loadIntoSlot[$eye] mirroredAcrossX aplicado (mismo .glb en los dos ojos)")
                    }
                    // Ver RawMesh.withColorFloor / RendererConfiguration.LASH_COLOR_FLOOR
                    // — recorta el extremo casi-negro-puro del degradado de
                    // color raíz→punta del .glb, confirmado en dispositivo
                    // real como la causa de la línea dura en la base.
                    // El floor primero (recorta el extremo casi-negro-puro
                    // del degradado del artista, ver su KDoc) y recién después
                    // el pase a negro neutro, que normaliza contra el máximo
                    // resultante — así el negro sale del degradado YA
                    // corregido y no se reintroduce la línea dura en la raíz.
                    val rawMesh = mirroredMesh
                        .withColorFloor(RendererConfiguration.LASH_COLOR_FLOOR)
                        .toNeutralBlack(RendererConfiguration.LASH_BLACK_TIP_LUMINANCE)
                    val geometry = Geometry.Builder(RenderableManager.PrimitiveType.TRIANGLES)
                        .vertices(rawMesh.vertices)
                        .indices(rawMesh.indices)
                        .build(sv.engine)
                    val renderableNode = node.renderableNodes.firstOrNull()
                    if (renderableNode != null) {
                        renderableNode.setGeometry(geometry)
                        slot.rawMesh = rawMesh
                        slot.geometry = geometry
                        // Double-buffer de LashMeshBender.bendInPlace —
                        // FloatBuffer DIRECTO, se asigna UNA vez acá con el
                        // tamaño exacto de este mesh (vertexCount×3 floats) y
                        // se reutiliza en cada resultado de MediaPipe sin
                        // volver a alocar (ver EyeModelSlot). No hace falta
                        // pre-llenarlo con la malla cruda: el nodo sigue
                        // oculto (`node.isVisible = false`, más abajo) hasta
                        // el primer resultado con rostro detectado, que ya
                        // dispara un doblado real (o, si el doblado está
                        // desactivado, la Geometry ya subió la forma de
                        // reposo una vez arriba, en `Geometry.Builder`).
                        slot.positionBufferA = allocateDirectFloatBuffer(rawMesh.vertices.size * 3)
                        slot.positionBufferB = allocateDirectFloatBuffer(rawMesh.vertices.size * 3)
                        // Tangente de reposo — costo único acá (como parsear
                        // el .glb), NO por frame. Ver LashMeshBender.
                        // computeRestTangents / KDoc de la clase (dejar la
                        // normal estática se veía como una línea negra dura
                        // con el material brilloso de LashPBR).
                        slot.restTangents = LashMeshBender.computeRestTangents(rawMesh.vertices)
                        slot.tangentBuffer = allocateDirectFloatBuffer(rawMesh.vertices.size * 4)
                    } else {
                        Log.w(TAG, "loadIntoSlot[$eye]: sin RenderableNode — sin doblado de párpado")
                    }
                    // REACTIVADO (diagnóstico Problema 1, validación en dispositivo):
                    // con rootLocalY=0 el CENTRO geométrico del abanico (bounding box
                    // simétrica, minY=-maxY, confirmado parseando los .glb reales)
                    // quedaba anclado en la línea de pestañas — la mitad superior del
                    // abanico (las puntas) sobresalía ~28% del ancho del ojo por
                    // encima de la línea real (síntoma: pestaña a la altura de la
                    // ceja/cuenca). rawMesh.minY es la RAÍZ real del mesh (constante,
                    // calculada una sola vez al cargar — sin ruido por frame), así que
                    // usarla acá ancla la raíz, no el centro, en la línea de pestañas.
                    // El ruido que causó la desactivación anterior venía de multiplicar
                    // esto por eyePlane.up (por frame) en EyeTransformCalculator — eso
                    // no cambió, así que si reaparece temblor visible, es la misma causa
                    // de siempre y hay que atacarla ahí, no revertir esto a 0f.
                    slot.rootLocalY = rawMesh.minY
                } catch (e: Exception) {
                    Log.e(TAG, "loadIntoSlot[$eye]: fallo parseando geometría para doblado, sigue rígido", e)
                }

                // setGeometry no garantiza preservar el material instance
                // original del glTF — se reaplica DESPUÉS del swap para no
                // perder el material PBR/anisotrópico.
                MaterialManager.tune(node, sv)
                // Oculto hasta el primer frame con rostro detectado — evita
                // mostrar el modelo "congelado" en su posición por defecto.
                node.isVisible = false
                // El deduplicador de visibilidad arranca alineado con el
                // estado real del nodo — ver [showSlot].
                slot.visibleRequested = false

                val size = node.size
                // naturalSpan = ancho del modelo en X (la dimensión que se
                // escala para coincidir con el ancho real del ojo en el mundo).
                // NO se usa maxOf(x,y,z): si el modelo fuera más alto que ancho,
                // la escala calculada en EyeTransformCalculator sería incorrecta.
                slot.naturalSpan = size.x.takeIf { it > 0f } ?: 1f

                sv.addChildNode(node)
                slot.node = node
                slot.path = path

                Log.i(
                    TAG,
                    "loadIntoSlot[$eye] OK node=${System.identityHashCode(node)} " +
                        "engine=${System.identityHashCode(engineAtLaunch)} sceneView=${System.identityHashCode(sv)} " +
                        "naturalSpan=${slot.naturalSpan} path=$path",
                )
            } catch (e: Exception) {
                Log.e(TAG, "loadIntoSlot[$eye] ERROR cargando $path", e)
            }
        }
    }

    // ── Iluminación / calidad de render ──────────────────────────────────────

    /**
     * Luz ambiental sintética de estudio, construida por armónicos esféricos
     * (banda 0-2) — no requiere un archivo .hdr/.ktx nuevo. Predominantemente
     * neutra, algo más intensa desde arriba, para dar volumen especular a la
     * fibra de las pestañas sin dejar negro puro el lado no iluminado.
     */
    private fun configureEnvironment(sv: SceneView) {
        // Armónicos esféricos para iluminación de estudio cálida y suave.
        // Simula luz de ring light frontal — ideal para pestañas de belleza:
        // ilumina de frente con calidez sin crear sombras duras.
        val sphericalHarmonics = floatArrayOf(
            1.0f, 0.95f, 0.90f,   // L0 — base cálida (como luz de día interior)
            0.10f, 0.08f, 0.06f,  // L1(y) — luz extra desde arriba
            0.05f, 0.05f, 0.05f,  // L1(x) — leve relleno lateral
            0.08f, 0.07f, 0.06f,  // L1(z) — luz frontal extra (ring light)
            0f, 0f, 0f,           // L2 (neutros)
            0f, 0f, 0f,
            0f, 0f, 0f,
            0f, 0f, 0f,
            0f, 0f, 0f,
        )
        try {
            val indirectLight = IndirectLight.Builder()
                .irradiance(3, sphericalHarmonics)
                .intensity(RendererConfiguration.INDIRECT_LIGHT_INTENSITY)
                .build(sv.engine)
            sv.environment = sv.environmentLoader.createEnvironment(indirectLight = indirectLight)
        } catch (e: Exception) {
            Log.e(TAG, "No se pudo configurar el entorno de iluminación", e)
        }
    }

    /**
     * Solo MSAA (multisampling del render target), NO `ToneMapping`/`FXAA`/
     * `TAA` — esos son pases de post-procesado que operan sobre TODO el
     * framebuffer ya resuelto, incluidas las zonas sin geometría, y en un
     * [SceneView] translúcido (`isOpaque = false`, ver
     * [com.example.test_face.CameraPreviewFactory]) pueden forzar alpha=1
     * de fondo y tapar de negro el preview de la cámara — eso fue lo que
     * pasó cuando se activaron los tres juntos en una iteración anterior
     * (ver historial en ESTADO_ACTUAL.md). MSAA es distinto: multisamplea
     * color+alpha por sub-muestra ANTES de resolver a un solo píxel, así
     * que preserva la transparencia correctamente — necesario acá porque
     * las fibras de pestaña son geometría muy fina (1-2px de ancho) que se
     * ve como ruido/estática sin ningún anti-aliasing. Probado en
     * dispositivo real (Infinix X669, 2026-07-24): preview de cámara sigue
     * visible, sin pantalla negra. Si en algún dispositivo esto SÍ tapa la
     * cámara, revertir a no-op inmediatamente (no investigar a ciegas).
     */
    private fun configureRenderQuality(sv: SceneView) {
        try {
            sv.view.multiSampleAntiAliasingOptions = com.google.android.filament.View.MultiSampleAntiAliasingOptions().apply {
                enabled = true
                sampleCount = RendererConfiguration.MSAA_SAMPLE_COUNT
                customResolve = false
            }
        } catch (e: Exception) {
            Log.e(TAG, "No se pudo configurar MSAA — sigue sin anti-aliasing", e)
        }
    }

    /**
     * Reconfigura la luz direccional principal que ya crea [SceneView] por
     * defecto (no se crea una luz nueva): color/intensidad pensados para
     * generar un catchlight especular en la fibra de la pestaña (el material
     * depende de eso para "brillar" — ver plan). El relleno del lado no
     * iluminado lo aporta la luz ambiental de [configureEnvironment].
     */
    private fun configureKeyLight(sv: SceneView) {
        val key = sv.mainLightNode ?: run {
            Log.w(TAG, "configureKeyLight: SceneView no tiene mainLightNode")
            return
        }
        try {
            key.color = dev.romainguy.kotlin.math.Float4(RendererConfiguration.KEY_LIGHT_COLOR, 1f)
            key.intensity = RendererConfiguration.KEY_LIGHT_INTENSITY
            key.lightDirection = RendererConfiguration.KEY_LIGHT_DIRECTION
            key.isShadowCaster = false
        } catch (e: Exception) {
            Log.e(TAG, "No se pudo configurar la luz clave", e)
        }
    }

    /** Buffer directo (memoria nativa) preasignado para el double-buffer de
     * [LashMeshBender.bendInPlace] — ver [EyeModelSlot.positionBufferA]/
     * [positionBufferB]. Se llama solo en `loadIntoSlot` (una vez por
     * modelo cargado), no por frame. */
    private fun allocateDirectFloatBuffer(floatCount: Int): FloatBuffer =
        ByteBuffer.allocateDirect(floatCount * Float.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()

    private companion object {
        private const val TAG = "LashRenderer"

        /** Ver [latencyLogFrames]. */
        private const val LATENCY_LOG_EVERY_FRAMES = 120

        /** Ver [recordPoseJitter]: más de ~3 vsync sin escribir pose = hueco. */
        private const val JITTER_MAX_GAP_NANOS = 50_000_000L
    }
}
