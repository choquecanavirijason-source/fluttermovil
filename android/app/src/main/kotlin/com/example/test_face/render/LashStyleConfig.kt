package com.example.test_face.render

/**
 * Parámetros de ajuste que legítimamente varían ENTRE ESTILOS artísticos
 * del catálogo (Cat Eye, Wispy, Natural, Mega-Volumen...), a diferencia de
 * las constantes de [RendererConfiguration] — esas documentan calibración
 * física/de dispositivo (filtros de suavizado, MSAA, umbrales de parpadeo)
 * que no depende de qué diseño eligió la usuaria. Antes de esto,
 * `EyeAnchorCalculator`/`LashMeshBender` leían `RendererConfiguration.
 * HEIGHT_OFFSET`/`NOSE_AVOID_SHIFT`/etc. como `const val` fijos — correcto
 * mientras solo existía un estilo, pero un Cat Eye (delineado dramático,
 * ala extendida) y un Wispy (natural, sin ala) necesitan valores distintos
 * de forma legítima, no por bug de calibración.
 *
 * [LashRenderer] mantiene la instancia activa (una por sesión — el mismo
 * diseño se aplica a ambos ojos, la asimetría izq/der ya la resuelve
 * [RawMesh.mirroredAcrossX] por separado) y la pasa hacia abajo por todo el
 * pipeline (`FaceRenderPipeline` → `EyeAnchorCalculator`, `LashMeshBender`).
 */
