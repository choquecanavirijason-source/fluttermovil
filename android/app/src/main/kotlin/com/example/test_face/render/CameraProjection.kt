package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Float4
import dev.romainguy.kotlin.math.Mat4
import kotlin.math.sqrt

/**
 * Snapshot mínimo de la cámara real de Filament necesario para des-proyectar
 * un punto de pantalla a una posición 3D verdadera a una profundidad
 * conocida. Se extrae una vez por frame desde `SceneView.cameraNode` (ver
 * [FaceRenderPipeline.compute]/[LashRenderer.onFaceResult]) para que
 * [EyeTransformCalculator] siga siendo matemática pura (`Mat4`/`Float3` de
 * kotlin-math), sin acoplarse directamente al tipo `Camera` de Filament.
 *
 * Reemplaza el mapeo lineal `(nx-0.5)*WORLD_SCALE_X` que existía antes: ese
 * mapeo era una proyección ortográfica encubierta, válida solo a la
 * distancia exacta a la que se calibraron las constantes — con esto, la
 * posición es correcta a cualquier distancia de cámara porque usa la
 * proyección de perspectiva real (ver auditoría, Hallazgo #1).
 */
data class CameraProjection(
    /** `camera.projectionTransform` — column-major, frustum simétrico (sin shift/lens offset). */
    val projection: Mat4,
    /** `camera.modelTransform` — transforma de espacio de cámara a espacio de mundo. */
    val cameraToWorld: Mat4,
) {
    /**
     * Des-proyecta un punto en coordenadas NDC (`[-1,1]`, convención OpenGL:
     * +Y hacia arriba) a la posición 3D real en espacio de mundo, a la
     * profundidad de vista [viewDepthZ] (unidades de mundo Filament, cámara
     * mirando hacia -Z — igual convención que `HeadPose.position.z`).
     *
     * Deriva `viewX`/`viewY` a partir de los términos diagonales de la
     * matriz de proyección en vez de invertir la matriz 4x4 completa: válido
     * exactamente cuando el frustum es simétrico (`setShift`/lens-shift no
     * usados), que es el caso de la cámara por defecto de `SceneView` en
     * este proyecto — `LashRenderer` nunca la reconfigura.
     */
    fun unproject(ndcX: Float, ndcY: Float, viewDepthZ: Float): Float3 {
        val px = projection.x.x
        val py = projection.y.y
        // clipW = -viewZ: convención de cámara mirando hacia -Z (OpenGL/Filament).
        val viewX = ndcX * (-viewDepthZ) / px
        val viewY = ndcY * (-viewDepthZ) / py
        val viewPoint = Float4(viewX, viewY, viewDepthZ, 1f)
        val worldPoint = cameraToWorld * viewPoint
        return Float3(worldPoint.x, worldPoint.y, worldPoint.z)
    }

    /**
     * Distancia real en espacio de mundo entre dos puntos de pantalla (NDC)
     * a la MISMA profundidad de vista — la forma físicamente correcta de
     * convertir un ancho en píxeles a un ancho en unidades de mundo,
     * respetando la perspectiva real (un mismo ancho en píxeles corresponde
     * a un ancho real mayor cuanto más lejos está el rostro de la cámara).
     */
    fun worldDistanceAtDepth(ndcX1: Float, ndcX2: Float, ndcY: Float, viewDepthZ: Float): Float {
        val a = unproject(ndcX1, ndcY, viewDepthZ)
        val b = unproject(ndcX2, ndcY, viewDepthZ)
        val dx = b.x - a.x
        val dy = b.y - a.y
        val dz = b.z - a.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
}
