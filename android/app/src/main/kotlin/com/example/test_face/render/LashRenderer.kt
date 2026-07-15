package com.example.test_face.render

import android.app.Activity
import android.os.Handler
import android.util.Log
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import com.google.android.filament.IndirectLight
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import io.github.sceneview.SceneView
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
    fun onFaceResult(result: FaceLandmarkerResult, imageWidth: Int, imageHeight: Int) {
        if (leftSlot.node == null && rightSlot.node == null) {
            Log.v(TAG, "onFaceResult IGNORADO — leftNode=null rightNode=null (sin modelos cargados aún)")
            return
        }

        val sv = sceneView ?: run {
            Log.v(TAG, "onFaceResult IGNORADO — SceneView no adjuntado en este frame")
            return
        }
        // Cámara real del SceneView actual, extraída una vez por frame — ver
        // CameraProjection: reemplaza el mapeo lineal por des-proyección real
        // (Fase 1 del plan de motor).
        val camera = CameraProjection(
            projection = sv.cameraNode.projectionTransform,
            cameraToWorld = sv.cameraNode.modelTransform,
        )

        // Red de seguridad: cualquier excepción acá NO debe dejar las
        // pestañas ocultas para siempre — se loguea y se reintenta en el
        // próximo frame en vez de propagar el error hacia el listener
        // nativo de MediaPipe.
        val pipelineResult = try {
            FaceRenderPipeline.compute(
                result = result,
                imageWidth = imageWidth,
                imageHeight = imageHeight,
                leftNaturalSpan = leftSlot.naturalSpan,
                rightNaturalSpan = rightSlot.naturalSpan,
                camera = camera,
            )
        } catch (e: Exception) {
            Log.e(TAG, "onFaceResult: fallo calculando la transformación", e)
            null
        }
        if (pipelineResult == null) {
            onFaceLost()
            return
        }

        Log.v(
            TAG,
            "onFaceResult left=${System.identityHashCode(leftSlot.node)} right=${System.identityHashCode(rightSlot.node)} " +
                "leftTransform=${pipelineResult.left != null} rightTransform=${pipelineResult.right != null}",
        )
        applyTransform(leftSlot, pipelineResult.left)
        applyTransform(rightSlot, pipelineResult.right)
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
                if (node.isVisible) {
                    Log.i(TAG, "hideSlot node=${System.identityHashCode(node)} -> OCULTO (onFaceLost)")
                }
                node.isVisible = false
            }
        }
    }

    private fun applyTransform(slot: EyeModelSlot, transform: EyeTransform?) {
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
        mainHandler.post {
            if (!node.isVisible) {
                Log.i(TAG, "applyTransform node=${System.identityHashCode(node)} -> VISIBLE")
            }
            node.isVisible = true
            node.position = smoothed.position
            node.quaternion = smoothed.rotation
            node.scale = smoothed.scale * damping
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
        if (path == slot.path && slot.node != null) {
            Log.d(TAG, "loadIntoSlot[$eye] SKIP — ya cargado node=${System.identityHashCode(slot.node)} path=$path")
            return
        }

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
                node.centerOrigin()
                MaterialManager.tune(node, sv)
                // Oculto hasta el primer frame con rostro detectado — evita
                // mostrar el modelo "congelado" en su posición por defecto.
                node.isVisible = false

                val size = node.size
                slot.naturalSpan = maxOf(size.x, size.y, size.z).takeIf { it > 0f } ?: 1f

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
     * DESACTIVADO: `ToneMapping`/`AntiAliasing`/`sampleCount` son pases de
     * post-procesado que operan sobre TODO el framebuffer, incluidas las
     * zonas donde no hay geometría — en un [SceneView] translúcido
     * (`isOpaque = false`, ver [com.example.test_face.CameraPreviewFactory])
     * eso puede forzar alpha=1 en el fondo y tapar de negro el preview de la
     * cámara que va debajo. Se activaron en una iteración anterior y
     * causaron justo eso, así que quedan fuera hasta poder confirmarlas de
     * forma segura en dispositivo (por ejemplo, restringiendo el pase a la
     * región del `.glb` en vez de a toda la vista).
     */
    private fun configureRenderQuality(sv: SceneView) {
        // No-op a propósito — ver comentario de la función.
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
