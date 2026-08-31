package com.example.test_face.render

import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import dev.romainguy.kotlin.math.Float3

/**
 * Fórmula compartida "landmark normalizado de MediaPipe → posición de mundo
 * de Filament" — la MISMA matemática que [FaceMeshRenderer.onFaceResult] usa
 * escalarizada (sin `Float3`, por los 468 vértices/frame sin throttle, ver el
 * KDoc de esa clase), expuesta acá en su forma `Float3` normal para los pocos
 * puntos por frame que necesita [MeshEyeTransformCalculator] (3 landmarks × 2
 * ojos = 6/frame — el mismo orden de magnitud que ya asignan hoy
 * `EyeAnchorCalculator`/`EyePlaneCalculator`/`EyeTransformCalculator` sin
 * problema, no hace falta escalarizar esto también).
 */
object FaceMeshMath {

    /**
     * [baseZ] y [worldUnitsPerNormalizedUnit] se calculan UNA vez por ojo (no
     * por landmark) — ver `camera.worldDistanceAtDepth` en
     * [MeshEyeTransformCalculator]/[FaceMeshRenderer]. Usa
     * [RendererConfiguration.FACE_MESH_DEPTH_Z_SIGN] — el MISMO signo que ya
     * usa la malla de 468 puntos, así que si se confirma/invierte ese signo
     * en dispositivo, este cálculo hereda la corrección automáticamente (son
     * los mismos landmarks, misma convención de profundidad).
     */
    fun worldPositionOf(
        landmark: NormalizedLandmark,
        camera: CameraProjection,
        baseZ: Float,
        worldUnitsPerNormalizedUnit: Float,
    ): Float3 {
        val ndcX = 2f * landmark.x() - 1f
        val ndcY = 1f - 2f * landmark.y()
        val viewDepthZ = baseZ + RendererConfiguration.FACE_MESH_DEPTH_Z_SIGN *
            landmark.z() * worldUnitsPerNormalizedUnit
        return camera.unproject(ndcX, ndcY, viewDepthZ)
    }
}
