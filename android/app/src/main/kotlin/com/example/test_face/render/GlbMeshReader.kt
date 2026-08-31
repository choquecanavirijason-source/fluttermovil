package com.example.test_face.render

import dev.romainguy.kotlin.math.Float2
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Float4
import io.github.sceneview.geometries.Geometry
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Malla original (vértices/índices) leída directamente del `.glb`, tal como
 * vino del artista, ANTES de cualquier doblado por [LashMeshBender].
 * [minX]/[maxX] son el rango local del eje X del mesh (extremo a extremo de
 * la pestaña) — necesarios para mapear cada vértice a un parámetro a lo
 * largo de la curva del párpado.
 *
 * [minY] es el punto más bajo del mesh en Y local — la RAÍZ real de la
 * pestaña (donde se apoya sobre el párpado), NO el origen local (0,0,0) del
 * `.glb`. Verificado con los 10 modelos de `assets/modelos/`: el bounding
 * box en Y es simétrico (`minY == -maxY`, el pivote SÍ está en el centro
 * geométrico), pero un histograma de densidad de vértices por banda de Y
 * muestra que la masa del mesh (la base ancha de donde nacen las fibras) se
 * concentra cerca de `minY`, no del centro — el origen local cae ya varias
 * unidades adentro del abanico de fibras. Anclar el origen (como hacía el
 * motor antes) en vez de `minY` empuja visualmente toda la pestaña hacia
 * arriba. Ver [EyeModelSlot.rootLocalY] / [EyeTransformCalculator] para
 * cómo se usa esto en el cálculo de posición final.
 */
data class RawMesh(
    val vertices: List<Geometry.Vertex>,
    val indices: List<Int>,
    val minX: Float,
    val maxX: Float,
    val minY: Float,
) {
    /**
     * Espeja la malla a lo largo del eje X local (`x → -x`). Usado por
     * [LashRenderer.loadIntoSlot] cuando el mismo archivo `.glb` se carga
     * para los dos ojos (diseños del backend, que solo guardan un modelo
     * por diseño — ver `eye_tracking_page.dart`): sin espejar uno de los
     * dos, el ala asimétrica del asset (pensada para un solo lado) queda
     * apuntando hacia el lado equivocado en ese ojo.
     *
     * No es solo `position.x = -x`:
     * - `normal.x` también se invierte, si no la iluminación queda
     *   especularmente incorrecta en el lado espejado.
     * - El winding de cada triángulo (`indices`, de a 3) se invierte
     *   (swap del 2do/3er índice) — espejar en un solo eje invierte el
     *   frente de cada cara; sin corregirlo, las normales de cara quedan
     *   mirando hacia adentro (se ve mal iluminado o el culling lo
     *   esconde).
     * - `minX`/`maxX` se recalculan (`-maxX`/`-minX` del original) para
     *   que el resto del pipeline (`LashMeshBender`, que depende de
     *   `raw.minX`/`raw.maxX`/`span`) opere sobre los datos ya espejados
     *   sin tener que saber que ocurrió un mirror.
     *
     * `minY` no cambia — el mirror es solo en X, la raíz de la pestaña
     * (ver [LashRenderer.loadIntoSlot] / `EyeTransformCalculator`) sigue
     * en el mismo lugar en Y.
     */
    fun mirroredAcrossX(): RawMesh {
        val mirroredVertices = vertices.map { vertex ->
            val p = vertex.position
            val n = vertex.normal
            vertex.copy(
                position = Float3(-p.x, p.y, p.z),
                normal = n?.let { Float3(-it.x, it.y, it.z) },
            )
        }
        val mirroredIndices = ArrayList<Int>(indices.size)
        var i = 0
        while (i + 2 < indices.size) {
            mirroredIndices.add(indices[i])
            mirroredIndices.add(indices[i + 2])
            mirroredIndices.add(indices[i + 1])
            i += 3
        }
        return copy(
            vertices = mirroredVertices,
            indices = mirroredIndices,
            minX = -maxX,
            maxX = -minX,
        )
    }

    /**
     * Sube el piso de color de cada vértice a [floor] por canal (RGB, no
     * alpha) — confirmado en dispositivo real: el `COLOR_0` del `.glb` trae
     * un degradado raíz→punta (raíz ≈0.03 casi negro puro, punta ≈0.14),
     * intencional del artista. Con la raíz ahora anclada exactamente en el
     * borde del párpado (ver `rootLocalY` en [LashRenderer.loadIntoSlot]),
     * la franja casi-negra-sólida del degradado (~65% de los vértices por
     * debajo de R=0.05) queda justo en la zona más visible y se lee como
     * una línea dura en vez de una sombra de raíz suave. Subir el piso NO
     * aplana el degradado a un solo tono: los vértices que ya estaban por
     * encima de [floor] quedan intactos, solo se recorta el extremo más
     * oscuro — conserva la forma del degradado, reduce el contraste del
     * extremo. Costo único al cargar el modelo, no por frame — no toca el
     * `.glb` en disco ni la geometría.
     */
    fun withColorFloor(floor: Float): RawMesh {
        val adjusted = vertices.map { vertex ->
            val c = vertex.color ?: return@map vertex
            vertex.copy(
                color = Float4(
                    c.x.coerceAtLeast(floor),
                    c.y.coerceAtLeast(floor),
                    c.z.coerceAtLeast(floor),
                    c.w,
                ),
            )
        }
        return copy(vertices = adjusted)
    }
}

