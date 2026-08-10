package com.example.test_face.render

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
     * SIN el desplazamiento de [RendererConfiguration.NOSE_AVOID_SHIFT] que
     * sí tiene [point]. [LashLineCurve.fit] debe ajustarse alrededor de este
     * punto (no de [point]) para que su rango `[minLocalX, maxLocalX]`
     * quede centrado donde realmente están los landmarks del párpado — ver
     * nota de la clase, diagnóstico BEND_DIAG 2026-08-02. */
    val lidCenter: ImagePoint,
    /** Proyección de `(point - lidCenter)` sobre [upperLidTangent] — cuánto
     * (en píxeles, a lo largo de la tangente) está desplazado el ancla de
     * render respecto al centroide real del párpado. [LashMeshBender]
     * necesita sumar esto a su `pixelLocalX` (que está expresado relativo a
     * `point`, porque ahí es donde se posiciona el centro del mesh) para
     * evaluar la curva —ajustada alrededor de `lidCenter`— en el sistema de
     * coordenadas correcto. Ver nota de la clase. */
    val lashCurveAnchorOffsetPx: Float,
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
 * centro — anclar el centro (como se hacía antes) empujaba la pestaña
 * sistemáticamente hacia la ceja. Para extensiones de pestañas reales:
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
 * CORRECCIÓN 2026-07-24 (ajuste fino): antes `anchorY` usaba `edgeLidY`
 * (promedio del 30% de puntos con MAYOR Y del párpado superior) en vez de
 * `meanY`. Para un párpado con forma de arco (más alto — Y menor — en el
 * centro, más bajo en las esquinas, que es la forma real de un ojo), "el
 * 30% con mayor Y" son casi siempre las ESQUINAS, no una muestra
 * representativa de toda la línea de pestañas — mientras que `meanX` sí
 * promedia TODOS los puntos (queda centrado). Esa mezcla (X centrado, Y de
 * esquina) desplazaba el ancla verticalmente respecto a dónde está la
 * línea de pestañas real en el CENTRO del ojo (donde cae `meanX`) — un
 * desfase real de varios píxeles, confirmado con logcat en dispositivo
 * real. `meanY` no tiene ese sesgo: es el centroide del mismo conjunto de
 * puntos que ya usa `meanX`.
 *
 * HEIGHT_OFFSET = 0.0 (valor actual) → ancla en el centroide del párpado
 * superior, y como ahora se ancla la RAÍZ real (no el centro del modelo),
 * la raíz de la pestaña nace ahí — anatómicamente correcto por defecto.
 * HEIGHT_OFFSET > 0 → la raíz queda esa fracción de la altura del ojo por
 * ENCIMA del centroide, solo si hiciera falta un margen estético.
 *
 * **`lidCenter`/`lashCurveAnchorOffsetPx` (2026-08-02)**: `point` (el ancla
 * de RENDER) está desplazado ~68% del ancho del ojo hacia la esquina
 * externa por `NOSE_AVOID_SHIFT` (ver más abajo) — necesario para que el
 * modelo 3D no invada la nariz, pero **no** es un buen origen para
 * `LashLineCurve.fit()`: `LashMeshBender` muestrea la curva centrada en el
 * punto medio del propio mesh (que se posiciona en `point`), así que si la
 * curva se ajusta alrededor de `point` en vez de la nube real de landmarks,
 * casi todos los vértices del mesh caen fuera del rango `[minLocalX,
 * maxLocalX]` que la curva realmente ajustó — y ahí `deviationAt`/
 * `slopeAt` extrapolan LINEALMENTE desde el borde en vez de seguir la
 * parábola (ver [LashLineCurve]), lo que se ve como una pestaña recta/sin
 * doblar en vez de curva. `lidCenter` (el centroide SIN desplazar) le da a
 * `LashLineCurve.fit()` un origen que sí coincide con la nube de landmarks;
 * `lashCurveAnchorOffsetPx` es la corrección que `LashMeshBender` necesita
 * sumar a su `pixelLocalX` (expresado relativo a `point`) para seguir
 * evaluando en el sistema de coordenadas de la curva (relativo a
 * `lidCenter`).
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
        if (width < 1f || height < 0.5f) return null

        // Centroide del párpado superior = promedio de X e Y de TODOS sus
        // puntos. Ambos se calculan del MISMO conjunto de puntos con el
        // MISMO peso, así que X e Y quedan geométricamente consistentes
        // entre sí (corrección 2026-07-24, ver nota de la clase).
        val meanX = eye.upperLid.sumOf { it.x.toDouble() }.toFloat() / eye.upperLid.size
        val meanY = eye.upperLid.sumOf { it.y.toDouble() }.toFloat() / eye.upperLid.size

        // Desplaza el ancla X hacia la esquina EXTERNA del ojo (la más
        // lejana al centro horizontal de la imagen, asumiendo rostro
        // centrado) — ver LashStyleConfig.noseAvoidShift y la nota de la
        // clase (2026-07-24): evita que la expansión simétrica de
        // WIDTH_MULTIPLIER invada la nariz por el lado interno.
        //
        // `cornerA`/`cornerB` (los extremos en X del anillo de 16 puntos del
        // ojo) SON, anatómicamente, el canto medial/lagrimal y el canto
        // lateral/temporal — las únicas dos esquinas reales de un ojo — sin
        // necesitar índices de landmark dedicados nuevos.
        val cornerA = eye.ring.minByOrNull { it.x }
        val cornerB = eye.ring.maxByOrNull { it.x }
        val imageCenterX = imageWidth / 2f
        val cornerAIsLateral = cornerA != null && cornerB != null &&
            kotlin.math.abs(cornerA.x - imageCenterX) > kotlin.math.abs(cornerB.x - imageCenterX)
        val outerCornerX = when {
            cornerA != null && cornerB != null -> if (cornerAIsLateral) cornerA.x else cornerB.x
            else -> meanX
        }
        val shiftSign = if (outerCornerX >= meanX) 1f else -1f
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
        //   lateralDirection = normalize(canthusLateral − canthusMedial)
        //   correctedPoint   = shiftedPoint + lateralDirection × (distancia(cantos) × lateralLashOffset)
        // `distancia(cantos)` es la distancia real entre los dos cantos (no
        // `width`, que es el ancho del bounding box — puede diferir si el
        // ojo está rotado), así que el offset sigue siendo proporcional al
        // tamaño REAL del ojo en la imagen, no un valor fijo en píxeles.
        // Al quedar expresado en píxeles de imagen (como el resto del
        // ancla), la misma des-proyección real de EyeTransformCalculator
        // (`camera.unproject`, ver Fase 1 del plan de motor) lo lleva a
        // espacio de mundo de forma correcta a cualquier distancia de
        // cámara — no hace falta ninguna corrección de perspectiva aparte
        // ni un desplazamiento fijo en unidades de mundo.
        var pointX = shiftedX
        var pointY = anchorY
        if (cornerA != null && cornerB != null) {
            val medialCanthus = if (cornerAIsLateral) cornerB else cornerA
            val lateralCanthus = if (cornerAIsLateral) cornerA else cornerB
            val lateralDx = lateralCanthus.x - medialCanthus.x
            val lateralDy = lateralCanthus.y - medialCanthus.y
            val canthusDistance = kotlin.math.hypot(lateralDx.toDouble(), lateralDy.toDouble())
                .toFloat().coerceAtLeast(1e-4f)
            val lateralDirX = lateralDx / canthusDistance
            val lateralDirY = lateralDy / canthusDistance
            val lateralOffsetPx = canthusDistance * styleConfig.lateralLashOffset
            pointX = shiftedX + lateralDirX * lateralOffsetPx
            pointY = anchorY + lateralDirY * lateralOffsetPx
        }
        val anchor = ImagePoint(pointX, pointY)

        val tangent = fittedUpperLidTangent(eye.upperLid, meanX, meanY)

        // lidCenter: centroide SIN el shift de NOSE_AVOID_SHIFT — origen
        // correcto para LashLineCurve.fit() (ver nota de la clase,
        // 2026-08-02). lashCurveAnchorOffsetPx: proyección de (anchor -
        // lidCenter) sobre la tangente, mismo producto punto que usa
        // LashLineCurve.fit para pasar a localX — permite a LashMeshBender
        // convertir su pixelLocalX (relativo a `anchor`, porque ahí se
        // posiciona el mesh) al sistema de coordenadas de la curva
        // (relativo a `lidCenter`).
        val lidCenter = ImagePoint(meanX, meanY)
        val lashCurveAnchorOffsetPx =
            (anchor.x - lidCenter.x) * tangent.x + (anchor.y - lidCenter.y) * tangent.y

        return EyeAnchor(
            point = anchor,
            widthPx = width,
            heightPx = height,
            upperLidTangent = tangent,
            lidCenter = lidCenter,
            lashCurveAnchorOffsetPx = lashCurveAnchorOffsetPx,
        )
    }

    private fun fittedUpperLidTangent(
        points: List<ImagePoint>,
        meanX: Float,
        meanY: Float,
    ): ImagePoint {
        var sxx = 0.0
        var syy = 0.0
        var sxy = 0.0
        for (p in points) {
            val dx = (p.x - meanX).toDouble()
            val dy = (p.y - meanY).toDouble()
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        val theta = 0.5 * atan2(2.0 * sxy, sxx - syy)
        var tx = cos(theta).toFloat()
        var ty = sin(theta).toFloat()

        val first = points.first()
        val last = points.last()
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
