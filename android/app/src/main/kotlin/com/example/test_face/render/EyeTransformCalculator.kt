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
    /** Curva de ajuste del párpado superior para el doblado del mesh (ver
     * [LashMeshBender]) — `null` si no hay suficientes puntos para un
     * ajuste significativo en este frame. NO se suaviza por
     * [EyeTrackingFilter]/[PoseInterpolator]: se propaga tal cual del frame
     * más reciente, igual que [opennessRatio]. */
    val lashLineCurve: LashLineCurve? = null,
    /** Ancho real del ojo en píxeles de imagen (`EyeAnchor.widthPx`) — ver
     * [LashMeshBender], necesario para convertir [lashLineCurve] (en
     * píxeles) a unidades locales del mesh. */
    val eyeWidthPx: Float = 0f,
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
        /** [EyeModelSlot.rootLocalY] — la raíz real de la pestaña en
         * unidades locales del `.glb` (mismo sistema que [naturalSpan]),
         * NO el origen (0,0,0) del modelo. `0f` si el mesh todavía no
         * terminó de parsear (degrada a anclar el origen, comportamiento
         * anterior). Ver [RawMesh]/[EyeModelSlot] para la evidencia de por
         * qué el origen del `.glb` no coincide con la raíz visual. */
        rootLocalY: Float = 0f,
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
        // Escala Y (volumen/grosor) por separado de X/Z (ancho/profundidad):
        // sube el eje Y local del modelo un poco más que el resto, para que
        // se vea más lleno sin estirarlo más allá de las esquinas del ojo
        // en X (ver RendererConfiguration.HEIGHT_VOLUME_MULTIPLIER).
        val scaleY = scaleFactor * RendererConfiguration.HEIGHT_VOLUME_MULTIPLIER

        // RESTAURADO 2026-08-10: el `.glb` está centrado en su bounding box
        // (minY = -maxY, verificado), pero la RAÍZ VISUAL real del mesh (la
        // banda densa donde nace la fibra) está muy por debajo de ese centro
        // — confirmado con histograma de densidad de vértices en Y (sección
        // 5.1 del doc, confirmado en dispositivo real 2026-07-24). Anclar el
        // CENTRO geométrico en `position` (como hacía una versión sin
        // commitear de este archivo, encontrada en esta sesión) reintroduce
        // exactamente ese bug: la mitad superior/dispersa del abanico de
        // fibras queda cerca del ancla y la mitad inferior/densa (la raíz
        // real) cuelga lejos de la línea de pestañas real — visible en
        // dispositivo como el modelo "flotando" desconectado del párpado.
        // `rootLocalY` es negativo (está por debajo del origen local) y usa
        // `scaleY`, no `scaleFactor` (el desplazamiento de la raíz es a lo
        // largo del eje Y del modelo — ver sección 5.3), así que el signo
        // menos desplaza el origen hacia ARRIBA la distancia justa para que
        // sea la RAÍZ, no el centro, la que quede en `position`.
        val rootCorrectedPosition = position - eyePlane.up * (scaleY * rootLocalY)

        return EyeTransform(
            position = rootCorrectedPosition,
            rotation = eyePlane.rotation,
            scale = Float3(scaleFactor, scaleY, scaleFactor),
        )
    }
}
