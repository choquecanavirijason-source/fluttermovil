package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.geometries.Geometry
import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Deforma [RawMesh.vertices] para que la pestaña siga la curva real del
 * párpado ([LashLineCurve]) y envuelva el globo ocular en profundidad, en
 * vez de mantener su forma genérica plana de fábrica. Se aplica en espacio
 * LOCAL del mesh, ANTES del transform rígido (posición/rotación/escala) que
 * ya calcula [EyeTransformCalculator] — por eso solo hace falta la
 * curvatura ADICIONAL respecto a la inclinación promedio (que el rígido ya
 * cubre), no la pose completa.
 *
 * Dos deformaciones, cada una en un eje distinto:
 * - **Y (shear vertical puro, NO rotación)**: sigue la curva del párpado
 *   ([LashLineCurve]). Se probó y revirtió un bend por rotación (marco
 *   tangente/normal 2D) — este asset es un ABANICO de fibras individuales,
 *   no una cinta continua; rotar cada vértice según la pendiente LOCAL de
 *   su propia columna X hace que fibras vecinas giren cantidades distintas
 *   y sus puntas se crucen/enrosquen (confirmado en dispositivo real). El
 *   shear puro (`x`/`z` intactos en este eje, solo `y' = y + desviación`)
 *   es lo correcto para este tipo de malla.
 * - **Z (envolvente esférica)**: aproximación cuadrática de una esfera de
 *   radio `eyeWidthPx · styleConfig.zDepthDropRadiusFraction` (ver sección
 *   5.8 del doc) — sin esto, el ala exterior de un Cat Eye se queda plana
 *   frente a la cámara en vez de retroceder hacia adentro de la órbita
 *   como hace el párpado real.
 *
 * Eje de doblado en Y: glTF exige espacio Y-up, y los assets de este
 * proyecto están exportados con "Khronos glTF Blender I/O" (confirmado
 * leyendo el JSON de cada `.glb`), que convierte automáticamente el Z-up
 * nativo de Blender a Y-up al exportar — la garantía viene del formato + la
 * herramienta, no de mirar el modelo.
 *
 * Riesgo NO verificable sin dispositivo: el sentido (izquierda/derecha) del
 * eje X local respecto a la tangente del párpado — si está invertido, el
 * doblado queda espejado en vez de seguir la curva real (ver
 * [RawMesh.mirroredAcrossX], que ya cubre el caso confirmado de esto).
 */
object LashMeshBender {