data class LashStyleConfig(
    /** Ver [RendererConfiguration.HEIGHT_OFFSET] — mismo significado
     * (fracción de la altura del ojo, negativo = baja el ancla), pero por
     * estilo: un delineado dramático necesita la raíz visiblemente más
     * arriba del borde real del párpado; uno natural, prácticamente pegado
     * a la línea de pestañas real. */
    val heightOffset: Float = RendererConfiguration.HEIGHT_OFFSET,
    /** Ver [RendererConfiguration.NOSE_AVOID_SHIFT] — mismo significado
     * (fracción del ancho del ojo, desplazamiento hacia la esquina
     * externa). Un Cat Eye (ala larga hacia la sien) necesita un shift
     * mayor que un estilo redondo/natural, centrado sobre el ojo. */
    val noseAvoidShift: Float = RendererConfiguration.NOSE_AVOID_SHIFT,
    /** Radio de la envolvente esférica en Z (ver
     * [LashMeshBender.bendInPlace], sección 5.8 del doc), como FRACCIÓN de
     * `eyeWidthPx` — no un radio absoluto en píxeles, para seguir
     * escalando con el tamaño real del ojo en cualquier dispositivo/
     * distancia de cámara, igual que el resto del pipeline. `0.5` = radio
     * = mitad del ancho del ojo (el punto de partida "natural"); valores
     * menores = esfera más chica = abrazo más cerrado/extremo en la sien
     * (más caída en Z para el mismo `pixelLocalX`, porque `depthDropPx =
     * pixelLocalX² / (2·radio)` crece al achicar el radio). */
    val zDepthDropRadiusFraction: Float = 0.5f,
    /** Multiplica la caída en Z ya calculada — reemplaza a
     * `RendererConfiguration.LASH_BEND_DEPTH_DROP_STRENGTH` como el knob
     * POR ESTILO (esa constante global queda como el valor por defecto
     * acá, no se lee más directamente desde `LashMeshBender`). `1.0` = tal
     * cual (retrocede hacia -Z, "abraza" el globo ocular); `0.0` = sin
     * envolvente (Z intacto); NEGATIVO invierte el sentido (empuja hacia
     * +Z — un "lift" en vez de un "drop": el efecto que un estilo tipo
     * "TikTok lift" necesita en el ala exterior, levantándola hacia la
     * cámara en vez de retroceder hacia adentro de la órbita). */
    val foxyLiftMultiplier: Float = RendererConfiguration.LASH_BEND_DEPTH_DROP_STRENGTH,
    /** Ver [RendererConfiguration.LATERAL_LASH_OFFSET] — corrección
     * ADICIONAL (se suma a [noseAvoidShift], no lo reemplaza) a lo largo de
     * la dirección real canto-medial→canto-lateral, como fracción de la
     * distancia real entre ambos cantos. Un Cat Eye con ala muy extendida
     * podría necesitar más corrección lateral que un estilo redondo. */
    val lateralLashOffset: Float = RendererConfiguration.LATERAL_LASH_OFFSET,
) {
    companion object {
        /** Estilo neutro — mismos valores que las constantes globales de
         * `RendererConfiguration` que existían antes de este sistema
         * (comportamiento idéntico si no se selecciona ningún estilo). */
        val DEFAULT = LashStyleConfig()

        // Los tres presets de abajo son puntos de PARTIDA (los valores
        // citados en la tarea de diseño), no medidos en dispositivo real —
        // mismo estatus que cualquier constante nueva de este motor sin
        // calibrar todavía (ver RendererConfiguration.HEIGHT_OFFSET para el
        // historial de cómo se calibra este tipo de valor: se ajusta en
        // dispositivo real y se documenta el resultado, no se asume).

        // NEUTRALIZADOS 2026-08-08 (confirmado en dispositivo real, Infinix
        // X669, el mismo día que se agregaron): con los valores originales
        // (heightOffset/noseAvoidShift alejados de los confirmados en
        // RendererConfiguration + foxyLiftMultiplier>0 activando la
        // envolvente en Z) la pestaña salía visiblemente deformada en los
        // dos ojos — captura + logcat en vivo. En vez de seguir ajustando
        // estos 4 números a ciegas (ya causó dos regresiones el mismo día:
        // ver LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER/LASH_BEND_DEPTH_DROP_STRENGTH
        // en RendererConfiguration), los 3 presets quedan IDÉNTICOS a
        // [DEFAULT] (los valores YA confirmados funcionando en 5.1-5.7) —
        // la arquitectura de estilos queda lista, pero sin diferenciación
        // real hasta poder calibrar cada preset con captura en vivo, uno a
        // la vez, en vez de los 4 parámetros juntos y sin ver el resultado.

        /** Delineado dramático, ala extendida hacia la sien. Pendiente de
         * calibrar (ver nota arriba) — hoy idéntico a [DEFAULT]. */
        val CAT_EYE = LashStyleConfig()

        /** Redondo/natural, sin ala, pegado a la línea de pestañas real.
         * Pendiente de calibrar — hoy idéntico a [DEFAULT]. */
        val NATURAL = LashStyleConfig()

        /** Fibras finas/dispersas. Pendiente de calibrar — hoy idéntico a
         * [DEFAULT]. */
        val WISPY = LashStyleConfig()

        private val BY_ID = mapOf(
            "cateye" to CAT_EYE,
            "natural" to NATURAL,
            "wispy" to WISPY,
        )

        /**
         * Resuelve el [LashStyleConfig] para un `styleId` enviado desde
         * Flutter (ver [LashRenderer.setStyle]). `null`/desconocido →
         * [DEFAULT] — un estilo sin registrar no debe romper el render, solo
         * perder su ajuste fino particular (degradación segura, mismo
         * criterio que el resto del pipeline ante datos faltantes/
         * inesperados).
         *
         * NOTA: hoy es un registro fijo de 3 presets — el catálogo real
         * (`design.id` del backend, ver `eye_tracking_page.dart`) puede
         * tener más diseños que un id de estilo genérico no cubre. Si el
         * backend termina exponiendo estos 4 parámetros por diseño, el
         * camino natural es reemplazar este mapa fijo por una lookup
         * data-driven (ej. recibir el `LashStyleConfig` completo desde
         * Dart en vez de solo un id) — fuera de alcance mientras el
         * backend no tenga ese esquema.
         */
        fun forStyleId(styleId: String?): LashStyleConfig =
            styleId?.let { BY_ID[it.lowercase()] } ?: DEFAULT
    }
}
