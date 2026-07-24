package com.example.test_face.render

import io.github.sceneview.geometries.Geometry
import io.github.sceneview.node.ModelNode

/** Estado por ojo: nodo del `.glb` cargado, tamaño natural medido, su filtro
 * de suavizado propio, su interpolador de pose (desacopla el framerate de
 * MediaPipe del refresco de pantalla, ver [PoseInterpolator]) y la malla
 * propia usada para el doblado del párpado (ver [LashMeshBender],
 * [LashRenderer.loadIntoSlot]). */
class EyeModelSlot {
    var node: ModelNode? = null
    var path: String? = null

    /** Dimensión X del modelo (ancho) tal cual viene en el .glb — la escala
     * del mundo se calcula para que esta dimensión coincida con el ancho real
     * del ojo, así las pestañas siempre se ajustan al ojo real. */
    var naturalSpan = 1f

    /** Altura del modelo en unidades de mundo, DESPUÉS de escalar. Se
     * calcula en loadIntoSlot y lo usa writeInterpolatedPose para subir el
     * modelo media-altura: así el BORDE INFERIOR del modelo (la raíz de las
     * pestañas) queda en el punto de anclaje, no el centro geométrico.
     * @Volatile porque se escribe desde el hilo de carga y se lee desde el
     * hilo principal (Choreographer). */
    @Volatile var modelYRatio = 0f  // = naturalSizeY / naturalSizeX (relación de aspecto Y/X)

    val filter = EyeTrackingFilter()
    val interpolator = PoseInterpolator()

    /** Malla original sin doblar, parseada del .glb (ver [GlbMeshReader]) —
     * `null` si el parseo falló o el modelo no tiene un `RenderableNode`. */
    var rawMesh: RawMesh? = null

    /** Geometry propia activa en el nodo (reemplaza la que carga gltfio por
     * defecto), actualizada en cada resultado de MediaPipe vía
     * [LashMeshBender]. */
    var geometry: Geometry? = null

    fun reset() {
        node = null
        path = null
        naturalSpan = 1f
        modelYRatio = 0f
        filter.reset()
        interpolator.reset()
        rawMesh = null
        geometry = null
    }
}
