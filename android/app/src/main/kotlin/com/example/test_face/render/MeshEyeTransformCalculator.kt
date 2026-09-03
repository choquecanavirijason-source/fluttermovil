package com.example.test_face.render

import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.dot
import kotlin.math.sqrt

/**
 * Fase 2 del plan de migración a face-mesh: deriva la POSICIÓN de la pestaña
 * de la posición de mundo REAL de landmarks del párpado (canto medial,
 * lateral, ápice, y el arco de 8 puntos del párpado superior) — ya
 * perspectiva-correcta gracias a la malla facial de 468 puntos (ver
 * [FaceMeshMath]/[FaceMeshRenderer]).
 *
 * REESCRITO 2026-09-01 (decisión del usuario, con evidencia de varias
 * capturas reales en dispositivo): la ORIENTACIÓN (`right`/`up`/`normal`) ya
 * NO se deriva acá de un producto cruzado de 2-3 landmarks sueltos — ese
 * enfoque se probó, se parchó tres veces (paridad ojo izq/der, ruido de un
 * solo punto en la normal, inclinación de `right`) y aun así nunca quedó tan
 * estable como el `up` que ya calculaba [EyePlaneCalculator] a partir de la
 * pose de cabeza completa de MediaPipe — confirmado con capturas reales: el
 * `up` del sistema viejo salía casi idéntico entre los dos ojos en TODAS las
 * rondas; el de acá recién se acercó después de tres parches. Este archivo
 * ahora es un HÍBRIDO: toma `right`/`up`/`normal`/`rotation` ya calculados
 * por [EyePlaneCalculator] (pasados como [eyePlane]) — la pieza comprobada —
 * y solo aporta la POSICIÓN real en 3D (mejor que el ancla 2D+headPose del
 * sistema viejo) y la escala derivada del ancho/alto real del ojo.
 *
 * NO reemplaza a [EyeAnchorCalculator]: ese sigue siendo el ancla 2D en
 * píxeles que consumen [LashLineCurve]/[LashMeshBender] — este archivo solo
 * produce el mismo [EyeTransform] que [EyeTransformCalculator], por otra vía.
 *
 * Activado por [RendererConfiguration.LASH_ANCHOR_FROM_FACE_MESH] desde
 * [FaceRenderPipeline.computeEye] — con el flag en `false`, este archivo no
 * se llama nunca.
 */
object MeshEyeTransformCalculator {

    /** Resultado enriquecido para calibración (ver
     * [RendererConfiguration.MESH_CALIBRATION_LOGGING] /
     * `FaceRenderPipeline.logMeshCalibration`) — expone las magnitudes
     * intermedias que [compute] no devuelve. */
    data class DebugInfo(
        val transform: EyeTransform?,
        val normal: Float3,
        val eyeWidthWorld: Float,
        val eyeHeightWorld: Float,
        val baseZ: Float,
        /** Base ortonormal usada (ver [eyePlane]) — para comparar contra
         * [EyePlane.up]/[EyePlane.right] del sistema viejo en el log de
         * calibración. Debería ser CASI IDÉNTICA a esa (mismo origen, ver
         * KDoc de la clase) — si diverge, algo se rompió. */
        val right: Float3 = Float3(0f, 0f, 0f),
        val up: Float3 = Float3(0f, 0f, 0f),
        /** Desglose vertical de `position.y` para la calibración de altura:
         * `position.y = centroidY + heightCorrection - heightOffsetTermY -
         * heightNudgeTermY - rootCorrectionTermY` (ver [computeWithDebug]).
         * `0f` en el caso `transform == null`. */
        val centroidY: Float = 0f,
        val anchorBaseY: Float = 0f,
        val heightOffsetTermY: Float = 0f,
        val rootCorrectionTermY: Float = 0f,
        val rootLocalYIn: Float = 0f,
        val scaleYOut: Float = 0f,
    )

    fun compute(
        landmarks: List<NormalizedLandmark>,
        medialIndex: Int,
        lateralIndex: Int,
        apexIndex: Int,
        /** Los 8 índices del párpado SUPERIOR (mismo subset que consume
         * [EyeAnchorCalculator]/`ring[8:16]`) — se promedian en 3D para
         * ubicar la altura del ancla en el arco real, no en un solo punto. */
        upperLidIndices: IntArray,
        camera: CameraProjection,
        headPose: HeadPose,
        /** `right`/`up`/`normal`/`rotation` ya calculados por
         * [EyePlaneCalculator] para este mismo ojo, este mismo frame — ver
         * KDoc de la clase sobre por qué la orientación se toma de ahí. */
        eyePlane: EyePlane,
        naturalSpan: Float,
        rootLocalY: Float,
        styleConfig: LashStyleConfig,
    ): EyeTransform? = computeWithDebug(
        landmarks, medialIndex, lateralIndex, apexIndex, upperLidIndices, camera, headPose, eyePlane, naturalSpan, rootLocalY, styleConfig,
    ).transform

