package com.example.test_face.render

import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Float4
import dev.romainguy.kotlin.math.Mat4
import dev.romainguy.kotlin.math.cross
import dev.romainguy.kotlin.math.dot
import dev.romainguy.kotlin.math.normalize
import kotlin.math.sqrt

/**
 * Fase 2 del plan de migración a face-mesh: reemplaza el trabajo COMBINADO de
 * [EyePlaneCalculator] + [EyeTransformCalculator] (posición/rotación/escala)
 * derivándolo directamente de la posición de mundo REAL de 3 landmarks del
 * párpado (canto medial, canto lateral, ápice) — ya perspectiva-correcta
 * gracias a la malla facial de 468 puntos (ver [FaceMeshMath]/
 * [FaceMeshRenderer]), sin necesitar la pose de cabeza completa ni un residuo
 * angular 2D como aproximación.
 *
 * NO reemplaza a [EyeAnchorCalculator]: ese sigue siendo el ancla 2D en
 * píxeles que consumen [LashLineCurve]/[LashMeshBender] — este archivo solo
 * produce el mismo [EyeTransform] que [EyeTransformCalculator], por otra vía.
 *
 * Activado por [RendererConfiguration.LASH_ANCHOR_FROM_FACE_MESH] desde
 * [FaceRenderPipeline.computeEye] — con el flag en `false` (default), este
 * archivo no se llama nunca y [EyePlaneCalculator]/[EyeTransformCalculator]
 * siguen corriendo exactamente como antes.
 *
 * Asignaciones: 3 landmarks por ojo (6 por frame contando los dos ojos) —
 * mismo orden de magnitud que ya asigna hoy el sistema viejo (varios
 * `Float3`/`Quaternion`/`Mat4` por ojo por frame), así que este archivo usa
 * esos mismos tipos en vez de la aritmética escalarizada de
 * [FaceMeshRenderer] — esa restricción se justifica solo para 468
 * vértices/frame sin throttle, no para 3.
 */
object MeshEyeTransformCalculator {

    fun compute(
        landmarks: List<NormalizedLandmark>,
        medialIndex: Int,
        lateralIndex: Int,
        apexIndex: Int,
        camera: CameraProjection,
        headPose: HeadPose,
        naturalSpan: Float,
        rootLocalY: Float,
        styleConfig: LashStyleConfig,
    ): EyeTransform? {
        if (medialIndex >= landmarks.size || lateralIndex >= landmarks.size || apexIndex >= landmarks.size) {
            return null
        }

        val baseZ = headPose.position.z.coerceIn(
            RendererConfiguration.MIN_DEPTH,
            RendererConfiguration.MAX_DEPTH,
        )
        // Mismo "puente" world-units-por-unidad-normalizada que ya usa
        // EyeTransformCalculator para el ancho del ojo y FaceMeshRenderer para
        // los 468 vértices — un único cálculo por OJO (no por landmark).
        val worldUnitsPerNormalizedUnit = camera.worldDistanceAtDepth(-1f, 1f, 0f, baseZ)

        val medialWorld = FaceMeshMath.worldPositionOf(landmarks[medialIndex], camera, baseZ, worldUnitsPerNormalizedUnit)
        val lateralWorld = FaceMeshMath.worldPositionOf(landmarks[lateralIndex], camera, baseZ, worldUnitsPerNormalizedUnit)
        val apexWorld = FaceMeshMath.worldPositionOf(landmarks[apexIndex], camera, baseZ, worldUnitsPerNormalizedUnit)

        // Base ortonormal REAL del párpado — reemplaza a EyePlaneCalculator
        // (pose de cabeza + residuo angular 2D como aproximación). SIN
        // CONFIRMAR EN DISPOSITIVO: si la normal sale invertida (apunta hacia
        // adentro de la cara en vez de hacia la cámara), cambiar
        // `cross(right, chord2)` por `cross(chord2, right)` acá abajo — mismo
        // patrón de "confirmar signo en dispositivo" que
        // RendererConfiguration.FACE_MESH_DEPTH_Z_SIGN / EyePoseEstimator.
        val right = normalize(lateralWorld - medialWorld)
        val chord2 = apexWorld - medialWorld
        val normal = normalize(cross(right, chord2))
        val up = normalize(cross(normal, right))

        val eyeWidthWorld = worldDistance(medialWorld, lateralWorld)
        if (!eyeWidthWorld.isFinite() || eyeWidthWorld < 1e-4f) return null

        // Alto "real" del ojo = proyección del ápice sobre `up`, medido desde
        // la línea medial→lateral. A diferencia de EyeTransformCalculator, NO
        // hace falta tiltCorrection/HEAD_TILT_MULTIPLIER (corrección de
        // escorzo): eyeWidthWorld ya es la distancia física real entre dos
        // puntos 3D, correcta a cualquier ángulo de cabeza — esa corrección
        // solo hacía falta cuando el ancho se medía en píxeles 2D.
        val eyeHeightWorld = dot(chord2, up)

        val desiredWorldWidth = eyeWidthWorld * RendererConfiguration.WIDTH_MULTIPLIER
        val rawScale = if (naturalSpan > 0f) desiredWorldWidth / naturalSpan else 1f
        val scaleFactor = if (rawScale.isFinite() && rawScale > 0f) rawScale else 1f
        val scaleY = scaleFactor * RendererConfiguration.HEIGHT_VOLUME_MULTIPLIER

        // Punto base = centroide de los 3 landmarks (mismo peso que
        // EyeAnchorCalculator.meanX/meanY, ahora en 3D), desplazado hacia
        // arriba (a lo largo de `up`) según heightOffset — mismo criterio
        // artístico que el sistema viejo, aplicado en el eje real del ojo en
        // vez de en Y de imagen.
        //
        // A propósito NO se replican acá noseAvoidShift/lateralLashOffset:
        // eran parches para el error de aproximación del sistema 2D+headPose
        // (ver EyeAnchorCalculator). Con ancla 3D real, evaluar en dispositivo
        // si siguen haciendo falta antes de portarlos (ver plan Fase 2, §4).
        val centroid = (medialWorld + lateralWorld + apexWorld) / 3f
        val basePosition = centroid - up * (eyeHeightWorld * styleConfig.heightOffset)
        val rootCorrectedPosition = basePosition - up * (scaleY * rootLocalY)

        val rotationMatrix = Mat4(
            Float4(right, 0f),
            Float4(up, 0f),
            Float4(normal, 0f),
            Float4(0f, 0f, 0f, 1f),
        )

        return EyeTransform(
            position = rootCorrectedPosition,
            rotation = rotationMatrix.toQuaternion(),
            scale = Float3(scaleFactor, scaleY, scaleFactor),
        )
    }

    /** Distancia euclídea manual (no un helper de kotlin-math) — mismo patrón
     * exacto que [CameraProjection.worldDistanceAtDepth]. */
    private fun worldDistance(a: Float3, b: Float3): Float {
        val dx = b.x - a.x
        val dy = b.y - a.y
        val dz = b.z - a.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
}