/**
 * Parsea un `.glb` (glTF binario) directamente, sin pasar por el loader de
 * gltfio — necesario porque ni `FilamentAsset` ni `RenderableManager`
 * exponen una forma de LEER los vértices que gltfio ya cargó, solo de
 * reemplazarlos (ver [LashRenderer.loadIntoSlot]). Se hace una única vez al
 * cargar el modelo, no por frame.
 *
 * Solo soporta lo que realmente usan los assets de este proyecto (los 5
 * estilos en `assets/modelos/`, todos verificados: 1 mesh, 1 primitive, 1
 * nodo, atributos POSITION/NORMAL/TEXCOORD_0 + COLOR_0 opcional, todos
 * float sin comprimir) — no es un parser de glTF genérico.
 */
object GlbMeshReader {

    fun read(path: String): RawMesh {
        val bytes = File(path).readBytes()
        val header = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)

        val magic = String(bytes, 0, 4, Charsets.US_ASCII)
        require(magic == "glTF") { "No es un .glb válido (magic=$magic): $path" }

        var offset = 12 // tras el header de 12 bytes (magic + version + totalLength)
        var jsonChunk: String? = null
        var binChunk: ByteBuffer? = null
        while (offset + 8 <= bytes.size) {
            val chunkLength = header.getInt(offset)
            val chunkType = header.getInt(offset + 4)
            val dataStart = offset + 8
            when (chunkType) {
                CHUNK_TYPE_JSON -> jsonChunk = String(bytes, dataStart, chunkLength, Charsets.UTF_8)
                CHUNK_TYPE_BIN -> binChunk = ByteBuffer
                    .wrap(bytes, dataStart, chunkLength)
                    .slice()
                    .order(ByteOrder.LITTLE_ENDIAN)
            }
            offset = dataStart + chunkLength
        }

