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
import io.github.sceneview.SceneView
import io.github.sceneview.geometries.Geometry
import io.github.sceneview.node.ModelNode
import kotlinx.coroutines.launch
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

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
                writeInterpolatedPose(leftSlot, frameTimeNanos)
                writeInterpolatedPose(rightSlot, frameTimeNanos)
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

    private fun startFrameLoop() {
        if (frameLoopRunning) return
        frameLoopRunning = true
        mainHandler.post { Choreographer.getInstance().postFrameCallback(frameCallback) }
    }

    private fun stopFrameLoop() {
        frameLoopRunning = false
    }

    /** Escribe en [slot.node] la pose extrapolada a [nowNanos] (ver
     * [PoseInterpolator]) — no-op si el nodo no existe o está oculto (ojo
     * cerrado/rostro perdido, ver [hideSlot]). */
    private fun writeInterpolatedPose(slot: EyeModelSlot, nowNanos: Long) {
        val node = slot.node ?: return
        if (!node.isVisible) return
        val transform = slot.interpolator.sample(nowNanos, measuredLatencyNanos) ?: return
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
            if (!loggedNonFinitePose) {
                loggedNonFinitePose = true
                Log.w(TAG, "writeInterpolatedPose: pose no finita descartada pos=$p quat=$q scale=$sc")
            }
            return
        }
        node.position = p
        node.quaternion = q
        node.scale = sc
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
    ) {
        if (leftSlot.node == null && rightSlot.node == null) return

        // Actualizar la latencia medida para que writeInterpolatedPose la use
        // en el próximo vsync. +16ms para compensar la composición de
        // SurfaceFlinger (2 superficies separadas: PreviewView + SceneView).
        measuredLatencyNanos = ((pipelineLatencyMs + 16f) * 1_000_000f).toLong()

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
            )
        } catch (e: Exception) {
            Log.e(TAG, "onFaceResult: fallo calculando la transformación", e)
            null
        }
        if (pipelineResult == null) {
            onFaceLost()
            return
        }

        applyTransform(leftSlot, pipelineResult.left, sv.engine)
        applyTransform(rightSlot, pipelineResult.right, sv.engine)
    }

    /**
     * Sin rostro detectado: oculta las pestañas (en vez de dejarlas
     * "congeladas" flotando en la última posición conocida) y resetea el
     * suavizado para que, cuando el rostro reaparezca, el modelo aparezca
     * directamente en su posición correcta en vez de deslizarse desde la
     * última posición previa a la pérdida de tracking.
     */
    fun onFaceLost() {
        hideSlot(leftSlot)
        hideSlot(rightSlot)
    }

    private fun hideSlot(slot: EyeModelSlot) {
        val node = slot.node
        slot.filter.reset()
        if (node != null) {
            mainHandler.post {
                // El interpolador se resetea acá (hilo principal, mismo hilo
                // que lo lee en writeInterpolatedPose vía el frame loop) para
                // que no queden muestras viejas esperando a extrapolarse
                // cuando el rostro reaparezca.
                slot.interpolator.reset()
                // Mismo motivo que el interpolador: sin esto, al redetectar
                // el rostro la curva del párpado arrancaría mezclada con la
                // forma de hace varios segundos (ver UpperLidFilter).
                slot.lidFilter.reset()
                slot.openness.reset()
                if (node.isVisible) {
                    Log.i(TAG, "hideSlot node=${System.identityHashCode(node)} -> OCULTO (onFaceLost)")
                }
                node.isVisible = false
            }
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
    private fun applyTransform(slot: EyeModelSlot, transform: EyeTransform?, engine: Engine) {
        val node = slot.node ?: return
        if (transform == null) {
            hideSlot(slot)
            return
        }
        // Atenuación de parpadeo ANTES del suavizado temporal: se calcula
        // sobre la apertura cruda del frame (no la filtrada) porque cerrar
        // el ojo debe reflejarse rápido, no arrastrar el lag del One Euro
        // Filter de posición/rotación/escala (ver auditoría, oclusión de
        // parpadeo). damping<=0 -> ojo cerrado, oculta sin escribir escala 0
        // (evita un frame con la malla aplastada a tamaño cero visible).
        // Umbral relativo al ojo de ESTA persona (ver OpennessTracker) en vez
        // de las constantes absolutas, que confundían un ojo rasgado abierto
        // con un ojo cerrado.
        val damping = slot.openness.damping(transform.opennessRatio)
        if (damping <= 0f) {
            hideSlot(slot)
            return
        }
        val smoothed = slot.filter.apply(transform)
        // Damping ya horneado en la escala ANTES de entrar al interpolador:
        // así el interpolador solo necesita conocer "la escala final a
        // renderizar", sin bookkeeping aparte, y de paso el parpadeo también
        // queda suavemente extrapolado frame a frame en vez de dar un salto
        // discreto exactamente en el instante de cada resultado de MediaPipe.
        val damped = smoothed.copy(scale = smoothed.scale * damping)
        val nowNanos = System.nanoTime()

        // REESCRITO a buffer directo con setBufferAt in-place (ver
        // LashMeshBender/EyeModelSlot) — cero Geometry.Vertex/Float3 nuevos
        // por vértice, así que ya no hace falta el throttle de
        // LASH_BEND_MIN_INTERVAL_NANOS (existía para acotar la TASA de esas
        // asignaciones, no la tasa de recálculo en sí): se recalcula en
        // CADA resultado de MediaPipe, igual que la malla facial de 468
        // puntos. bendPending sigue como única red de seguridad si el hilo
        // principal se atrasa.
        val curve = transform.lashLineCurve
        val rawMesh = slot.rawMesh
        val geometry = slot.geometry
        val target = if (slot.useBufferAAsTarget) slot.positionBufferA else slot.positionBufferB
        val prior = if (slot.useBufferAAsTarget) slot.positionBufferB else slot.positionBufferA
        val restTangents = slot.restTangents
        val tangentTarget = slot.tangentBuffer
        if (curve != null && rawMesh != null && geometry != null && target != null &&
            restTangents != null && tangentTarget != null && !slot.bendPending
        ) {
            val bent = LashMeshBender.bendInPlace(
                raw = rawMesh,
                target = target,
                previous = if (slot.hasBentBefore) prior else null,
                restTangents = restTangents,
                tangentTarget = tangentTarget,
                smoothing = RendererConfiguration.LASH_BEND_SMOOTHING,
                curve = curve,
                styleConfig = currentStyleConfig,
                eyeWidthPx = transform.eyeWidthPx,
            )
            if (bent) {
                target.rewind()
                tangentTarget.rewind()
                slot.hasBentBefore = true
                slot.useBufferAAsTarget = !slot.useBufferAAsTarget
                slot.bendPending = true
                val vertexCount = rawMesh.vertices.size
                mainHandler.post {
                    try {
                        geometry.vertexBuffer.setBufferAt(engine, 0, target, 0, vertexCount * 3)
                        geometry.vertexBuffer.setBufferAt(engine, 1, tangentTarget, 0, vertexCount * 4)
                    } catch (e: Exception) {
                        Log.e(TAG, "applyTransform: fallo subiendo malla doblada a GPU", e)
                    } finally {
                        slot.bendPending = false
                    }
                }
            }
        }

        // Push directo (sin mainHandler.post): evita añadir ~16ms de latencia
        // extra por esperar al próximo despacho del hilo principal. Los campos
        // de PoseInterpolator son @Volatile, así que writeInterpolatedPose (que
        // corre en el hilo principal vía Choreographer) ve el push más reciente
        // en el próximo vsync sin problemas de visibilidad de memoria.
        slot.interpolator.push(damped, nowNanos)
        if (!node.isVisible) {
            mainHandler.post {
                Log.i(TAG, "applyTransform node=${System.identityHashCode(node)} -> VISIBLE")
                node.isVisible = true
            }
        }
    }

    /** Smoothstep entre `EYE_CLOSED_OPENNESS_THRESHOLD` (0) y `EYE_OPEN_OPENNESS_THRESHOLD` (1). */
    private fun opennessDamping(ratio: Float): Float {
        val closed = RendererConfiguration.EYE_CLOSED_OPENNESS_THRESHOLD
        val open = RendererConfiguration.EYE_OPEN_OPENNESS_THRESHOLD
        val t = ((ratio - closed) / (open - closed)).coerceIn(0f, 1f)
        return t * t * (3f - 2f * t)
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
    }
}
