package com.example.test_face.render

import android.media.Image
import android.os.Build
import android.os.Handler
import android.util.Log
import androidx.annotation.RequiresApi
import com.google.android.filament.Box
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.IndexBuffer
import com.google.android.filament.Material
import com.google.android.filament.MaterialInstance
import com.google.android.filament.RenderableManager
import com.google.android.filament.Scene
import com.google.android.filament.Stream
import com.google.android.filament.Texture
import com.google.android.filament.VertexBuffer
import io.github.sceneview.SceneView
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Fondo de cámara DENTRO de Filament, para el modo sincronizado
 * ([RendererConfiguration.FRAME_SYNC_MODE]).
 *
 * Por qué: con el `PreviewView` la cámara se ve EN VIVO y las pestañas
 * llegan ~50-100 ms después (esperan a MediaPipe): al mover la cabeza se
 * despegan, y había que predecir la pose hacia adelante para disimularlo.
 * Acá se dibuja, en el mismo render de Filament que las pestañas, el
 * fotograma de cámara (alta resolución, textura de GPU sin copias) que
 * corresponde al MISMO instante que analizó MediaPipe — imagen y pestaña
 * cambian juntas, como en TikTok/Instagram, y la pose no necesita predicción.
 *
 * El rectángulo se coloca con la MISMA [CameraProjection] que usan las
 * pestañas (`fillCenter` sobre la imagen de análisis): las esquinas de la
 * imagen se des-proyectan igual que los landmarks, así que imagen y pestañas
 * quedan alineadas por construcción, sin calibración aparte.
 *
 * Solo hilo principal (como el resto del render de Filament).
 */
@RequiresApi(Build.VERSION_CODES.Q)
class CameraBackground {

    private var engine: Engine? = null
    private var scene: Scene? = null
    private var entity = 0
    private var texture: Texture? = null
    private var stream: Stream? = null
    private var materialInstance: MaterialInstance? = null
    private var vertexBuffer: VertexBuffer? = null
    private var indexBuffer: IndexBuffer? = null
    private var inScene = false

    private val positions: FloatBuffer = floatBuffer(4 * 3)
    private val uvs: FloatBuffer = floatBuffer(4 * 2)

    /** Parámetros con los que se armó la geometría actual — se rearma solo
     * si cambian (encuadre, rotación del sensor, espejo, profundidad). */
    private var geometryKey: String? = null

    /** Si ya se mostró al menos un fotograma — hasta entonces el fondo no se
     * agrega a la escena (se vería negro). */
    var hasFrame = false
        private set