    /**
     * Dobla [raw] y escribe el resultado en [target] — sin alocar una lista
     * nueva por frame. [target] debe venir PRE-ASIGNADO con el mismo tamaño
     * que `raw.vertices` (ver [EyeModelSlot.bufferA]/[EyeModelSlot.bufferB],
     * llenados una única vez al cargar el modelo). Si [previous] no es
     * `null`, el suavizado EMA contra el frame anterior (ver
     * [RendererConfiguration.LASH_BEND_SMOOTHING]) se funde en el MISMO
     * pase — antes eran dos pasadas separadas (doblado en esta función +
     * suavizado en `LashRenderer`), cada una construyendo un `Vertex` nuevo
     * por vértice; acá se calcula la posición/normal final una sola vez y
     * se construye 1 solo `Vertex` por vértice por frame, el mínimo posible
     * sin cambiar de API (ver límite honesto más abajo).
     *
     * `curve == null`, `eyeWidthPx <= 0` o `strength <= 0` → sin curvatura
     * adicional para este frame: copia los vértices crudos a [target] (sin
     * alocar `Vertex` nuevos, solo referencias) en vez de recorrer nada.
     *
     * **LÍMITE HONESTO de "cero asignaciones"**: `io.github.sceneview.
     * geometries.Geometry.Vertex` y `dev.romainguy.kotlin.math.Float3` son
     * INMUTABLES — todos sus campos son `val`/`final`, verificado
     * decompilando `sceneview-2.1.1-api.jar` con `javap` (no a ojo): no
     * exponen setters ni una variante mutable, solo `copy()`. No hay forma
     * de mutar un `Vertex` ya existente en el sitio sin bypassear esta API
     * por completo (manejar un `VertexBuffer`/`FloatBuffer` de Filament
     * directamente — fuera de alcance de este cambio, ver nota en el doc).
     * Lo que SÍ se elimina acá, y es lo que realmente presionaba al GC a
     * ~30Hz por ojo: (a) la `List`/`ArrayList` nueva por frame (`target` se
     * reutiliza, solo se sobreescribe por índice), y (b) la doble
     * instanciación de `Vertex` por vértice que había antes (doblado +
     * suavizado como dos `.map`/`.mapIndexed` encadenados).
     */
    fun bendInPlace(
        raw: RawMesh,
        target: MutableList<Geometry.Vertex>,
        /** Resultado ya doblado del frame anterior (buffer distinto a
         * [target] — ver double-buffer en [EyeModelSlot]), o `null` en el
         * primer doblado de este slot (sin frame previo contra el que
         * suavizar). */
        previous: List<Geometry.Vertex>?,
        /** [RendererConfiguration.LASH_BEND_SMOOTHING] — `1f` = sin
         * suavizar (equivalente a ignorar [previous]). */
        smoothing: Float,
        curve: LashLineCurve?,
        styleConfig: LashStyleConfig,
        eyeWidthPx: Float,
        /** [EyeAnchor.lashCurveAnchorOffsetPx] — ver la nota extensa en el
         * historial de este archivo / `EyeAnchorCalculator`: sin sumar
         * esto, casi todos los vértices caían fuera de `[minLocalX,
         * maxLocalX]` que `curve` realmente ajustó. */
        anchorOffsetPx: Float = 0f,
        strength: Float = RendererConfiguration.LASH_BEND_STRENGTH,
    ) {
        require(target.size == raw.vertices.size) {
            "target (${target.size}) debe tener el mismo tamaño que raw.vertices (${raw.vertices.size})"
        }

        val span = raw.maxX - raw.minX
        val canBend = curve != null && eyeWidthPx > 0f && strength > 0f && span > 1e-4f
        if (!canBend) {
            for (i in raw.vertices.indices) target[i] = raw.vertices[i]
            return
        }

        // El span local del mesh (unidades propias del .glb) corresponde al
        // ancho real del ojo en píxeles (eyeWidthPx) — de ahí la conversión
        // píxeles<->unidades locales, derivada de cantidades que YA calcula
        // el resto del pipeline, no una constante inventada.
        val meshUnitsPerPixel = span / eyeWidthPx

        // Radio de la esfera del globo ocular, como fracción de eyeWidthPx
        // (ver LashStyleConfig.zDepthDropRadiusFraction) — coerceAtLeast
        // solo por seguridad numérica (evitar división por cero con un
        // estilo mal configurado a fracción 0), no un ajuste visual.
        val radiusPx = (eyeWidthPx * styleConfig.zDepthDropRadiusFraction).coerceAtLeast(1e-3f)
        val blend = previous != null && smoothing < 1f

        for (i in raw.vertices.indices) {
            val vertex = raw.vertices[i]
            val pos = vertex.position
            val t = (pos.x - raw.minX) / span
            val pixelLocalX = (t - 0.5f) * eyeWidthPx + anchorOffsetPx

            // `strength` amortigua la desviación calculada — se escala
            // ANTES de la pendiente/normal también, así la inclinación de
            // la normal queda consistente con el desplazamiento real
            // aplicado (si no, la iluminación insinuaría más curva de la
            // que realmente se ve).
            val deviationPx = curve!!.deviationAt(pixelLocalX) * strength
            val slope = curve.slopeAt(pixelLocalX) * strength

            // Envolvente esférica en Z (sección 5.8 del doc): aproximación
            // de círculo z = R − √(R²−x²) ≈ x²/(2R) para |x| ≪ R (primer
            // término no nulo de Taylor) — una caída CUADRÁTICA derivada de
            // la geometría real de una esfera, no un valor inventado.
            // Clamp a `radiusPx` (verificado numéricamente: la aproximación
            // diverge sin límite para |x|>R, que el ala de un Cat Eye
            // alcanza de forma rutinaria) — la profundidad física máxima de
            // esa esfera es su propio radio, así que es la meseta correcta.
            val depthDropPx = ((pixelLocalX * pixelLocalX) / (2f * radiusPx)).coerceAtMost(radiusPx)
            // foxyLiftMultiplier reemplaza a LASH_BEND_DEPTH_DROP_STRENGTH
            // como el knob por-estilo — negativo invierte el sentido (lift
            // hacia +Z en vez de drop hacia -Z, ver LashStyleConfig).
            val depthDropLocal = depthDropPx * meshUnitsPerPixel * styleConfig.foxyLiftMultiplier * strength

            val bentPosition = Float3(pos.x, pos.y + deviationPx * meshUnitsPerPixel, pos.z - depthDropLocal)
            val bentNormal = tiltNormal(vertex.normal ?: DEFAULT_NORMAL, slope)

            val finalPosition = if (blend) {
                val prevPos = previous!![i].position
                Float3(
                    prevPos.x + (bentPosition.x - prevPos.x) * smoothing,
                    prevPos.y + (bentPosition.y - prevPos.y) * smoothing,
                    prevPos.z + (bentPosition.z - prevPos.z) * smoothing,
                )
            } else {
                bentPosition
            }

            target[i] = Geometry.Vertex(finalPosition, bentNormal, vertex.uvCoordinate, vertex.color)
        }
    }

    /** Rota la normal alrededor del eje Z local por `atan(slope)`. `slope`
     * es adimensional (píxeles/píxeles), así que la rotación no depende de
     * la conversión de unidades usada para la posición. */
    private fun tiltNormal(normal: Float3, slope: Float): Float3 {
        val angle = atan(slope.toDouble()).toFloat()
        val cosA = cos(angle.toDouble()).toFloat()
        val sinA = sin(angle.toDouble()).toFloat()
        val nx = normal.x * cosA - normal.y * sinA
        val ny = normal.x * sinA + normal.y * cosA
        val nz = normal.z
        val lengthSq = nx * nx + ny * ny + nz * nz
        if (lengthSq <= 0f || !lengthSq.isFinite()) return normal
        val invLength = 1f / sqrt(lengthSq)
        return Float3(nx * invLength, ny * invLength, nz * invLength)
    }

    private val DEFAULT_NORMAL = Float3(0f, 1f, 0f)
}
