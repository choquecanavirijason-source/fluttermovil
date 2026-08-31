package com.example.test_face.render

import io.github.sceneview.geometries.Geometry
import io.github.sceneview.node.GeometryNode
import java.nio.FloatBuffer

/**
 * Copia de [EyeModelSlot] para el delineado (ver plan Fase 4: "duplicar, no
 * tocar código de pestañas ya probado") — MISMOS campos y mismo propósito,
 * la única diferencia real es que [node] es [GeometryNode] en vez de
 * [io.github.sceneview.node.ModelNode], porque [LinerRenderer] no carga un
 * `.glb` (no hay `modelInstance` que crear vía `gltfio`), construye la
 * [Geometry] directo desde un [RawMesh] procedural (ver [LinerRibbonMesh]).
 * `EyeModelSlot.node` está tipado a `ModelNode?` específicamente, así que no
 * alcanza para este caso sin ensancharlo — y ensancharlo sería tocar el
 * archivo que [LashRenderer] ya usa en producción, exactamente lo que el
 * plan pidió evitar.
 */
class LinerModelSlot {
    var node: GeometryNode? = null

    /** Ver [EyeModelSlot.naturalSpan]. */
    var naturalSpan = 1f

    /** Ver [EyeModelSlot.rootLocalY]. Siempre `0f` para el ribbon
     * procedural (está centrado en su propio origen local por
     * construcción, ver [LinerRibbonMesh]). */
    @Volatile var rootLocalY = 0f

    val filter = EyeTrackingFilter()
    val interpolator = PoseInterpolator()

    /** Ver [EyeModelSlot.rawMesh]. */
    @Volatile var rawMesh: RawMesh? = null

    /** Ver [EyeModelSlot.geometry]. */
    @Volatile var geometry: Geometry? = null

    /** Ver [EyeModelSlot.bendPending]. */
    @Volatile var bendPending = false

    /** Ver [EyeModelSlot.positionBufferA]/[EyeModelSlot.positionBufferB]. */
    @Volatile var positionBufferA: FloatBuffer? = null
    @Volatile var positionBufferB: FloatBuffer? = null

    /** Ver [EyeModelSlot.restTangents]/[EyeModelSlot.tangentBuffer]. */
    @Volatile var restTangents: FloatArray? = null
    @Volatile var tangentBuffer: FloatBuffer? = null

    /** Ver [EyeModelSlot.useBufferAAsTarget]. */
    var useBufferAAsTarget = true

    /** Ver [EyeModelSlot.hasBentBefore]. */
    var hasBentBefore = false

    fun reset() {
        node = null
        naturalSpan = 1f
        rootLocalY = 0f
        filter.reset()
        interpolator.reset()
        rawMesh = null
        geometry = null
        bendPending = false
        positionBufferA = null
        positionBufferB = null
        restTangents = null
        tangentBuffer = null
        useBufferAAsTarget = true
        hasBentBefore = false
    }
}
