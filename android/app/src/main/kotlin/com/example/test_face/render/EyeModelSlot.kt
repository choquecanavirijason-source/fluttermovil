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

    /** [RawMesh.minY] — la raíz real de la pestaña en unidades locales del
     * `.glb` (mismo sistema de unidades que [naturalSpan], sin escalar).
     * `0f` mientras el mesh no haya terminado de parsear (degrada al
     * comportamiento anterior: ancla en el origen del modelo, no en la
     * raíz). [EyeTransformCalculator] usa esto para desplazar la posición
     * final de modo que la RAÍZ del modelo (no su origen/centro geométrico)
     * quede sobre el punto de anclaje del ojo — ver [GlbMeshReader] para la
     * evidencia de por qué el origen del `.glb` NO coincide con la raíz
     * visual. @Volatile porque se escribe desde el hilo de carga y se lee
     * desde el hilo llamante de [FaceRenderPipeline] (el de MediaPipe). */
    @Volatile var rootLocalY = 0f

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
        rootLocalY = 0f
        filter.reset()
        interpolator.reset()
        rawMesh = null
        geometry = null
    }
}
