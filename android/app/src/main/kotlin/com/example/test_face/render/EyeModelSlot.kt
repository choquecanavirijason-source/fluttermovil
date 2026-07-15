package com.example.test_face.render

import io.github.sceneview.node.ModelNode

/** Estado por ojo: nodo del `.glb` cargado, tamaño natural medido, y su filtro de suavizado propio. */
class EyeModelSlot {
    var node: ModelNode? = null
    var path: String? = null

    /** Mayor dimensión del modelo tal cual viene en el .glb (escala 1, sin normalizar). */
    var naturalSpan = 1f

    val filter = EyeTrackingFilter()

    fun reset() {
        node = null
        path = null
        naturalSpan = 1f
        filter.reset()
    }
}