        val json = requireNotNull(jsonChunk) { "glb sin chunk JSON: $path" }
        val bin = requireNotNull(binChunk) { "glb sin chunk BIN: $path" }
        return parse(JSONObject(json), bin)
    }

    private fun parse(root: JSONObject, bin: ByteBuffer): RawMesh {
        val accessors = root.getJSONArray("accessors")
        val bufferViews = root.getJSONArray("bufferViews")
        val primitive = root.getJSONArray("meshes")
            .getJSONObject(0)
            .getJSONArray("primitives")
            .getJSONObject(0)
        val attributes = primitive.getJSONObject("attributes")

        val positions = readVec3(accessors, bufferViews, bin, attributes.getInt("POSITION"))
        val normals = readVec3(accessors, bufferViews, bin, attributes.optInt("NORMAL", -1))
        val uvs = readVec2(accessors, bufferViews, bin, attributes.optInt("TEXCOORD_0", -1))
        val colors = readColor(accessors, bufferViews, bin, attributes.optInt("COLOR_0", -1))
        val indices = readIndices(accessors, bufferViews, bin, primitive.getInt("indices"))

        val vertexCount = positions.size
        val vertices = ArrayList<Geometry.Vertex>(vertexCount)
        for (i in 0 until vertexCount) {
            vertices.add(
                Geometry.Vertex(
                    position = positions[i],
                    normal = normals.getOrElse(i) { DEFAULT_NORMAL },
                    uvCoordinate = uvs.getOrElse(i) { DEFAULT_UV },
                    color = colors.getOrElse(i) { DEFAULT_COLOR },
                ),
            )
        }

        val minX = positions.minOf { it.x }
        val maxX = positions.maxOf { it.x }
        val minY = positions.minOf { it.y }
        return RawMesh(vertices = vertices, indices = indices, minX = minX, maxX = maxX, minY = minY)
    }

    private fun readVec3(
        accessors: JSONArray,
        bufferViews: JSONArray,
        bin: ByteBuffer,
        accessorIndex: Int,
    ): List<Float3> {
        if (accessorIndex < 0) return emptyList()
        val accessor = accessors.getJSONObject(accessorIndex)
        val count = accessor.getInt("count")
        val floats = readFloats(accessor, bufferViews, bin, componentsPerElement = 3)
        return (0 until count).map { i -> Float3(floats[i * 3], floats[i * 3 + 1], floats[i * 3 + 2]) }
    }

    private fun readVec2(
        accessors: JSONArray,
        bufferViews: JSONArray,
        bin: ByteBuffer,
        accessorIndex: Int,
    ): List<Float2> {
        if (accessorIndex < 0) return emptyList()
        val accessor = accessors.getJSONObject(accessorIndex)
        val count = accessor.getInt("count")
        val floats = readFloats(accessor, bufferViews, bin, componentsPerElement = 2)
        return (0 until count).map { i -> Float2(floats[i * 2], floats[i * 2 + 1]) }
    }

    private fun readColor(
        accessors: JSONArray,
        bufferViews: JSONArray,
        bin: ByteBuffer,
        accessorIndex: Int,
    ): List<Float4> {
        if (accessorIndex < 0) return emptyList()
        val accessor = accessors.getJSONObject(accessorIndex)
        val count = accessor.getInt("count")
        val componentsPerElement = if (accessor.getString("type") == "VEC4") 4 else 3
        val floats = readFloats(accessor, bufferViews, bin, componentsPerElement)
        return (0 until count).map { i ->
            val base = i * componentsPerElement
            val alpha = if (componentsPerElement == 4) floats[base + 3] else 1f
            Float4(floats[base], floats[base + 1], floats[base + 2], alpha)
        }
    }

    private fun readIndices(
        accessors: JSONArray,
        bufferViews: JSONArray,
        bin: ByteBuffer,
        accessorIndex: Int,
    ): List<Int> {
        val accessor = accessors.getJSONObject(accessorIndex)
        val bufferView = bufferViews.getJSONObject(accessor.getInt("bufferView"))
        val count = accessor.getInt("count")
        val byteOffset = bufferView.optInt("byteOffset", 0) + accessor.optInt("byteOffset", 0)
        val result = ArrayList<Int>(count)
        when (accessor.getInt("componentType")) {
            COMPONENT_TYPE_UNSIGNED_BYTE ->
                for (i in 0 until count) result.add(bin.get(byteOffset + i).toInt() and 0xFF)
            COMPONENT_TYPE_UNSIGNED_SHORT ->
                for (i in 0 until count) result.add(bin.getShort(byteOffset + i * 2).toInt() and 0xFFFF)
            COMPONENT_TYPE_UNSIGNED_INT ->
                for (i in 0 until count) result.add(bin.getInt(byteOffset + i * 4))
            else -> error("componentType de índices no soportado: ${accessor.getInt("componentType")}")
        }
        return result
    }

    /** Lee `count` elementos de `componentsPerElement` floats cada uno,
     * respetando `byteStride` del bufferView si el atributo no viene
     * empaquetado de forma contigua (el glTF spec lo permite, aunque
     * ninguno de los assets verificados de este proyecto lo usa). */
    private fun readFloats(
        accessor: JSONObject,
        bufferViews: JSONArray,
        bin: ByteBuffer,
        componentsPerElement: Int,
    ): FloatArray {
        require(accessor.getInt("componentType") == COMPONENT_TYPE_FLOAT) {
            "Solo se soportan atributos FLOAT (componentType=${accessor.getInt("componentType")})"
        }
        val bufferView = bufferViews.getJSONObject(accessor.getInt("bufferView"))
        val count = accessor.getInt("count")
        val baseOffset = bufferView.optInt("byteOffset", 0) + accessor.optInt("byteOffset", 0)
        val elementByteSize = componentsPerElement * 4
        val stride = bufferView.optInt("byteStride", elementByteSize)

        val out = FloatArray(count * componentsPerElement)
        for (i in 0 until count) {
            val elementOffset = baseOffset + i * stride
            for (c in 0 until componentsPerElement) {
                out[i * componentsPerElement + c] = bin.getFloat(elementOffset + c * 4)
            }
        }
        return out
    }

    private val DEFAULT_NORMAL = Float3(0f, 1f, 0f)
    private val DEFAULT_UV = Float2(0f, 0f)
    private val DEFAULT_COLOR = Float4(1f, 1f, 1f, 1f)

    // Constantes del formato glTF 2.0 (spec, no inventadas).
    private const val CHUNK_TYPE_JSON = 0x4E4F534A
    private const val CHUNK_TYPE_BIN = 0x004E4942
    private const val COMPONENT_TYPE_UNSIGNED_BYTE = 5121
    private const val COMPONENT_TYPE_UNSIGNED_SHORT = 5123
    private const val COMPONENT_TYPE_UNSIGNED_INT = 5125
    private const val COMPONENT_TYPE_FLOAT = 5126
}
