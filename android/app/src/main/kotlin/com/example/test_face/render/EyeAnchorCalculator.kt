package com.example.test_face.render

import kotlin.math.abs
import kotlin.math.hypot

/** Resultado geométrico 2D de un ojo, listo para proyectar a espacio de mundo. */
data class EyeAnchor(
    val point: ImagePoint,
    val widthPx: Float,
    val heightPx: Float,
    val upperLidTangent: ImagePoint,
    /** Centroide REAL del párpado superior (`meanX`/`meanY`, ver [compute]),
     * SIN los desplazamientos de estilo ([LashStyleConfig.noseAvoidShift]/
     * [LashStyleConfig.lateralLashOffset]/[LashStyleConfig.heightOffset])
     * que sí tiene [point]. Solo para diagnóstico/debug — [LashLineCurve.fit]
     * ya NO se ajusta alrededor de este punto (ver nota de la clase,
     * "unificación de frame" 2026-08-10). */
    val lidCenter: ImagePoint,
    /** Canto medial (lagrimal, hacia la nariz) — uno de los dos extremos
     * reales en X del anillo de 16 puntos del ojo. Nombrado explícitamente
     * (en vez de "cornerA/cornerB" sin significado) para que cualquier
     * cálculo que necesite el extremo interno del ojo lo use por nombre, no
     * por índice ni por min/max recalculado aparte. */
    val medialCanthus: ImagePoint,
    /** Canto lateral (temporal, hacia la sien) — el otro extremo real en X
     * del anillo. Ver [medialCanthus]. */
    val lateralCanthus: ImagePoint,
)

/**
 * Calcula el punto de anclaje de las pestañas 3D.
 *
 * **Principio (corregido 2026-07-24)**: `anchor.point` es el punto de mundo
 * donde debe renderizar la RAÍZ real de la pestaña (`EyeModelSlot.
 * rootLocalY`, ver [EyeTransformCalculator]) — NO el centro geométrico del
 * bounding box del modelo. Se verificó con los 10 `.glb` reales de
 * `assets/modelos/` que su bounding box en Y está centrado en el origen
 * local, pero la masa/raíz visual del mesh está muy por debajo de ese
 * centro — anclar el centro (como se hacía antes, y como una versión sin
 * commitear de `EyeTransformCalculator` encontrada y revertida en esta
 * sesión volvía a hacer) empuja la pestaña sistemáticamente lejos de la
 * línea real del párpado. Para extensiones de pestañas reales:
 *   - El borde del párpado (lash line) es el ORIGEN de las pestañas
 *   - Las pestañas se extienden HACIA ARRIBA desde ahí
 *
 * En coordenadas de imagen, Y crece HACIA ABAJO, así que "arriba en el
 * rostro" = Y menor. La fórmula es:
 *
 *   anchorY = meanY - height * HEIGHT_OFFSET
 *
 * donde `meanY` es el promedio de Y de TODOS los puntos del párpado
 * superior (el mismo conjunto y el mismo peso que `meanX`, así que X e Y
 * quedan geométricamente consistentes entre sí) y HEIGHT_OFFSET ≥ 0 mueve
 * el ancla hacia arriba (Y más pequeño = más arriba en la imagen = hacia
 * la frente).
 *
 * **Unificación de frame (2026-08-10)**: hasta esta fecha, `LashLineCurve`
 * se ajustaba alrededor de `lidCenter` (el centroide SIN desplazar) en vez
 * de `point` (el ancla de RENDER, desplazada por `noseAvoidShift`/
 * `lateralLashOffset`), porque el ajuste anterior (una parábola por mínimos
 * cuadrados) se mal-condicionaba numéricamente si se centraba lejos de la
 * nube real de puntos — eso obligaba a mantener DOS orígenes distintos
 * (`point` para el transform rígido, `lidCenter` para la curva) y una
 * corrección aparte (`lashCurveAnchorOffsetPx`, ya eliminada) solo para
 * reconciliarlos. Con el spline de Hermite/Catmull-Rom que reemplazó a esa
 * parábola (ver `LashLineCurve`, interpola los puntos reales en vez de
 * aproximarlos), ese mal-condicionamiento ya no existe — el spline es
 * válido en cualquier origen. Por eso ahora `FaceRenderPipeline` ajusta la
 * curva directamente alrededor de `point`: transform, curva y doblado del
 * mesh comparten el MISMO frame, sin offset de reconciliación.
 */
object EyeAnchorCalculator {

