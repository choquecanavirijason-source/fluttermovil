package com.example.test_face.render

import android.os.Handler
import android.util.Log
import com.google.android.filament.IndexBuffer
import com.google.android.filament.MaterialInstance
import com.google.android.filament.RenderableManager.PrimitiveType
import com.google.android.filament.VertexBuffer
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import io.github.sceneview.SceneView
import io.github.sceneview.math.Color
import io.github.sceneview.node.MeshNode
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.ShortBuffer

/**
 * Fase 1 del plan de migración a face-mesh: construye la malla facial
 * completa de 468 vértices como geometría PROPIA de Filament (NO un `.glb`,
 * NO pasa por [io.github.sceneview.geometries.Geometry]) y actualiza sus
 * posiciones XYZ en cada resultado de MediaPipe.
 *
 * Completamente independiente de [LashRenderer]/[FaceRenderPipeline]: ambos
 * viven en el mismo [SceneView] (mismo `Engine`/`Scene`) como nodos
 * separados, pero ninguno lee ni escribe estado del otro — el pipeline de
 * pestañas actual (`.glb` rígido, 16 landmarks) sigue funcionando exactamente
 * igual que antes. La Fase 2 (no esta) es la que decide cómo anclar la
 * pestaña sobre ESTA malla en vez del `.glb`.
 *
 * Requisito duro de esta fase (viene de un OOM real ya sufrido con
 * [LashMeshBender] — ver `RendererConfiguration.LASH_BEND_MIN_INTERVAL_NANOS`):
 * CERO asignaciones de heap por frame proporcionales a los 468 vértices. Por
 * eso este archivo NO usa [io.github.sceneview.geometries.Geometry] ni su
 * `setVertices(engine, List<Vertex>)`: esa función SÍ asigna un
 * `FloatBuffer.allocate(...)` nuevo (heap de la JVM, no un buffer directo) Y
 * recalcula el bounding box completo en cada llamada (confirmado leyendo
 * `io.github.sceneview.geometries.Geometry.kt` de la versión 2.1.1 pineada en
 * este proyecto). Eso es aceptable para el doblado de pestañas porque está
 * limitado a ~4.5Hz por ojo (`LASH_BEND_MIN_INTERVAL_NANOS`); NO es aceptable
 * acá porque esta malla se actualiza en CADA resultado de MediaPipe (~30Hz,
 * sin throttle — la gracia de 468 puntos es capturar expresión en vivo, no
 * solo pose rígida de cabeza). En su lugar, este archivo usa
 * [VertexBuffer]/[IndexBuffer] crudos de Filament + [MeshNode] (el mismo
 * nivel que usa la propia librería por debajo de `Geometry`, ver
 * `MeshNode.kt`), con un `FloatBuffer` DIRECTO preasignado una única vez y
 * reescrito in-place (`put(index, value)`, absoluto, no mueve el cursor)
 * cada frame — nunca reasignado. La matemática por vértice tampoco usa
 * `Float3`/`Float4`/`Mat4` (esos tipos SÍ asignan un objeto nuevo por
 * llamada): los componentes de `cameraToWorld`/`projection` se leen una única
 * vez POR FRAME (no por vértice) a variables `Float` locales, y el resto es
 * aritmética escalar pura.
 */
class FaceMeshRenderer(private val mainHandler: Handler) {

    private var sceneView: SceneView? = null
    private var vertexBuffer: VertexBuffer? = null
    private var indexBuffer: IndexBuffer? = null
    private var materialInstance: MaterialInstance? = null
    private var node: MeshNode? = null

    /** Buffer NIO DIRECTO (memoria nativa, no heap de la JVM/ART) preasignado
     * una única vez en la vida de este objeto — sobrevive attach/detach de
     * [SceneView] (los datos no dependen del `Engine`, solo el [VertexBuffer]
     * de Filament que los consume, ese sí se reconstruye por attach). Se
     * reescribe con `put(index, value)` en cada [onFaceResult] — jamás
     * reasignado, ver requisito duro en el KDoc de la clase. */
    private val positionByteBuffer: ByteBuffer = ByteBuffer
        .allocateDirect(FaceMeshTopology.VERTEX_COUNT * POSITION_COMPONENTS * Float.SIZE_BYTES)
        .order(ByteOrder.nativeOrder())
    private val positionBuffer: FloatBuffer = positionByteBuffer.asFloatBuffer()

    /** `true` mientras hay un `setBufferAt` encolado en el hilo principal sin
     * ejecutar todavía — mismo propósito que [EyeModelSlot.bendPending]: sin
     * este guard, si el hilo principal va lento, cada resultado de MediaPipe
     * seguiría reescribiendo [positionBuffer] Y encolando `Runnable`s nuevos
     * más rápido de lo que se pueden consumir. Con el guard, un frame de
     * MediaPipe que llega mientras el anterior sigue pendiente simplemente se
     * descarta PARA ESTA MALLA (el tracking 2D que ya consume Flutter, y el
     * pipeline de pestañas, no se ven afectados — cada uno tiene su propio
     * guard/estado independiente). */
    @Volatile private var uploadPending = false

