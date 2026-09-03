package com.example.test_face.render

import android.os.Handler
import android.util.Log
import android.view.Choreographer
import com.google.android.filament.Engine
import com.google.android.filament.RenderableManager.PrimitiveType
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import io.github.sceneview.SceneView
import io.github.sceneview.geometries.Geometry
import io.github.sceneview.math.Color
import io.github.sceneview.node.GeometryNode
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Segundo efecto sobre la malla facial (Fase 4, ver el plan) — delineado.
 * Mismo esqueleto que [LashRenderer] a propósito DUPLICADO, no una base
 * compartida (decisión del plan: "duplicar, no tocar pestañas que ya
 * funcionan"). Vive en el MISMO [SceneView] que [LashRenderer]/
 * [FaceMeshRenderer], como un tercer nodo independiente — ninguno lee ni
 * escribe estado de los otros. No repite `configureEnvironment`/
 * `configureKeyLight`/MSAA: son ajustes de TODA la escena, ya los aplica
 * [LashRenderer.attachSceneView] sobre el mismo [SceneView].
 *
 * Ver [RendererConfiguration.ENABLE_EYELINER]: con el flag en `false`
 * (default actual) [attachSceneView]/[onFaceResult] retornan de inmediato —
 * mismo patrón que [FaceMeshRenderer.FACE_MESH_ENABLED] — así que este
 * renderer no crea nodo ni consume resultados de MediaPipe en absoluto.
 *
 * Sin `.glb` real todavía (ver plan): usa [LinerRibbonMesh] (procedural) en
 * vez de [GlbMeshReader]. Por eso el nodo es [GeometryNode] (construye la
 * [Geometry] directo desde un [RawMesh], sin pasar por `gltfio`) y NO
 * [io.github.sceneview.node.ModelNode] como en [LashRenderer]: `ModelNode`
 * necesita un `.glb` real para inicializar su `modelInstance` vía
 * `sv.modelLoader.createModelInstance(buffer)` — con un mesh 100% procedural
 * no hay ningún archivo que leer, así que ese paso no aplica. `GeometryNode`
 * expone el mismo `geometry.vertexBuffer` (con `setBufferAt` in-place) que
 * ya consume [LashMeshBender]/[LashRenderer.applyTransform], así que el
 * doblado se reutiliza sin cambios (ver plan, punto 2).
 *
 * Tampoco usa [MaterialManager] (ese archivo elige entre el material
 * anisotrópico y el PBR IMPORTADO DEL GLTF como fallback — acá no hay glTF
 * importado del que partir, por eso el material se arma directo con
 * `materialLoader.createColorInstance`, el mismo helper simple que ya usa
 * [FaceMeshRenderer] para su color de depuración).
 */
class LinerRenderer(private val mainHandler: Handler) {

    private var sceneView: SceneView? = null

    private val leftSlot = LinerModelSlot()
    private val rightSlot = LinerModelSlot()

    /** Estilo activo (ver [LashStyleConfig]) — mismo tipo que pestañas, ver
     * KDoc del plan sobre por qué no se crea un `LinerStyleConfig` aparte
     * todavía. */
    @Volatile private var currentStyleConfig: LashStyleConfig = LashStyleConfig.DEFAULT

    private var frameLoopRunning = false

    /** Ver [LashRenderer.measuredLatencyNanos] — mismo propósito, estado
     * propio porque este renderer tiene su propio [PoseInterpolator] por
     * slot, independiente del de pestañas. */
    @Volatile private var measuredLatencyNanos = 35_000_000L

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!frameLoopRunning) return
            writeInterpolatedPose(leftSlot, frameTimeNanos)
            writeInterpolatedPose(rightSlot, frameTimeNanos)
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    fun attachSceneView(view: SceneView) {
        if (!RendererConfiguration.ENABLE_EYELINER) return
        sceneView = view
        loadIntoSlot(view, leftSlot, "LEFT")
        loadIntoSlot(view, rightSlot, "RIGHT")
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

    private fun writeInterpolatedPose(slot: LinerModelSlot, nowNanos: Long) {
        val node = slot.node ?: return
        if (!node.isVisible) return
        val transform = slot.interpolator.sample(nowNanos, measuredLatencyNanos) ?: return
        node.position = transform.position
        node.quaternion = transform.rotation
        node.scale = transform.scale
    }

    fun detachSceneView(view: SceneView) {
        if (sceneView !== view) return
        stopFrameLoop()
        for (slot in listOf(leftSlot, rightSlot)) {
            slot.node?.let { old ->
                view.removeChildNode(old)
                old.destroy() // GeometryNode.destroy() ya libera su Geometry (VertexBuffer/IndexBuffer).
            }
            slot.reset()
        }
        sceneView = null
    }

    /** Ver [LashRenderer.setStyle]. */
    fun setStyle(styleId: String?) {
        currentStyleConfig = LashStyleConfig.forStyleId(styleId)
    }

    fun onFaceResult(result: FaceLandmarkerResult, imageWidth: Int, imageHeight: Int) {
        if (!RendererConfiguration.ENABLE_EYELINER) return
        if (leftSlot.node == null && rightSlot.node == null) return
        val sv = sceneView ?: return
        // Ver CameraProjection.coverScaleX / LashRenderer.onFaceResult.
        val camera = CameraProjection.fillCenter(
            projection = sv.cameraNode.projectionTransform,
            cameraToWorld = sv.cameraNode.modelTransform,
            imageWidth = imageWidth,
            imageHeight = imageHeight,
            viewportWidth = sv.width,
            viewportHeight = sv.height,
        )
        val pipelineResult = try {
            LinerRenderPipeline.compute(
                result = result,
                imageWidth = imageWidth,
                imageHeight = imageHeight,
                leftNaturalSpan = leftSlot.naturalSpan,
                rightNaturalSpan = rightSlot.naturalSpan,
                camera = camera,
                leftRootLocalY = leftSlot.rootLocalY,
                rightRootLocalY = rightSlot.rootLocalY,
                styleConfig = currentStyleConfig,
            )
        } catch (e: Exception) {
            Log.e(TAG, "onFaceResult: fallo calculando la transformación del delineado", e)
            null
        }
        if (pipelineResult == null) {
            onFaceLost()
            return
        }
        applyTransform(leftSlot, pipelineResult.left, sv.engine)
        applyTransform(rightSlot, pipelineResult.right, sv.engine)
    }

    fun onFaceLost() {
        hideSlot(leftSlot)
        hideSlot(rightSlot)
    }

    private fun hideSlot(slot: LinerModelSlot) {
        val node = slot.node
        slot.filter.reset()
        if (node != null) {
            mainHandler.post {
                slot.interpolator.reset()
                node.isVisible = false
            }
        }
    }

    /** Idéntico a [LashRenderer.applyTransform] (mismo buffer directo con
     * `setBufferAt` in-place, sin throttle por nanotime — ver ese archivo),
     * sin los logs de diagnóstico temporal que ya cumplieron su propósito
     * ahí. */
    private fun applyTransform(slot: LinerModelSlot, transform: EyeTransform?, engine: Engine) {
        val node = slot.node ?: return
        if (transform == null) {
            hideSlot(slot)
            return
        }
        val damping = opennessDamping(transform.opennessRatio)
        if (damping <= 0f) {
            hideSlot(slot)
            return
        }
        val smoothed = slot.filter.apply(transform)
        val damped = smoothed.copy(scale = smoothed.scale * damping)
        val nowNanos = System.nanoTime()

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

        slot.interpolator.push(damped, nowNanos)
        if (!node.isVisible) {
            mainHandler.post { node.isVisible = true }
        }
    }

    private fun opennessDamping(ratio: Float): Float {
        val closed = RendererConfiguration.EYE_CLOSED_OPENNESS_THRESHOLD
        val open = RendererConfiguration.EYE_OPEN_OPENNESS_THRESHOLD
        val t = ((ratio - closed) / (open - closed)).coerceIn(0f, 1f)
        return t * t * (3f - 2f * t)
    }

    private fun loadIntoSlot(sv: SceneView, slot: LinerModelSlot, eye: String) {
        slot.node?.let { old ->
            sv.removeChildNode(old)
            old.destroy()
        }
        slot.reset()
        try {
            val rawMesh = LinerRibbonMesh.build()
            val geometry = Geometry.Builder(PrimitiveType.TRIANGLES)
                .vertices(rawMesh.vertices)
                .indices(rawMesh.indices)
                .build(sv.engine)

            val material = sv.materialLoader.createColorInstance(
                color = Color(
                    RendererConfiguration.LINER_PLACEHOLDER_COLOR_R,
                    RendererConfiguration.LINER_PLACEHOLDER_COLOR_G,
                    RendererConfiguration.LINER_PLACEHOLDER_COLOR_B,
                    RendererConfiguration.LINER_PLACEHOLDER_COLOR_A,
                ),
                metallic = 0f,
                roughness = 1f,
                reflectance = 0.05f,
            ).apply { setDoubleSided(true) }

            val node = GeometryNode(
                engine = sv.engine,
                geometry = geometry,
                materialInstance = material,
            ).apply { isVisible = false }

            sv.addChildNode(node)

            slot.node = node
            slot.rawMesh = rawMesh
            slot.geometry = geometry
            // Double-buffer de POSICIONES + tangente de reposo, mismo patrón
            // que LashRenderer.loadIntoSlot — ver LinerModelSlot.positionBufferA/
            // positionBufferB/restTangents/tangentBuffer.
            slot.positionBufferA = allocateDirectFloatBuffer(rawMesh.vertices.size * 3)
            slot.positionBufferB = allocateDirectFloatBuffer(rawMesh.vertices.size * 3)
            slot.restTangents = LashMeshBender.computeRestTangents(rawMesh.vertices)
            slot.tangentBuffer = allocateDirectFloatBuffer(rawMesh.vertices.size * 4)
            slot.rootLocalY = 0f
            // naturalSpan directo de los bounds del RawMesh (no node.size):
            // como el mesh es procedural, ya conocemos su ancho local exacto
            // sin depender de una propiedad de Node que ModelNode expone
            // pero cuya presencia en GeometryNode no está confirmada.
            slot.naturalSpan = (rawMesh.maxX - rawMesh.minX).takeIf { it > 0f } ?: 1f

            Log.i(
                TAG,
                "loadIntoSlot[$eye] OK node=${System.identityHashCode(node)} naturalSpan=${slot.naturalSpan}",
            )
        } catch (e: Exception) {
            Log.e(TAG, "loadIntoSlot[$eye] ERROR construyendo el ribbon de delineado", e)
        }
    }

    /** Ver [LashRenderer.allocateDirectFloatBuffer] — misma implementación,
     * duplicada a propósito (ver KDoc de la clase). */
    private fun allocateDirectFloatBuffer(floatCount: Int): FloatBuffer =
        ByteBuffer.allocateDirect(floatCount * Float.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()

    private companion object {
        private const val TAG = "LinerRenderer"
    }
}
