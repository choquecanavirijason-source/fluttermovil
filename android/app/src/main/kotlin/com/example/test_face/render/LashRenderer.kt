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
    @Volatile private var measuredLatencyNanos = 35_000_000L  // seed: 35ms

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!frameLoopRunning) return
            writeInterpolatedPose(leftSlot, frameTimeNanos)
            writeInterpolatedPose(rightSlot, frameTimeNanos)
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

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
        node.position = transform.position
        node.quaternion = transform.rotation
        node.scale = transform.scale
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
        Log.i(
            TAG,
            "loadEyeModels renderer=${System.identityHashCode(this)} " +
                "sceneView=${sceneView?.let { System.identityHashCode(it) }} left=$leftPath right=$rightPath",
        )
        loadIntoSlot(leftSlot, leftPath, "LEFT")
        loadIntoSlot(rightSlot, rightPath, "RIGHT")
    }

    /**
     * Punto de entrada por frame: recibe el resultado crudo de MediaPipe
     * (para la pose 3D completa vía [FaceRenderPipeline]) y lo traduce en la
     * transformación final de cada nodo, suavizada por el filtro propio de
     * su [EyeModelSlot]. El cálculo pesado corre en el hilo llamante (el de
     * MediaPipe); solo la escritura final de la transformación en el nodo se
     * despacha al hilo principal, igual que antes, por rendimiento.
     */
    fun onFaceResult(result: FaceLandmarkerResult, imageWidth: Int, imageHeight: Int, pipelineLatencyMs: Float = 35f) {
        if (leftSlot.node == null && rightSlot.node == null) return

        // Actualizar la latencia medida para que writeInterpolatedPose la use
        // en el próximo vsync. +16ms para compensar la composición de
        // SurfaceFlinger (2 superficies separadas: PreviewView + SceneView).
        measuredLatencyNanos = ((pipelineLatencyMs + 16f) * 1_000_000f).toLong()

        val sv = sceneView ?: return
        val camera = CameraProjection(
            projection = sv.cameraNode.projectionTransform,
            cameraToWorld = sv.cameraNode.modelTransform,
        )

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
        val damping = opennessDamping(transform.opennessRatio)
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

        // DESACTIVADO: LashMeshBender.bend() reconstruye una List<Geometry.
        // Vertex> completa (17k-85k objetos según el diseño) y
        // geometry.setVertices() la vuelve a subir a GPU en CADA resultado
        // de MediaPipe. En dispositivo esto no fue "lento" — tumbó el
        // proceso: GC bloqueando 600-850ms seguidos, heap al tope de
        // 192MB, terminando en OutOfMemoryError real (ver logcat del
        // crash). El engine sigue en `engine` (parámetro) y `slot.geometry`
        // sigue existiendo con la malla ORIGINAL sin doblar (asignada una
        // única vez al cargar, en loadIntoSlot — esa parte es barata,
        // ocurre una vez, no en cada frame) — el modelo se sigue viendo
        // rígido, como antes de esta ronda, pero sin crashear. Reactivar
        // esto necesita un rediseño que no reasigne buffers por vértice
        // cada frame (p. ej. ByteBuffer directo reusado + throttling real),
        // no una versión "más lenta" de lo mismo. `engine` queda sin usar
        // acá a propósito, mientras el doblado está desactivado.

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

    private fun loadIntoSlot(slot: EyeModelSlot, path: String?, eye: String) {
       

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
                    val rawMesh = GlbMeshReader.read(path)
                    val geometry = Geometry.Builder(RenderableManager.PrimitiveType.TRIANGLES)
                        .vertices(rawMesh.vertices)
                        .indices(rawMesh.indices)
                        .build(sv.engine)
                    val renderableNode = node.renderableNodes.firstOrNull()
                    if (renderableNode != null) {
                        renderableNode.setGeometry(geometry)
                        slot.rawMesh = rawMesh
                        slot.geometry = geometry
                    } else {
                        Log.w(TAG, "loadIntoSlot[$eye]: sin RenderableNode — sin doblado de párpado")
                    }
                    // Raíz real de la pestaña (ver GlbMeshReader/EyeModelSlot):
                    // el bounding box del .glb está centrado en Y, pero la
                    // masa del mesh (banda densa de donde nacen las fibras)
                    // está cerca de minY, no del origen — anclar el origen
                    // (como se hacía antes) empuja la pestaña hacia arriba.
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
        val sphericalHarmonics = floatArrayOf(
            0.9f, 0.9f, 0.92f, // L0 — término constante (color base)
            0.05f, 0.08f, 0.05f, // L1(y) — algo más de luz desde arriba
            0.02f, 0.02f, 0.02f, // L1(x)
            0f, 0f, 0f, // L1(z)
            0f, 0f, 0f, // L2 (5 bandas restantes, neutras)
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

    private companion object {
        private const val TAG = "LashRenderer"
    }
}