    fun attachSceneView(view: SceneView) {
        if (!RendererConfiguration.FACE_MESH_ENABLED) return
        sceneView = view
        try {
            val vb = VertexBuffer.Builder()
                .bufferCount(1)
                .vertexCount(FaceMeshTopology.VERTEX_COUNT)
                .attribute(
                    VertexBuffer.VertexAttribute.POSITION,
                    0,
                    VertexBuffer.AttributeType.FLOAT3,
                    0,
                    POSITION_COMPONENTS * Float.SIZE_BYTES,
                )
                .build(view.engine)

            val ib = IndexBuffer.Builder()
                .indexCount(FaceMeshTopology.TRIANGLE_INDICES_SHORT.size)
                .bufferType(IndexBuffer.Builder.IndexType.USHORT)
                .build(view.engine)
            val indexShortBuffer: ShortBuffer = ByteBuffer
                .allocateDirect(FaceMeshTopology.TRIANGLE_INDICES_SHORT.size * Short.SIZE_BYTES)
                .order(ByteOrder.nativeOrder())
                .asShortBuffer()
                .apply {
                    put(FaceMeshTopology.TRIANGLE_INDICES_SHORT)
                    rewind()
                }
            ib.setBuffer(view.engine, indexShortBuffer)

            val material = view.materialLoader.createColorInstance(
                color = Color(
                    RendererConfiguration.FACE_MESH_DEBUG_COLOR_R,
                    RendererConfiguration.FACE_MESH_DEBUG_COLOR_G,
                    RendererConfiguration.FACE_MESH_DEBUG_COLOR_B,
                    RendererConfiguration.FACE_MESH_DEBUG_COLOR_A,
                ),
                metallic = 0f,
                roughness = 1f,
                reflectance = 0f,
            ).apply { setDoubleSided(true) }

            val meshNode = MeshNode(
                engine = view.engine,
                primitiveType = PrimitiveType.TRIANGLES,
                vertexBuffer = vb,
                indexBuffer = ib,
                boundingBox = null, // sin AABB fija -> culling(false) (ver MeshNode.kt) — no hace falta
                // recalcularla por frame; a cambio, Filament nunca descarta este nodo por culling.
                materialInstance = material,
            ) {
                // CRASH FIX (2026-08-28): "AABB can't be empty, unless culling is disabled and the
                // object is not a shadow caster/receiver" — Panic nativo de Filament que abortaba el
                // proceso (SIGABRT) acá mismo, al construir este MeshNode. boundingBox=null SÍ dispara
                // culling(false) dentro de MeshNode (confirmado decompilando MeshNode.class de
                // sceneview-android 2.1.1), pero Filament exige AMBAS condiciones para tolerar un AABB
                // vacío: culling desactivado Y que el objeto no sea shadow caster/receiver. MeshNode
                // nunca toca esos flags, así que quedan en su default de Filament (true/true) — y el
                // AABB calculado del buffer de posiciones recién asignado (los 468 vértices en 0,0,0
                // hasta el primer onFaceResult) es degenerado/vacío. Esta malla es un overlay de debug
                // semitransparente (ver FACE_MESH_DEBUG_COLOR_A) — no necesita proyectar ni recibir
                // sombras, así que desactivarlas es correcto además de evitar el panic. `this` acá es
                // el RenderableManager.Builder (receiver implícito, ver firma real de MeshNode:
                // `builder: RenderableManager.Builder.() -> Unit`).
                castShadows(false)
                receiveShadows(false)
            }.apply { isVisible = false }

            view.addChildNode(meshNode)

            vertexBuffer = vb
            indexBuffer = ib
            materialInstance = material
            node = meshNode
            Log.i(TAG, "attachSceneView OK node=${System.identityHashCode(meshNode)}")
        } catch (e: Exception) {
            Log.e(TAG, "attachSceneView: fallo creando la malla facial", e)
        }
    }

    fun detachSceneView(view: SceneView) {
        if (sceneView !== view) return
        node?.let { n ->
            view.removeChildNode(n)
            n.destroy() // libera el entity/RenderableManager — NO el VertexBuffer/IndexBuffer, ver abajo.
        }
        try {
            vertexBuffer?.let { view.engine.destroyVertexBuffer(it) }
            indexBuffer?.let { view.engine.destroyIndexBuffer(it) }
        } catch (e: Exception) {
            Log.w(TAG, "detachSceneView: fallo liberando VertexBuffer/IndexBuffer", e)
        }
        node = null
        vertexBuffer = null
        indexBuffer = null
        materialInstance = null
        sceneView = null
    }