    fun computeWithDebug(
        landmarks: List<NormalizedLandmark>,
        medialIndex: Int,
        lateralIndex: Int,
        apexIndex: Int,
        upperLidIndices: IntArray,
        camera: CameraProjection,
        headPose: HeadPose,
        eyePlane: EyePlane,
        naturalSpan: Float,
        rootLocalY: Float,
        styleConfig: LashStyleConfig,
    ): DebugInfo {
        if (medialIndex >= landmarks.size || lateralIndex >= landmarks.size || apexIndex >= landmarks.size) {
            return DebugInfo(null, Float3(0f, 0f, 0f), 0f, 0f, 0f)
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
        val upperLidWorldPoints = upperLidIndices
            .filter { it < landmarks.size }
            .map { FaceMeshMath.worldPositionOf(landmarks[it], camera, baseZ, worldUnitsPerNormalizedUnit) }

        // Orientación: ver KDoc de la clase — tomada de EyePlaneCalculator,
        // NO derivada acá.
        val right = eyePlane.right
        val up = eyePlane.up
        val normal = eyePlane.normal

        val eyeWidthWorld = worldDistance(medialWorld, lateralWorld)
        val chord2 = apexWorld - medialWorld
        // Alto "real" del ojo = proyección del ápice sobre `up`, medido desde
        // la línea medial→lateral — eyeWidthWorld/eyeHeightWorld siguen
        // siendo distancias físicas 3D reales, correctas a cualquier ángulo
        // de cabeza, sin necesitar tiltCorrection.
        val eyeHeightWorld = dot(chord2, up)
        if (!eyeWidthWorld.isFinite() || eyeWidthWorld < 1e-4f) {
            return DebugInfo(null, normal, eyeWidthWorld, eyeHeightWorld, baseZ)
        }

        val desiredWorldWidth = eyeWidthWorld * RendererConfiguration.WIDTH_MULTIPLIER
        val rawScale = if (naturalSpan > 0f) desiredWorldWidth / naturalSpan else 1f
        val scaleFactor = if (rawScale.isFinite() && rawScale > 0f) rawScale else 1f
        val scaleY = scaleFactor * RendererConfiguration.HEIGHT_VOLUME_MULTIPLIER

        // ANCLA = promedio de los 8 puntos REALES del párpado superior, y
        // nada más. Reescrito 2026-09-02 tras el señalamiento del usuario:
        // el objetivo de este sistema siempre fue colocar la pestaña sobre
        // los rasgos 3D reales de cada cara, SIN constantes calibradas a
        // mano — pero la versión anterior tomaba el centroide de 3 puntos y
        // encima le sumaba `heightOffset` (constante manual heredada del
        // sistema 2D) y un `MESH_ANCHOR_HEIGHT_NUDGE` inventado, o sea más
        // calibración manual que el sistema que venía a reemplazar. Esos dos
        // términos se eliminaron: esos 8 puntos SON la línea de nacimiento
        // de la pestaña, no hace falta desplazarlos.
        // CORRECCIÓN 2026-09-02 (confirmada con el overlay de debug en
        // dispositivo): promediar los 7 puntos del arco NO da un punto sobre
        // la línea del párpado — da un punto POR DEBAJO de ella, en el medio
        // del ojo, porque los extremos del arco bajan hacia las esquinas y
        // arrastran la media. Con la raíz ahí, el abanico (que mide ~2x la
        // altura del ojo) nacía en el medio del ojo y se extendía por encima
        // del párpado hasta la ceja — exactamente el síntoma reportado.
        //
        // Fix: promediar solo los 3 puntos MÁS ALTOS del arco (mayor
        // proyección sobre `up`). Eso cae sobre la línea real de nacimiento
        // de la pestaña, y al ser un promedio de 3 sigue siendo robusto al
        // ruido de tracking de un punto suelto (a diferencia de usar el
        // ápice solo, que ya se probó y hacía "voltear" el modelo).
        val anchorBase = if (upperLidWorldPoints.isNotEmpty()) {
            val topPoints = upperLidWorldPoints
                .sortedByDescending { dot(it, up) }
                .take(TOP_LID_POINTS_FOR_ANCHOR)
            var sum = Float3(0f, 0f, 0f)
            for (p in topPoints) sum += p
            sum / topPoints.size.toFloat()
        } else {
            // Sin los puntos del arco no hay línea real que seguir — degradar
            // al ápice (único punto del párpado superior disponible) antes
            // que devolver una posición sin sentido.
            apexWorld
        }
        // Única corrección que queda, y NO es calibración manual: `rootLocalY`
        // es una propiedad MEDIDA del `.glb` cargado (`rawMesh.minY`, dónde
        // está la raíz del abanico respecto al origen del modelo). Sin esto
        // se ancla el origen del mesh en vez de su raíz, y la pestaña queda
        // colgando lejos del párpado (ver EyeTransformCalculator, sección
        // 5.1 de COLOCADO_PESTANAS).
        val rootCorrectionTerm = up * (scaleY * rootLocalY)
        val rootCorrectedPosition = anchorBase - rootCorrectionTerm

        val transform = EyeTransform(
            position = rootCorrectedPosition,
            rotation = eyePlane.rotation,
            scale = Float3(scaleFactor, scaleY, scaleFactor),
        )
        return DebugInfo(
            transform, normal, eyeWidthWorld, eyeHeightWorld, baseZ,
            right = right,
            up = up,
            centroidY = anchorBase.y,
            anchorBaseY = anchorBase.y,
            heightOffsetTermY = 0f,
            rootCorrectionTermY = rootCorrectionTerm.y,
            rootLocalYIn = rootLocalY,
            scaleYOut = scaleY,
        )
    }

    /** Cuántos de los puntos más altos del arco del párpado superior se
     * promedian para ubicar la raíz (ver [computeWithDebug]). 3 de 7: cae
     * sobre la línea real de pestañas y sigue promediando lo suficiente como
     * para no depender del ruido de un landmark suelto. */
    private const val TOP_LID_POINTS_FOR_ANCHOR = 3

    /** Distancia euclídea manual (no un helper de kotlin-math) — mismo patrón
     * exacto que [CameraProjection.worldDistanceAtDepth]. */
    private fun worldDistance(a: Float3, b: Float3): Float {
        val dx = b.x - a.x
        val dy = b.y - a.y
        val dz = b.z - a.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
}