    /** [imageWidth] — ancho de la imagen de análisis, en píxeles. Se usa
     * SOLO para estimar qué esquina del ojo es la externa (hacia la sien)
     * vs la interna (hacia la nariz), comparando cada esquina contra el
     * centro horizontal de la imagen — ver [RendererConfiguration.
     * NOSE_AVOID_SHIFT]. No depende de saber si es el ojo izquierdo o
     * derecho de MediaPipe (evita esa ambigüedad — ver nota en
     * [FaceLandmarkIndices]), solo de que el rostro esté razonablemente
     * centrado en el cuadro (caso normal de selfie). */
    /** [styleConfig] reemplaza a los `const val` fijos de
     * `RendererConfiguration.HEIGHT_OFFSET`/`NOSE_AVOID_SHIFT` — ver
     * [LashStyleConfig]: esos dos parámetros varían legítimamente por
     * estilo artístico (Cat Eye vs. Natural), no son calibración física de
     * dispositivo. `LashStyleConfig.DEFAULT` reproduce el comportamiento
     * anterior (mismos valores que las constantes globales). */
    fun compute(eye: EyeLandmarks, imageWidth: Float, styleConfig: LashStyleConfig = LashStyleConfig.DEFAULT): EyeAnchor? {
        if (eye.upperLid.size < 2) return null

        val width = eye.width
        val height = eye.height
        if (width < 1f || height < 0.5f || !width.isFinite() || !height.isFinite()) return null

        // Centroide del párpado superior = promedio de X e Y de TODOS sus
        // puntos. Ambos se calculan del MISMO conjunto de puntos con el
        // MISMO peso, así que X e Y quedan geométricamente consistentes
        // entre sí (corrección 2026-07-24, ver nota de la clase).
        val meanX = eye.upperLid.sumOf { it.x.toDouble() }.toFloat() / eye.upperLid.size
        val meanY = eye.upperLid.sumOf { it.y.toDouble() }.toFloat() / eye.upperLid.size

        // `cornerA`/`cornerB` (los extremos en X del anillo de 16 puntos del
        // ojo) SON, anatómicamente, el canto medial/lagrimal y el canto
        // lateral/temporal — las únicas dos esquinas reales de un ojo — sin
        // necesitar índices de landmark dedicados nuevos. Se calculan UNA
        // sola vez acá y se exponen nombrados en [EyeAnchor] (ver
        // `medialCanthus`/`lateralCanthus`) para que ningún otro archivo
        // necesite recalcular min/max sobre `eye.ring`.
        val cornerA = eye.ring.minByOrNull { it.x }
        val cornerB = eye.ring.maxByOrNull { it.x }
        val imageCenterX = imageWidth / 2f
        val cornerAIsLateral = cornerA != null && cornerB != null &&
            abs(cornerA.x - imageCenterX) > abs(cornerB.x - imageCenterX)
        val medialCanthus = when {
            cornerA != null && cornerB != null -> if (cornerAIsLateral) cornerB else cornerA
            else -> ImagePoint(meanX, meanY)
        }
        val lateralCanthus = when {
            cornerA != null && cornerB != null -> if (cornerAIsLateral) cornerA else cornerB
            else -> ImagePoint(meanX, meanY)
        }

        // Desplaza el ancla X hacia la esquina EXTERNA del ojo — ver
        // LashStyleConfig.noseAvoidShift y la nota de la clase (2026-07-24):
        // evita que la expansión simétrica de WIDTH_MULTIPLIER invada la
        // nariz por el lado interno.
        val shiftSign = if (lateralCanthus.x >= meanX) 1f else -1f
        val shiftedX = meanX + shiftSign * width * styleConfig.noseAvoidShift

        // El ancla sube (Y decrece) desde el centroide según heightOffset.
        val anchorY = meanY - height * styleConfig.heightOffset

        // CORRECCIÓN 2026-08-08 (LATERAL_LASH_OFFSET, ver
        // RendererConfiguration): reportado en dispositivo real que el
        // conjunto seguía viéndose corrido hacia el canto medial/lagrimal
        // incluso con NOSE_AVOID_SHIFT activo. Causa: el desplazamiento de
        // arriba es puramente horizontal (un signo × una magnitud en X), no
        // a lo largo del eje REAL del ojo — con la cabeza en roll, ese eje
        // tiene una componente en Y que el shift horizontal no cubre.
        //
        // Corrección ADITIVA (no reemplaza el shift de arriba, se suma
        // encima) siguiendo el vector real medial→lateral:
        //   lateralDirection = normalize(lateralCanthus − medialCanthus)
        //   correctedPoint   = shiftedPoint + lateralDirection × (distancia(cantos) × lateralLashOffset)
        // `distancia(cantos)` es la distancia real entre los dos cantos (no
        // `width`, que es el ancho del bounding box — puede diferir si el
        // ojo está rotado), así que el offset sigue siendo proporcional al
        // tamaño REAL del ojo en la imagen, no un valor fijo en píxeles.
        val lateralDx = lateralCanthus.x - medialCanthus.x
        val lateralDy = lateralCanthus.y - medialCanthus.y
        val canthusDistance = hypot(lateralDx.toDouble(), lateralDy.toDouble())
            .toFloat().coerceAtLeast(1e-4f)
        val lateralDirX = lateralDx / canthusDistance
        val lateralDirY = lateralDy / canthusDistance
        val lateralOffsetPx = canthusDistance * styleConfig.lateralLashOffset
        val pointX = shiftedX + lateralDirX * lateralOffsetPx
        val pointY = anchorY + lateralDirY * lateralOffsetPx
        val anchor = ImagePoint(pointX, pointY)

        val tangent = fittedUpperLidTangent(eye.upperLid, meanX, meanY)

        return EyeAnchor(
            point = anchor,
            widthPx = width,
            heightPx = height,
            upperLidTangent = tangent,
            lidCenter = ImagePoint(meanX, meanY),
            medialCanthus = medialCanthus,
            lateralCanthus = lateralCanthus,
        )
    }