    /**
     * Punto de entrada por frame — mismo hilo llamante que
     * [LashRenderer.onFaceResult] (el de MediaPipe, ver `CameraXManager`).
     * Calcula las 468 posiciones de mundo con aritmética escalar pura (sin
     * `Float3`/`Float4`/`Mat4` por vértice, ver KDoc de la clase) y despacha
     * SOLO la subida a GPU al hilo principal, igual que
     * [LashRenderer.applyTransform].
     */
    fun onFaceResult(result: FaceLandmarkerResult) {
        if (!RendererConfiguration.FACE_MESH_ENABLED) return
        val vb = vertexBuffer ?: return
        val sv = sceneView ?: return
        if (uploadPending) return // backpressure — ver KDoc de uploadPending.

        val landmarks: List<NormalizedLandmark>? = result.faceLandmarks().getOrNull(0)
        if (landmarks == null || landmarks.size < FaceMeshTopology.VERTEX_COUNT) {
            onFaceLost()
            return
        }

        val matricesOptional = result.facialTransformationMatrixes()
        val headPose = if (matricesOptional.isPresent && matricesOptional.get().isNotEmpty()) {
            EyePoseEstimator.fromMediaPipeMatrix(matricesOptional.get()[0])
        } else {
            null
        } ?: EyePoseEstimator.fallback()

        val camera = CameraProjection(
            projection = sv.cameraNode.projectionTransform,
            cameraToWorld = sv.cameraNode.modelTransform,
        )

        val baseZ = headPose.position.z.coerceIn(
            RendererConfiguration.MIN_DEPTH,
            RendererConfiguration.MAX_DEPTH,
        )
        // Unidades de mundo por unidad normalizada de imagen a esta
        // profundidad — un único unproject "doble" por FRAME (no por
        // vértice), mismo patrón que EyeTransformCalculator para el ancho
        // del ojo (worldDistanceAtDepth).
        val worldUnitsPerNormalizedUnit = camera.worldDistanceAtDepth(-1f, 1f, 0f, baseZ)

        // Componentes escalares de cameraToWorld/proyección, leídos UNA vez
        // por frame (no por vértice): son solo lecturas de campos de un
        // Float4/Mat4 que YA existen (camera se calcula una vez por frame en
        // cualquier caso) — no asignan nada nuevo.
        val px = camera.projection.x.x
        val py = camera.projection.y.y
        val m = camera.cameraToWorld
        val c0x = m.x.x; val c0y = m.x.y; val c0z = m.x.z
        val c1x = m.y.x; val c1y = m.y.y; val c1z = m.y.z
        val c2x = m.z.x; val c2y = m.z.y; val c2z = m.z.z
        val c3x = m.w.x; val c3y = m.w.y; val c3z = m.w.z
        // SIN CONFIRMAR EN DISPOSITIVO — ver RendererConfiguration.FACE_MESH_DEPTH_Z_SIGN.
        val zSign = RendererConfiguration.FACE_MESH_DEPTH_Z_SIGN

        for (i in 0 until FaceMeshTopology.VERTEX_COUNT) {
            val lm = landmarks[i]
            val ndcX = 2f * lm.x() - 1f
            val ndcY = 1f - 2f * lm.y()
            val viewDepthZ = baseZ + zSign * lm.z() * worldUnitsPerNormalizedUnit

            val viewX = ndcX * (-viewDepthZ) / px
            val viewY = ndcY * (-viewDepthZ) / py

            val worldX = c0x * viewX + c1x * viewY + c2x * viewDepthZ + c3x
            val worldY = c0y * viewX + c1y * viewY + c2y * viewDepthZ + c3y
            val worldZ = c0z * viewX + c1z * viewY + c2z * viewDepthZ + c3z

            val base = i * POSITION_COMPONENTS
            positionBuffer.put(base, worldX)
            positionBuffer.put(base + 1, worldY)
            positionBuffer.put(base + 2, worldZ)
        }
        positionBuffer.rewind()

        uploadPending = true
        mainHandler.post {
            try {
                vb.setBufferAt(sv.engine, 0, positionBuffer, 0, FaceMeshTopology.VERTEX_COUNT * POSITION_COMPONENTS)
                node?.let { if (!it.isVisible) it.isVisible = true }
            } catch (e: Exception) {
                Log.e(TAG, "onFaceResult: fallo subiendo posiciones de la malla facial", e)
            } finally {
                uploadPending = false
            }
        }
    }

    /** Sin rostro detectado: oculta la malla — mismo criterio que
     * [LashRenderer.onFaceLost] (no dejarla "congelada" flotando). */
    fun onFaceLost() {
        val n = node ?: return
        mainHandler.post {
            if (n.isVisible) n.isVisible = false
        }
    }

    private companion object {
        private const val TAG = "FaceMeshRenderer"
        private const val POSITION_COMPONENTS = 3
    }
}
