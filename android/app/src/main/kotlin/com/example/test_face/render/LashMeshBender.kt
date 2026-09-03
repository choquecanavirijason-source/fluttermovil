package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.math.normalToTangent
import java.nio.FloatBuffer
import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.sin

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
 *   ([LashLineCurve]). Este asset es un ABANICO de fibras individuales, no
 *   una cinta continua; rotar cada vértice según la pendiente LOCAL de su
 *   propia columna X hace que fibras vecinas giren cantidades distintas y
 *   sus puntas se crucen/enrosquen (confirmado en dispositivo real). El
 *   shear puro (`x`/`z` intactos en este eje, solo `y' = y + desviación`)
 *   es lo correcto para este tipo de malla.
 * - **Z (envolvente esférica)**: aproximación cuadrática de una esfera de
 *   radio `eyeWidthPx · styleConfig.zDepthDropRadiusFraction` — sin esto,
 *   el ala exterior de un Cat Eye se queda plana frente a la cámara en vez
 *   de retroceder hacia adentro de la órbita como hace el párpado real.
 *
 * REESCRITO a buffer directo (ver plan): antes escribía en un
 * `MutableList<Geometry.Vertex>`, construyendo un `Geometry.Vertex`
 * (y su `Float3` de posición) NUEVO por vértice por resultado de MediaPipe
 * — eso, sumado a que `geometry.setVertices()` (SceneView) internamente
 * hacía `FloatBuffer.allocate()` nuevo + recálculo de AABB en cada llamada,
 * fue lo que causó el OOM real en dispositivo que documentaba este archivo.
 * Acá se aplica el mismo patrón ya probado en [FaceMeshRenderer]: [target]/
 * [tangentTarget] son `FloatBuffer` DIRECTOS preasignados por el llamador,
 * escritos con `put(index, valor)` absoluto — cero `Geometry.Vertex`/
 * `Float3`/`Quaternion` nuevos por vértice.
 *
 * NORMAL/TANGENTS (agregado tras confirmar en dispositivo real que dejarla
 * estática se veía como una línea negra dura junto a la pestaña — el
 * material `LashPBR` del propio `.glb` es bastante brilloso,
 * `roughness=0.42`/`specularFactor=0.9`, muy sensible a una normal que ya
 * no coincide con la superficie doblada): en vez de reconstruir la base
 * ortonormal completa (`normalToTangent`, que arma tangente/bitangente
 * desde cero con `Float3`/`Quaternion` — SÍ asigna) en cada frame, esa
 * función se llama UNA SOLA VEZ por vértice al cargar el modelo (ver
 * [computeRestTangents], costo único como parsear el `.glb`, no por frame),
 * y por frame solo se le aplica una rotación alrededor del eje Z LOCAL por
 * el mismo ángulo que ya usa el shear de posición (`atan(slope)`) —
 * multiplicación de cuaterniones en escalares puros, cerrada y barata,
 * sin reconstruir la base.
 */
object LashMeshBender {

    private const val POSITION_COMPONENTS = 3
    private const val TANGENT_COMPONENTS = 4

    /**
     * Calcula el cuaternión de tangente "de reposo" (mesh sin doblar) de
     * cada vértice — UNA sola vez, al cargar el modelo (ver
     * [LashRenderer.loadIntoSlot]), reusando [normalToTangent] tal como lo
     * hacía `Geometry.Builder` internamente. Resultado: `FloatArray` plano
     * (`vertexCount * 4`, orden x,y,z,w), insumo de [bendInPlace] para
     * rotarlo por frame sin reconstruir la base ortonormal.
     */
    fun computeRestTangents(vertices: List<io.github.sceneview.geometries.Geometry.Vertex>): FloatArray {
        val out = FloatArray(vertices.size * TANGENT_COMPONENTS)
        for (i in vertices.indices) {
            val normal = vertices[i].normal ?: DEFAULT_NORMAL
            val q = normalToTangent(normal)
            val base = i * TANGENT_COMPONENTS
            out[base] = q.x
            out[base + 1] = q.y
            out[base + 2] = q.z
            out[base + 3] = q.w
        }
        return out
    }

