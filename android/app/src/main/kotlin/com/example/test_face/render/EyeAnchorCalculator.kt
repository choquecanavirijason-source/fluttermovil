package com.example.test_face.render

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

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
    /** Forma del párpado MEDIDA en este frame, siempre — aunque el resto de
     * este [EyeAnchor] se haya construido con una forma congelada (ver el
     * parámetro `heldShape` de [compute]). Es lo que el llamador guarda en
     * [LidShapeHold] mientras el ojo está abierto. */
    val measuredShape: LidShape,
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
 * centro — anclar el centro empuja la pestaña sistemáticamente lejos de la
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
 * **Unificación de frame (2026-08-10)**: hasta esa fecha, `LashLineCurve`
 * se ajustaba alrededor de `lidCenter` (el centroide SIN desplazar) en vez
 * de `point` (el ancla de RENDER), porque el ajuste anterior (una parábola
 * por mínimos cuadrados) se mal-condicionaba numéricamente si se centraba
 * lejos de la nube real de puntos. Con el spline de Hermite que reemplazó a
 * esa parábola (interpola los puntos reales en vez de aproximarlos) ese
 * mal-condicionamiento ya no existe — el spline es válido en cualquier
 * origen. Por eso ahora `FaceRenderPipeline` ajusta la curva directamente
 * alrededor de `point`: transform, curva y doblado del mesh comparten el
 * MISMO frame, sin offset de reconciliación.
 *
 * **Separación forma / posición (2026-09-04, fix de parpadeo)**: `height` y
 * la tangente ya no se consumen directo de los landmarks de este frame.
 * Primero se expresan como [LidShape] — una razón adimensional y un ángulo
 * RELATIVO al eje esquina-a-esquina — y el ancla las reconstruye contra el
 * ancho y el eje VIVOS de este frame. Así, pasar `heldShape` (lo último
 * medido con el ojo abierto) congela sólo esas dos cantidades, que con el
 * ojo cerrándose dejan de describir un párpado abierto; la escala por
 * distancia y el roll de cabeza siguen siendo los de este frame.
 *
 * `meanX`/`meanY` (el centroide del arco) NO entran en [LidShape] a
 * propósito: se miden siempre en vivo. Que bajen al cerrar el ojo no es
 * ruido, es el borde del párpado bajando de verdad — y una extensión pegada
 * a ese borde tiene que bajar con él. Ver el KDoc de [LidShape] para el
 * desglose de qué se congela y qué no.
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
    fun compute(
        eye: EyeLandmarks,
        imageWidth: Float,
        styleConfig: LashStyleConfig = LashStyleConfig.DEFAULT,
        /** Forma del párpado a usar en vez de la medida en este frame — ver
         * [LidShape]. `null` (default) mide en vivo, que es el
         * comportamiento de siempre y el único camino con el ojo abierto. */
        heldShape: LidShape? = null,
    ): EyeAnchor? {
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

        // ── Eje local del ojo: esquina de menor X → esquina de mayor X ────
        // El MISMO eje que ya usa [EyePlaneCalculator] para su residuo (min X
        // → max X, no medial → lateral), así que el ángulo ronda 0 para los
        // dos ojos y no hay que lidiar con el envoltorio en ±π, y el residuo
        // que se congela acá es exactamente el que consume ese cálculo.
        //
        // Este eje es la referencia ESTABLE del ojo: los dos cantos son las
        // esquinas donde se juntan los párpados y prácticamente no se mueven
        // al parpadear, a diferencia del arco del párpado superior, que baja
        // entero. Por eso sirve para expresar la INCLINACIÓN del párpado de
        // manera que se pueda congelar sin congelar el roll de la cabeza.
        val frameStart = cornerA ?: ImagePoint(meanX, meanY)
        val frameEnd = cornerB ?: ImagePoint(meanX, meanY)
        val cornerAngle = atan2(
            (frameEnd.y - frameStart.y).toDouble(),
            (frameEnd.x - frameStart.x).toDouble(),
        ).toFloat()

        // ── Forma medida en ESTE frame ───────────────────────────────────
        val rawTangent = fittedUpperLidTangent(eye.upperLid, meanX, meanY)
        val measuredShape = LidShape(
            heightOverWidth = height / width,
            tangentResidualRad = normalizeAngle(
                atan2(rawTangent.y.toDouble(), rawTangent.x.toDouble()).toFloat() - cornerAngle,
            ),
        )

        // ── Forma efectiva: la congelada si la hay, si no la de este frame ─
        //
        // El CENTROIDE queda deliberadamente afuera de [LidShape]: se usa
        // siempre el medido en vivo. Que baje al cerrar el ojo no es un
        // artefacto del tracking, es el borde del párpado bajando de verdad,
        // y una extensión pegada a ese borde baja con él. Congelarlo dejaría
        // la pestaña flotando a la altura del ojo abierto sobre un párpado ya
        // cerrado. Lo que sí se congela es lo que NO es movimiento real sino
        // ruido/colapso de medición: la elevación extra derivada de la altura
        // del ojo, y la inclinación ajustada sobre una nube de puntos que con
        // el ojo cerrado ya es casi una recta (ver KDoc de [LidShape]).
        val shape = heldShape ?: measuredShape
        // La altura se reconstruye desde la RAZÓN alto/ancho y el ancho VIVO
        // (que no colapsa al parpadear), así que el término de elevación del
        // ancla sigue siendo correcto aunque la persona se acerque o se aleje
        // con el ojo cerrado.
        val effectiveHeight = (shape.heightOverWidth * width).coerceAtLeast(0.5f)
        val tangentAngle = cornerAngle + shape.tangentResidualRad
        val tangent = ImagePoint(cos(tangentAngle), sin(tangentAngle))

        // Desplaza el ancla X hacia la esquina EXTERNA del ojo — ver
        // LashStyleConfig.noseAvoidShift y la nota de la clase (2026-07-24):
        // evita que la expansión simétrica de WIDTH_MULTIPLIER invada la
        // nariz por el lado interno.
        val shiftSign = if (lateralCanthus.x >= meanX) 1f else -1f
        val shiftedX = meanX + shiftSign * width * styleConfig.noseAvoidShift

        // El ancla sube (Y decrece) desde el centroide según heightOffset.
        val anchorY = meanY - effectiveHeight * styleConfig.heightOffset

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

        return EyeAnchor(
            point = anchor,
            widthPx = width,
            heightPx = effectiveHeight,
            upperLidTangent = tangent,
            lidCenter = ImagePoint(meanX, meanY),
            medialCanthus = medialCanthus,
            lateralCanthus = lateralCanthus,
            measuredShape = measuredShape,
        )
    }

    /** Lleva [angleRad] al rango `[-π, π]` — [LidShape.tangentResidualRad] es
     * una diferencia de dos `atan2`, que sin normalizar puede salir cerca de
     * ±2π y volver discontinua la reconstrucción. */
    private fun normalizeAngle(angleRad: Float): Float {
        val twoPi = (2.0 * PI).toFloat()
        var a = angleRad % twoPi
        if (a > PI) a -= twoPi
        if (a < -PI) a += twoPi
        return a
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
     *
     * Aun sin esa discontinuidad, con el ojo a medio cerrar la pendiente se
     * ajusta sobre una nube casi plana y queda dominada por el ruido de
     * ±1-2 px de cada landmark — por eso el resultado se CONGELA durante el
     * parpadeo (vía [LidShape.tangentResidualRad]) en vez de usarse crudo.
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