    /**
     * Tangente del párpado superior por mínimos cuadrados de y sobre x
     * (`slope = sxy / sxx`).
     *
     * ANTES usaba el EJE PRINCIPAL de la nube de puntos:
     *
     *     theta = 0.5 * atan2(2*sxy, sxx - syy)
     *
     * Eso tiene una discontinuidad de 90°: en cuanto `sxx - syy` cambia de
     * signo — o sea cuando los puntos del párpado quedan MÁS ALTOS QUE
     * ANCHOS — `atan2` salta a ±π y `theta` a ±π/2, así que la tangente rota
     * un cuarto de vuelta entre un frame y el siguiente y el modelo se
     * VOLTEA. La corrección de sentido de más abajo no lo puede tapar: solo
     * arregla inversiones de 180°.
     *
     * Esa condición se cumple con el ojo entrecerrado, al parpadear, o con
     * la cabeza girada (el ojo se escorza y pierde ancho) — justo los casos
     * reportados en dispositivo como "a veces voltea las pestañas". Se
     * volvió más frecuente al sacar el canto de `upperLid` (fix 9..15 en
     * [EyeLandmarks]): ese punto era uno de los de mayor extensión en X, y
     * sin él `sxx` baja y cruza a `syy` más seguido.
     *
     * Mínimos cuadrados de y sobre x no tiene esa discontinuidad: el
     * párpado superior ES una función de x (`upperLid` ya viene ordenado por
     * x, ver [EyeLandmarks.from]), la pendiente varía de forma continua y la
     * tangente nunca puede rotar 90° de golpe. Solo degenera si TODOS los
     * puntos comparten la misma x (`sxx ≈ 0`), caso imposible en un párpado
     * real y cubierto igual por el fallback.
     */
    private fun fittedUpperLidTangent(
        points: List<ImagePoint>,
        meanX: Float,
        meanY: Float,
    ): ImagePoint {
        var sxx = 0.0
        var sxy = 0.0
        for (p in points) {
            val dx = (p.x - meanX).toDouble()
            val dy = (p.y - meanY).toDouble()
            sxx += dx * dx
            sxy += dx * dy
        }

        val first = points.first()
        val last = points.last()

        // Degenerado (todos los puntos en la misma columna): cae a la
        // dirección primero→último, que sigue siendo continua entre frames.
        if (sxx < 1e-6) {
            val dx = last.x - first.x
            val dy = last.y - first.y
            val len = hypot(dx.toDouble(), dy.toDouble()).toFloat()
            return if (len < 1e-4f) ImagePoint(1f, 0f) else ImagePoint(dx / len, dy / len)
        }

        var tx = 1f
        var ty = (sxy / sxx).toFloat()

        // `points` viene ordenado por x, así que `refDx >= 0` y `tx = 1` ya
        // apunta en ese sentido; la comprobación queda por si el orden
        // cambiara en el futuro.
        val refDx = last.x - first.x
        val refDy = last.y - first.y
        if (tx * refDx + ty * refDy < 0f) {
            tx = -tx
            ty = -ty
        }

        val len = hypot(tx.toDouble(), ty.toDouble()).toFloat().coerceAtLeast(1e-4f)
        return ImagePoint(tx / len, ty / len)
    }
}