    /**
     * Dobla [raw] y escribe posición en [target] y tangente en
     * [tangentTarget] — sin alocar nada por vértice (ver KDoc de la clase).
     * [target]/[previous] son los `EyeModelSlot.positionBufferA`/
     * `positionBufferB` (double-buffer alternado por el llamador, para el
     * suavizado EMA de posición); [tangentTarget] es un único buffer (no
     * necesita double-buffer: no se suaviza entre frames, ver nota abajo) y
     * [restTangents] es el resultado de [computeRestTangents], constante
     * mientras el modelo esté cargado.
     *
     * La tangente NO pasa por el suavizado EMA de posición — se recalcula
     * fresca cada frame desde el `slope` de este frame. Es una
     * simplificación deliberada (evita mezclar cuaterniones, que necesita
     * slerp, no una mezcla lineal): si se nota temblor fino en el brillo
     * especular (no en la forma, que sí está suavizada), es lo próximo a
     * ajustar.
     *
     * Devuelve `false` (sin escribir nada) si `LASH_DEFORMATION_ENABLED` es
     * `false`, no hay curva para este frame, o el ancho del ojo/`strength`
     * son inválidos — el llamador no debe subir nada a GPU en ese caso (el
     * mesh queda en la última forma subida, normalmente la de reposo del
     * `.glb`, cargada una única vez al construir la `Geometry`).
     */
    fun bendInPlace(
        raw: RawMesh,
        target: FloatBuffer,
        /** Resultado ya doblado del frame anterior (buffer distinto a
         * [target] — ver double-buffer en [EyeModelSlot]), o `null` en el
         * primer doblado de este slot (sin frame previo contra el que
         * suavizar). */
        previous: FloatBuffer?,
        restTangents: FloatArray,
        tangentTarget: FloatBuffer,
        /** [RendererConfiguration.LASH_BEND_SMOOTHING] — `1f` = sin
         * suavizar (equivalente a ignorar [previous]). */
        smoothing: Float,
        curve: LashLineCurve?,
        styleConfig: LashStyleConfig,
        eyeWidthPx: Float,
        /** Fuerza dentro de `[minLocalX, maxLocalX]` — la zona con los 8
         * landmarks REALES del párpado, donde el spline es exacto y
         * monótono (sin riesgo de overshoot, ver [LashLineCurve]). `1f` =
         * fidelidad total a esos 8 puntos. */
        strength: Float = RendererConfiguration.LASH_BEND_STRENGTH,
        /** Fuerza en la extrapolación MÁS ALLÁ de los 8 puntos reales (ej.
         * la punta del ala de un Cat Eye) — zona sin datos reales, donde
         * `strength=1` uniforme confirmó distorsión en dispositivo real. La
         * transición entre [strength] y esto usa [LashLineCurve.wingBlend],
         * con derivada cero en el borde. */
        wingStrength: Float = RendererConfiguration.LASH_BEND_WING_STRENGTH,
    ): Boolean {
        val span = raw.maxX - raw.minX
        // LASH_DEFORMATION_ENABLED=false aísla el TRANSFORM (posición/
        // rotación/escala) de la DEFORMACIÓN (este doblado) para diagnóstico
        // — ver RendererConfiguration.
        val canBend = RendererConfiguration.LASH_DEFORMATION_ENABLED &&
            curve != null && eyeWidthPx > 0f && strength > 0f && span > 1e-4f
        if (!canBend) {
            if (RendererConfiguration.MESH_CALIBRATION_LOGGING) {
                android.util.Log.w(
                    "MESH_CALIB",
                    "BEND_SKIP deformationEnabled=${RendererConfiguration.LASH_DEFORMATION_ENABLED} " +
                        "curveNull=${curve == null} eyeWidthPx=$eyeWidthPx strength=$strength span=$span",
                )
            }
            return false
        }

        // El span local del mesh (unidades propias del .glb) corresponde al
        // ancho real del ojo en píxeles (eyeWidthPx) — de ahí la conversión
        // píxeles<->unidades locales, derivada de cantidades que YA calcula
        // el resto del pipeline, no una constante inventada.
        val meshUnitsPerPixel = span / eyeWidthPx

        // ── Corrección de amplificación vertical ─────────────────────
        // `meshUnitsPerPixel` asume que el span del mesh acaba midiendo
        // `eyeWidthPx` en pantalla, pero NO es así: el transform rígido lo
        // escala a `eyeWidthWorld * WIDTH_MULTIPLIER * tilt`, y además estira
        // el eje Y local por `HEIGHT_VOLUME_MULTIPLIER` aparte. Componiendo:
        //
        //   desviacionEnMundo = deviationPx * (eyeWidthWorld/eyeWidthPx)
        //                       * WIDTH_MULTIPLIER * tilt * HEIGHT_VOLUME_MULTIPLIER
        //
        // cuando lo correcto es solo `deviationPx * (eyeWidthWorld/eyeWidthPx)`
        // — la misma escala mundo-por-píxel que se usa en horizontal. O sea
        // que el arco del párpado se dibujaba 1.15 * 1.55 = 1.78x más
        // pronunciado de lo que realmente es (reportado en dispositivo: "la
        // parte central sube demasiado, no se acomoda al párpado").
        //
        // `HEIGHT_VOLUME_MULTIPLIER` existe para dar VOLUMEN a la fibra — un
        // estiramiento artístico del modelo. Que estire también el término
        // GEOMÉTRICO que sigue al párpado es el bug: la raíz tiene que caer
        // sobre el párpado real sin importar qué tan gruesa sea la pestaña.
        //
        // El factor `tilt` no se corrige acá porque el bender no lo recibe.
        // Vale 1 de frente Y al cabecear (desde el fix del eje `right` en
        // EyeTransformCalculator), o sea en todos los ángulos salvo GIRO de
        // cabeza, donde queda un residuo de hasta 2.2x. Para eliminarlo hay
        // que propagar el mundo-por-píxel real desde EyeTransform.
        val verticalUnitsPerPixel = meshUnitsPerPixel /
            (RendererConfiguration.WIDTH_MULTIPLIER * RendererConfiguration.HEIGHT_VOLUME_MULTIPLIER)
        // El eje Z se escala con `scaleFactor` (uniforme), sin
        // HEIGHT_VOLUME_MULTIPLIER — así que su exceso es solo WIDTH_MULTIPLIER.
        val depthUnitsPerPixel = meshUnitsPerPixel / RendererConfiguration.WIDTH_MULTIPLIER

        // Radio de la esfera del globo ocular, como fracción de eyeWidthPx
        // (ver LashStyleConfig.zDepthDropRadiusFraction) — coerceAtLeast
        // solo por seguridad numérica.
        val radiusPx = (eyeWidthPx * styleConfig.zDepthDropRadiusFraction).coerceAtLeast(1e-3f)
        val blend = previous != null && smoothing < 1f

        val vertices = raw.vertices
        val n = vertices.size

        // Diagnóstico temporal (ver RendererConfiguration.MESH_CALIBRATION_LOGGING)
        // — rango real de deviationPx/pixelLocalX en este doblado, para
        // confirmar con números si el doblado se está aplicando y con qué
        // magnitud, en vez de solo mirar el resultado final en pantalla.
        var minDeviationPx = Float.MAX_VALUE
        var maxDeviationPx = -Float.MAX_VALUE
        var minPixelLocalX = Float.MAX_VALUE
        var maxPixelLocalX = -Float.MAX_VALUE

        for (i in 0 until n) {
            // vertex.position es un Float3 EXISTENTE (parseado una única vez
            // al cargar el modelo, no por frame) — leer sus componentes acá
            // es solo acceso a campo, no asigna nada nuevo.
            val pos = vertices[i].position
            val t = (pos.x - raw.minX) / span
            val pixelLocalX = (t - 0.5f) * eyeWidthPx

            // Fuerza efectiva: `strength` dentro del rango con datos reales,
            // amortiguando suave y continuamente hacia `wingStrength` en la
            // extrapolación — ver [LashLineCurve.wingBlend].
            val effectiveStrength = strength - (strength - wingStrength) * curve!!.wingBlend(pixelLocalX)

            // SIGNO (fix 2026-09-03): [LashLineCurve.fit] proyecta los puntos
            // del párpado en ESPACIO DE IMAGEN, donde Y crece hacia ABAJO.
            // `pos.y` de acá abajo es Y LOCAL DEL MODELO, que crece hacia
            // ARRIBA (la raíz está en `raw.minY` y la punta en el máximo).
            // Son convenciones OPUESTAS, así que hay que negar al cruzar de
            // una a la otra.
            //
            // Sin esta negación el arco quedaba invertido: el centro del
            // párpado superior está MÁS ALTO en el rostro, o sea con Y de
            // imagen MENOR, o sea desviación NEGATIVA respecto al ancla — y
            // al sumarla a un Y que crece hacia arriba, el centro BAJABA y las
            // esquinas SUBÍAN. Resultado: la pestaña se curvaba en "U" (como
            // un párpado inferior) en vez de en "n" (el arco real del
            // párpado superior), reportado en dispositivo.
            //
            // Se niega también `slope`, que es d(localY)/d(localX) en las
            // mismas coordenadas de imagen: alimenta la rotación de la
            // tangente más abajo (`atan(slope)`), y tiene que seguir al shear
            // de posición o la normal queda peleada con la superficie
            // doblada.
            val deviationPx = -curve.deviationAt(pixelLocalX) * effectiveStrength
            val slope = -curve.slopeAt(pixelLocalX) * effectiveStrength
            if (deviationPx < minDeviationPx) minDeviationPx = deviationPx
            if (deviationPx > maxDeviationPx) maxDeviationPx = deviationPx
            if (pixelLocalX < minPixelLocalX) minPixelLocalX = pixelLocalX
            if (pixelLocalX > maxPixelLocalX) maxPixelLocalX = pixelLocalX

            // Envolvente esférica en Z: z = R − √(R²−x²) ≈ x²/(2R) para
            // |x| ≪ R (primer término no nulo de Taylor). Clamp a `radiusPx`
            // — la profundidad física máxima de esa esfera es su propio
            // radio, así que es la meseta correcta.
            val depthDropPx = ((pixelLocalX * pixelLocalX) / (2f * radiusPx)).coerceAtMost(radiusPx)
            val depthDropLocal = depthDropPx * depthUnitsPerPixel * styleConfig.foxyLiftMultiplier * strength

            val bentX = pos.x
            val bentY = pos.y + deviationPx * verticalUnitsPerPixel
            val bentZ = pos.z - depthDropLocal

            val base = i * POSITION_COMPONENTS
            if (blend) {
                // previous no-null garantizado por `blend` — !! es solo para
                // el compilador, nunca lanza en este camino.
                val prevX = previous!!.get(base)
                val prevY = previous.get(base + 1)
                val prevZ = previous.get(base + 2)
                target.put(base, prevX + (bentX - prevX) * smoothing)
                target.put(base + 1, prevY + (bentY - prevY) * smoothing)
                target.put(base + 2, prevZ + (bentZ - prevZ) * smoothing)
            } else {
                target.put(base, bentX)
                target.put(base + 1, bentY)
                target.put(base + 2, bentZ)
            }

            // Tangente: rotar el cuaternión DE REPOSO (precalculado, ver
            // computeRestTangents) alrededor del eje Z local por `angle`,
            // mismo ángulo que el shear de posición — multiplicación de
            // cuaterniones cerrada (q_tilt * q_rest), sin reconstruir la
            // base tangente/bitangente/normal desde cero. q_tilt = rotación
            // alrededor de Z: (x=0, y=0, z=sin(angle/2), w=cos(angle/2)) —
            // con x=y=0 el producto de Hamilton se simplifica a esto:
            val angle = atan(slope)
            val half = angle * 0.5f
            val sinHalf = sin(half)
            val cosHalf = cos(half)
            val tb = i * TANGENT_COMPONENTS
            val rx = restTangents[tb]
            val ry = restTangents[tb + 1]
            val rz = restTangents[tb + 2]
            val rw = restTangents[tb + 3]
            tangentTarget.put(tb, cosHalf * rx - sinHalf * ry)
            tangentTarget.put(tb + 1, cosHalf * ry + sinHalf * rx)
            tangentTarget.put(tb + 2, cosHalf * rz + sinHalf * rw)
            tangentTarget.put(tb + 3, cosHalf * rw - sinHalf * rz)
        }
        if (RendererConfiguration.MESH_CALIBRATION_LOGGING) {
            android.util.Log.i(
                "MESH_CALIB",
                "BEND_APPLIED n=$n eyeWidthPx=%.2f meshUnitsPerPixel=%.6f pixelLocalX=[%.2f,%.2f] deviationPx=[%.2f,%.2f]".format(
                    eyeWidthPx, meshUnitsPerPixel, minPixelLocalX, maxPixelLocalX, minDeviationPx, maxDeviationPx,
                ),
            )
        }
        return true
    }

    private val DEFAULT_NORMAL = Float3(0f, 1f, 0f)
}
