package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import kotlin.math.abs

/** Transformación final (posición, rotación, escala) lista para aplicar a un `ModelNode`. */
data class EyeTransform(
    val position: Float3,
    val rotation: Quaternion,
    val scale: Float3,
    /** [EyeLandmarks.opennessRatio] del frame — 1f por defecto (abierto) si
     * el llamador no lo asigna. Lo usa [LashRenderer] para atenuar la escala
     * al parpadear en vez de dejar que la geometría casi cerrada lo haga de
     * forma implícita. */
    val opennessRatio: Float = 1f,
)

/**
 * Combina el ancla 2D del ojo ([EyeAnchor]), su plano/orientación local
 * ([EyePlane]) y la pose de cabeza ([HeadPose]) en la transformación 3D
 * final del modelo de pestañas: profundidad dinámica, rotación completa por
 * plano/normal, y escala corregida por escorzo cuando la cabeza gira.
 *
 * X/Y/escala se derivan de la [CameraProjection] real de Filament (ver
 * Fase 1 del plan de motor) — NO de un mapeo lineal con constantes de
 * calibración. Esto reemplaza el intento anterior con
 * `WORLD_SCALE_X`/`WORLD_SCALE_Y`, que era una proyección ortográfica
 * encubierta válida solo a la distancia exacta en la que se calibraron esas
 * constantes (ver auditoría, Hallazgo #1): al moverse la cara hacia/desde la
 * cámara, esa aproximación se desalineaba porque nunca dependía de la
 * profundidad real. Con des-proyección real, la posición y el ancho medido
 * en mundo son correctos a cualquier distancia, sin ninguna constante de
 * "escala de mundo" que recalibrar.
 */
object EyeTransformCalculator {

    fun compute(
        headPose: HeadPose,
        eyePlane: EyePlane,
        anchor: EyeAnchor,
        imageWidth: Float,
        imageHeight: Float,
        naturalSpan: Float,
        camera: CameraProjection,
        /** Corrección fina por ojo, como fracción del ancho de pantalla
         * ([0,1]). Ver [RendererConfiguration.RIGHT_EYE_X_NUDGE]. */
        xNudgeNormalized: Float = 0f,
    ): EyeTransform {
        val nx = (anchor.point.x / imageWidth) + xNudgeNormalized
        val ny = anchor.point.y / imageHeight
        // NDC: X crece a la derecha [-1,1] igual que la imagen; Y de imagen
        // crece hacia abajo pero NDC (OpenGL/Filament) crece hacia arriba,
        // de ahí el signo invertido en ndcY.
        val ndcX = 2f * nx - 1f
        val ndcY = 1f - 2f * ny

        val worldZ = headPose.position.z.coerceIn(
            RendererConfiguration.MIN_DEPTH,
            RendererConfiguration.MAX_DEPTH,
        )
        val position = camera.unproject(ndcX, ndcY, worldZ)

        // Corrección de escorzo (foreshortening): cuánto de frente mira el
        // plano del ojo a la cámara (que observa a lo largo de +Z). normal.z
        // ≈ 1 → de frente, sin corrección; se acerca a 0 → el ojo se ve de
        // perfil y su ancho proyectado se reduce, así que se compensa
        // dividiendo por ese factor (clamped para no explotar en ángulos
        // extremos de tracking ruidoso).
        val facingFactor = abs(eyePlane.normal.z).coerceAtLeast(0.35f)
        val tiltCorrection = (1f / facingFactor).coerceAtMost(2.2f) *
            RendererConfiguration.HEAD_TILT_MULTIPLIER

        // Ancho real del ojo en unidades de mundo: se des-proyectan los dos
        // bordes del ojo a la MISMA profundidad y se mide la distancia real
        // entre ellos — físicamente correcto a cualquier distancia de
        // cámara, sin ninguna constante de "escala de mundo".
        val ndcXLeftEdge = 2f * (nx - (anchor.widthPx / 2f) / imageWidth) - 1f
        val ndcXRightEdge = 2f * (nx + (anchor.widthPx / 2f) / imageWidth) - 1f
        val eyeWidthWorld = camera.worldDistanceAtDepth(ndcXLeftEdge, ndcXRightEdge, ndcY, worldZ)

        val desiredWorldWidth = eyeWidthWorld * RendererConfiguration.WIDTH_MULTIPLIER * tiltCorrection
        val rawScale = if (naturalSpan > 0f) desiredWorldWidth / naturalSpan else 1f
        val scaleFactor = if (rawScale.isFinite() && rawScale > 0f) rawScale else 1f

        return EyeTransform(
            position = position,
            rotation = eyePlane.rotation,
            scale = Float3(scaleFactor, scaleFactor, scaleFactor),
        )
    }
}