    fun attach(sceneView: SceneView) {
        if (engine != null) return
        try {
            val eng = sceneView.engine
            val tex = Texture.Builder()
                .sampler(Texture.Sampler.SAMPLER_EXTERNAL)
                .format(Texture.InternalFormat.RGB8)
                .build(eng)
            // Modo "acquired": se le entrega cada fotograma a mano
            // ([show]) en vez de que lea siempre el último de un
            // SurfaceTexture — es lo que permite elegir QUÉ fotograma se ve.
            val str = Stream.Builder().build(eng)
            tex.setExternalStream(eng, str)
            val mi = sceneView.materialLoader.createVideoInstance(tex, null)
            mi.setCullingMode(Material.CullingMode.NONE)

            val vb = VertexBuffer.Builder()
                .bufferCount(2)
                .vertexCount(4)
                .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 12)
                .attribute(VertexBuffer.VertexAttribute.UV0, 1, VertexBuffer.AttributeType.FLOAT2, 0, 8)
                .build(eng)
            val ib = IndexBuffer.Builder()
                .indexCount(6)
                .bufferType(IndexBuffer.Builder.IndexType.USHORT)
                .build(eng)
            val indices = ByteBuffer.allocateDirect(6 * 2).order(ByteOrder.nativeOrder())
            indices.asShortBuffer().put(shortArrayOf(0, 1, 2, 2, 1, 3))
            ib.setBuffer(eng, indices)

            val ent = EntityManager.get().create()
            RenderableManager.Builder(1)
                // Caja enorme: el rectángulo puede quedar lejos de la cámara
                // y no debe recortarse nunca por frustum culling.
                .boundingBox(Box(0f, 0f, 0f, 10_000f, 10_000f, 10_000f))
                .geometry(0, RenderableManager.PrimitiveType.TRIANGLES, vb, ib, 0, 6)
                .material(0, mi)
                .culling(false)
                .castShadows(false)
                .receiveShadows(false)
                .build(eng, ent)

            engine = eng
            scene = sceneView.scene
            entity = ent
            texture = tex
            stream = str
            materialInstance = mi
            vertexBuffer = vb
            indexBuffer = ib
            geometryKey = null
            hasFrame = false
            inScene = false
            Log.i(TAG, "attach: fondo de cámara creado")
        } catch (e: Throwable) {
            Log.e(TAG, "attach: no se pudo crear el fondo de cámara", e)
            detach()
        }
    }

    fun detach() {
        val eng = engine ?: return
        try {
            if (inScene) scene?.removeEntity(entity)
            if (entity != 0) {
                eng.destroyEntity(entity)
                EntityManager.get().destroy(entity)
            }
            materialInstance?.let { eng.destroyMaterialInstance(it) }
            vertexBuffer?.let { eng.destroyVertexBuffer(it) }
            indexBuffer?.let { eng.destroyIndexBuffer(it) }
            texture?.let { eng.destroyTexture(it) }
            stream?.let { eng.destroyStream(it) }
        } catch (e: Throwable) {
            Log.e(TAG, "detach: excepción liberando el fondo (ignorada)", e)
        }
        engine = null
        scene = null
        entity = 0
        texture = null
        stream = null
        materialInstance = null
        vertexBuffer = null
        indexBuffer = null
        inScene = false
        hasFrame = false
        geometryKey = null
    }

    /**
     * Muestra [image] (fotograma de la cámara, buffer de GPU) como fondo.
     * Cierra [image] cuando Filament termina de usarla. Devuelve `false` (y
     * la cierra) si no se pudo mostrar.
     *
     * [rotationDegrees]: giro horario que deja derecho el buffer del sensor
     * (el de `SurfaceRequest.TransformationInfo`). [mirror]: cámara frontal
     * (se ve como espejo, igual que el análisis y el `PreviewView`).
     * [viewDepthZ]: profundidad de vista a la que se coloca el rectángulo,
     * detrás de las pestañas.
     */
    fun show(
        image: Image,
        handler: Handler,
        rotationDegrees: Int,
        mirror: Boolean,
        camera: CameraProjection,
        viewDepthZ: Float,
    ): Boolean {
        val eng = engine
        val str = stream
        if (eng == null || str == null) {
            image.close()
            return false
        }
        val hardwareBuffer = try {
            image.hardwareBuffer
        } catch (e: Throwable) {
            null
        }
        if (hardwareBuffer == null) {
            image.close()
            return false
        }
        try {
            str.setAcquiredImage(hardwareBuffer, handler, Runnable {
                hardwareBuffer.close()
                image.close()
            })
        } catch (e: Throwable) {
            Log.e(TAG, "show: setAcquiredImage falló", e)
            hardwareBuffer.close()
            image.close()
            return false
        }
        updateGeometry(eng, rotationDegrees, mirror, camera, viewDepthZ)
        hasFrame = true
        setVisible(true)
        return true
    }

    /** Saca/vuelve a poner el fondo en la escena (fuera del modo
     * sincronizado tiene que desaparecer para que se vea el `PreviewView`). */
    fun setVisible(visible: Boolean) {
        val sc = scene ?: return
        if (visible && hasFrame && !inScene) {
            sc.addEntity(entity)
            inScene = true
        } else if (!visible && inScene) {
            sc.removeEntity(entity)
            inScene = false
        }
    }

    private fun updateGeometry(
        eng: Engine,
        rotationDegrees: Int,
        mirror: Boolean,
        camera: CameraProjection,
        viewDepthZ: Float,
    ) {
        val p = camera.projection
        val key = "$rotationDegrees|$mirror|${camera.coverScaleX}|${camera.coverScaleY}|" +
            "${p.x.x}|${p.y.y}|$viewDepthZ|${camera.cameraToWorld.position}"
        if (key == geometryKey) return
        geometryKey = key

        positions.clear()
        uvs.clear()
        // Esquinas en coordenadas NORMALIZADAS de la imagen de análisis
        // (origen arriba-izquierda, igual que los landmarks). Mismo
        // des-proyectado que EyeTransformCalculator: NDC = (2u-1, 1-2v).
        val corners = arrayOf(
            floatArrayOf(0f, 0f), floatArrayOf(1f, 0f),
            floatArrayOf(0f, 1f), floatArrayOf(1f, 1f),
        )
        for ((u, v) in corners.map { it[0] to it[1] }) {
            val world = camera.unproject(2f * u - 1f, 1f - 2f * v, viewDepthZ)
            positions.put(world.x).put(world.y).put(world.z)
            val (s, t) = sensorUv(u, v, rotationDegrees, mirror)
            uvs.put(if (RendererConfiguration.FRAME_SYNC_FLIP_U) 1f - s else s)
                .put(if (RendererConfiguration.FRAME_SYNC_FLIP_V) 1f - t else t)
        }
        positions.flip()
        uvs.flip()
        vertexBuffer?.setBufferAt(eng, 0, positions)
        vertexBuffer?.setBufferAt(eng, 1, uvs)
        Log.i(TAG, "geometría del fondo: rotación=$rotationDegrees espejo=$mirror profundidad=$viewDepthZ")
    }

    companion object {
        private const val TAG = "CameraBackground"

        private fun floatBuffer(count: Int): FloatBuffer =
            ByteBuffer.allocateDirect(count * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()

        /**
         * Punto (u, v) de la imagen DERECHA y espejada (la que analiza
         * MediaPipe y ve la clienta) → coordenada (s, t) en el buffer del
         * sensor, que llega sin girar ni espejar. Se deshace el espejo y
         * después el giro horario de [rotationDegrees].
         */
        fun sensorUv(u: Float, v: Float, rotationDegrees: Int, mirror: Boolean): Pair<Float, Float> {
            val x = if (mirror) 1f - u else u
            val y = v
            return when (((rotationDegrees % 360) + 360) % 360) {
                90 -> y to 1f - x
                180 -> 1f - x to 1f - y
                270 -> 1f - y to x
                else -> x to y
            }
        }
    }
}
