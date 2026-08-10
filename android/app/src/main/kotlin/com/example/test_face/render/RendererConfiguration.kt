package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3

/**
 * Parámetros del motor de render optimizados para LATENCIA MÍNIMA.
 *
 * Filosofía: el One Euro Filter SOLO debe eliminar el micro-jitter de
 * MediaPipe, sin agregar lag perceptible. La predicción forward en
 * PoseInterpolator se encarga del resto de la compensación.
 *
 * El minCutoff alto (3.0Hz) hace que el filtro sea casi transparente:
 * señales que cambian más lento que 3Hz (movimiento lento de cabeza)
 * pasan sin casi ningún suavizado → CERO lag perceptible.
 */
object RendererConfiguration {

    // ── One Euro Filter: MÍNIMO suavizado, MÁXIMA velocidad ─────────────
    //
    // Con predicción forward adaptativa, el filtro ya NO necesita compensar
    // la latencia — solo necesita limpiar el ruido de MediaPipe.
    //
    // minCutoff = 3.0Hz → τ ≈ 53ms en reposo (solo limpia jitter)
    // Target rápido = 25Hz → τ ≈ 6.4ms (sub-frame, invisible)
    //
    // Comparación con antes:
    // - Antes: minCutoff=1.0, target=12Hz → lag de ~100ms visible
    // - Ahora: minCutoff=3.0, target=25Hz → lag de ~6ms invisible
    const val ONE_EURO_D_CUTOFF = 1.0f

    private const val FAST_MOTION_TARGET_CUTOFF_HZ = 25f

    const val POSITION_MIN_CUTOFF = 3.0f
    private const val FAST_MOTION_POSITION_VELOCITY_MPS = 1.0f
    const val POSITION_BETA =
        (FAST_MOTION_TARGET_CUTOFF_HZ - POSITION_MIN_CUTOFF) / FAST_MOTION_POSITION_VELOCITY_MPS

    const val ROTATION_MIN_CUTOFF = 2.0f
    private const val FAST_MOTION_ROTATION_VELOCITY = 1.8f
    const val ROTATION_BETA =
        (FAST_MOTION_TARGET_CUTOFF_HZ - ROTATION_MIN_CUTOFF) / FAST_MOTION_ROTATION_VELOCITY

    const val SCALE_MIN_CUTOFF = 2.0f
    private const val SCALE_TO_POSITION_BETA_RATIO = 0.05f / 0.3f
    const val SCALE_BETA = POSITION_BETA * SCALE_TO_POSITION_BETA_RATIO

    // ── Profundidad ─────────────────────────────────────────────────────
    const val MIN_DEPTH = -2.2f
    const val MAX_DEPTH = -0.35f
    const val FACE_DISTANCE_MULTIPLIER = 1.0f

    // ── Escala del modelo ───────────────────────────────────────────────
    const val WIDTH_MULTIPLIER = 1.8f
    // HEIGHT_OFFSET controla dónde queda la RAÍZ real de la pestaña 3D
    // (EyeModelSlot.rootLocalY, ver EyeTransformCalculator) respecto al
    // BORDE del párpado superior (la línea donde nace la pestaña real).
    //
    // 0.0 = raíz exactamente en el borde del párpado (valor por defecto —
    //       anatómicamente correcto: una extensión de pestañas se pega justo
    //       sobre la línea de pestañas real, sin margen)
    // >0  = raíz desplazada hacia ARRIBA esa fracción de la altura del ojo
    //       (margen de "flote"/glue visible, si hiciera falta por estética)
    //
    // IMPORTANTE (corrección 2026-07-24): antes este offset se aplicaba
    // sobre el CENTRO GEOMÉTRICO del bounding box del modelo (asumiendo que
    // el .glb estaba centrado en su raíz visual), en 0.30 — pero se verificó
    // con los 10 modelos reales de assets/modelos/ (histograma de densidad
    // de vértices en Y) que la raíz visual de cada pestaña está muy por
    // debajo del centro geométrico del bounding box, cerca de su Y mínimo.
    // Ancorar el centro (en vez de la raíz real) + este offset extra
    // empujaba la pestaña sistemáticamente hacia la ceja, en cualquier
    // ángulo de cabeza — justo el síntoma reportado con capturas reales.
    // Ahora EyeTransformCalculator ancla EyeModelSlot.rootLocalY (la raíz
    // real, medida del mesh) directamente al punto de anclaje del ojo, así
    // que este offset vuelve a tener el significado simple y literal de su
    // nombre. 0.0f es el punto de partida teóricamente correcto — falta
    // confirmar visualmente en dispositivo real (no disponible en este
    // entorno) y ajustar solo si hace falta un pequeño margen estético.
    // Ajuste 2026-08-02: reportado en dispositivo real que la raíz quedaba
    // un poco por ENCIMA de la línea de pestañas real (0.0 usa el centroide
    // del párpado superior, que por promediar todo el arco queda algo más
    // arriba que el punto más bajo visible en la mayor parte del ancho del
    // ojo). Negativo = baja el ancla (suma a meanY en vez de restar).
    // Ajuste 2026-08-08 (calibración fina, con el envolvente en Z de 5.8 ya
    // confirmado funcionando): se probó -0.05 (sección 5.11) razonando que
    // "menos negativo = menos agresivo" — INCORRECTO: por la convención de
    // signos de esta fórmula, menos negativo es MENOS corrección hacia
    // abajo, no menos "agresividad" hacia arriba. Confirmado con captura de
    // cámara real recortada/ampliada (`adb screencap` + `ffmpeg crop`): con
    // -0.05 la raíz queda claramente por ENCIMA del borde visible del
    // párpado, con un espacio de piel de por medio en los dos ojos. Subido
    // (más negativo) a -0.22 para cerrar ese espacio.
    //
    // Ajuste 2026-08-10 (sección 5.15): el usuario marcó con una línea verde,
    // sobre una foto real, dónde debe caer la línea de pestañas (justo sobre
    // el borde del párpado, cerca del iris) — con -0.22 la raíz seguía
    // renderizando claramente por ENCIMA de esa línea, con piel de por medio
    // en los dos ojos (la misma clase de hueco que motivó el ajuste
    // anterior, solo que insuficiente). Subido (más negativo) a -0.38.
    const val HEIGHT_OFFSET = -0.38f
    const val HEAD_TILT_MULTIPLIER = 1.0f
    // Multiplicador SOLO sobre el eje Y local del modelo (además del
    // scaleFactor isotrópico que ya iguala el ancho al ojo real) — le da
    // más volumen/grosor vertical a la pestaña sin estirarla más allá de
    // las esquinas del ojo en X (que es lo que pasaría si en cambio se
    // subiera WIDTH_MULTIPLIER, porque ese escala X/Y/Z por igual). 1.0 =
    // sin cambio. Ver EyeTransformCalculator: también se usa (no solo
    // WIDTH_MULTIPLIER×scaleFactor) para el desplazamiento de rootLocalY,
    // porque ese desplazamiento es a lo largo del mismo eje Y que ahora
    // tiene esta escala extra.
    const val HEIGHT_VOLUME_MULTIPLIER = 1.55f

    // ── Corrección por ojo ──────────────────────────────────────────────
    const val RIGHT_EYE_X_NUDGE = 0.0f
    const val LEFT_EYE_X_NUDGE = 0.0f

    // Con WIDTH_MULTIPLIER=1.65 el modelo se agranda simétricamente desde
    // el centro del ojo — pero el lado interno (hacia la nariz/lagrimal)
    // tiene mucho menos espacio anatómico libre que el lado externo (hacia
    // la sien), así que esa misma expansión simétrica invade la nariz de
    // un lado y se ve bien del otro (reportado en dispositivo real,
    // 2026-07-24). NOSE_AVOID_SHIFT desplaza el ancla X, como fracción del
    // ancho del ojo, hacia el corner EXTERNO (el más lejano al centro
    // horizontal de la imagen — ver EyeAnchorCalculator) para reducir el
    // invasión del lado interno sin tocar la escala. 0.0 = sin desplazar.
    const val NOSE_AVOID_SHIFT = 0.68f

    // CORRECCIÓN 2026-08-08: reportado en dispositivo real que el conjunto
    // de pestañas sigue quedando visiblemente más cerca del canto medial/
    // lagrimal de lo esperado, incluso con NOSE_AVOID_SHIFT ya activo.
    // Causa: NOSE_AVOID_SHIFT desplaza SOLO en el eje X de la imagen (un
    // signo × una magnitud escalar), no a lo largo de la dirección real
    // canto-medial→canto-lateral — con la cabeza en roll (inclinada de
    // costado), esa dirección real tiene una componente en Y que el
    // desplazamiento puramente horizontal no cubre, así que el ancla queda
    // corta respecto al eje verdadero del ojo.
    //
    // LATERAL_LASH_OFFSET es una corrección ADICIONAL (no reemplaza a
    // NOSE_AVOID_SHIFT, se suma encima) calculada como vector real:
    // `normalize(canthusLateral - canthusMedial) * (distancia(canthus) ×
    // LATERAL_LASH_OFFSET)` — ver EyeAnchorCalculator.compute(). Al ser
    // proporcional a la distancia REAL entre los dos cantos (no un valor
    // fijo en píxeles ni un desplazamiento en espacio de mundo), escala
    // solo con el tamaño del ojo en la imagen — el mismo mecanismo de
    // des-proyección real que ya usa el resto del ancla (ver
    // EyeTransformCalculator) se encarga de que sea correcto a cualquier
    // distancia de cámara, no hace falta ningún ajuste aparte por
    // perspectiva.
    //
    // 0.0 = sin corrección adicional (comportamiento anterior). Positivo =
    // empuja más hacia el canto LATERAL/temporal.
    //
    // Ajuste 2026-08-08 (feedback en dispositivo real, mismo día,
    // iterativo): 0.08 → correcto pero insuficiente ("sigue alejado del
    // canto externo") → 0.16 → SIGUE insuficiente → 0.28 → SOBRE-CORRIGE
    // (la punta del ala se pasaba del canto lateral real hacia la sien/
    // nacimiento del pelo, visible en captura recortada/ampliada) → 0.20.
    //
    // CONFIRMADO en dispositivo real (Infinix X669) con 0.20: captura
    // recortada/ampliada de los dos ojos — el ala queda CONTENIDA dentro
    // del contorno real del ojo en ambos (ni se pasa hacia la sien ni deja
    // hueco en el lagrimal), simétrico entre los dos ojos, sin pico ni
    // deformación.
    //
    // REVISADO 2026-08-10: con dispositivo real disponible de nuevo (mismo
    // Infinix X669), captura fresca (`adb screencap`) recortada con grid de
    // referencia en píxeles mostró que 0.20 deja un ojo bien contenido
    // (margen ~7px hacia el canto lateral) pero el OTRO ojo con un hueco
    // real de ~95px entre la punta del ala y el canto lateral real — no un
    // desajuste menor. Confirma lo que la sección 5.13 ya dejaba anotado
    // como sospecha sin resolver ("probablemente por pose, no
    // necesariamente asimetría de código"): la magnitud de este caso
    // (95px vs 7px con la MISMA fórmula/constante en los dos ojos) es
    // grande para explicarse solo por ruido de landmarks. Subido a 0.30
    // como paso intermedio.
    //
    // Ajuste 2026-08-10 (sección 5.15): con 0.30, el usuario marcó con
    // flechas sobre una foto real que TODAVÍA queda un hueco visible entre
    // la punta del ala y el canto lateral real, en los DOS ojos esta vez
    // (no uno solo como en la ronda anterior). Subido a 0.38.
    const val LATERAL_LASH_OFFSET = 0.38f

    // ── Parpadeo ────────────────────────────────────────────────────────
    const val EYE_CLOSED_OPENNESS_THRESHOLD = 0.12f
    const val EYE_OPEN_OPENNESS_THRESHOLD = 0.22f

    // ── Iluminación ─────────────────────────────────────────────────────
    const val INDIRECT_LIGHT_INTENSITY = 15000f
    const val KEY_LIGHT_INTENSITY = 100000f
    val KEY_LIGHT_COLOR = Float3(1f, 0.97f, 0.90f)
    val KEY_LIGHT_DIRECTION = Float3(-0.35f, -0.7f, -0.6f)

    // ── Calidad de render ───────────────────────────────────────────────
    const val MSAA_SAMPLE_COUNT = 4

    // ── Doblado de pestaña según curva del párpado (LashMeshBender) ──────
    // Reconstruir la malla (List<Geometry.Vertex>, 17k-85k objetos según el
    // diseño) y subirla a GPU vía geometry.setVertices() es caro: hacerlo en
    // CADA resultado de MediaPipe (~30Hz+) causó un OutOfMemoryError real en
    // dispositivo (GC bloqueando 600-850ms seguidos — ver ESTADO_ACTUAL.md
    // sección 3.4). Este intervalo limita a cuántas veces por segundo como
    // MÁXIMO se permite recalcular el doblado, independiente de la
    // frecuencia real de MediaPipe — reduce la basura generada por segundo
    // en la misma proporción. 120ms ≈ 8.3 Hz: la curva del párpado cambia
    // lento respecto al movimiento de cabeza (que ya tiene su propio
    // suavizado/predicción vía PoseInterpolator, no depende de esto), así
    // que a esta tasa no debería notarse como "atrasado", solo menos fluido
    // que 60Hz. Si en dispositivo real esto SIGUE generando presión de GC
    // visible, subir este valor (menos Hz) antes de tocar el resto —
    // primera palanca de ajuste, no hace falta tocar LashMeshBender.
    // Subido de 120ms a 220ms (2026-07-29): con el doblado REACTIVADO en
    // dispositivo real (no solo el diagnóstico) apareció lag notorio — cada
    // recalculo reconstruye una List<Geometry.Vertex> de miles de objetos y
    // la sube a GPU vía setVertices() en el hilo principal; a 8.3Hz por CADA
    // ojo (hasta ~16.6 subidas/seg combinadas) eso satura el hilo principal.
    // ~4.5Hz por ojo sigue siendo imperceptible como "atraso" (la curva del
    // párpado cambia lento respecto al movimiento de cabeza, que tiene su
    // propio suavizado vía PoseInterpolator) pero reduce el trabajo de GPU
    // upload/GC a poco más de la mitad. Ver también EyeModelSlot.bendPending,
    // que evita que se seguya encolando trabajo si el hilo principal ya va
    // atrasado.
    const val LASH_BEND_MIN_INTERVAL_NANOS = 220_000_000L

    // Multiplicador de intensidad del doblado (0 = recto, 1 = la curva
    // calculada tal cual).
    //
    // CORRECCIÓN 2026-08-02 (BEND_DIAG_3): el valor anterior (0.25f) se
    // había calibrado el 2026-07-29 para tapar una desviación "de magnitud
    // mayor a la que se ve bien en pantalla" — pero esa medición se hizo
    // CON el bug de desalineación de coordenadas todavía presente (ver
    // EyeAnchorCalculator.lashCurveAnchorOffsetPx / LashMeshBender): la
    // mayoría de los vértices se muestreaban fuera del rango real ajustado
    // por LashLineCurve.fit() y caían en la extrapolación LINEAL de borde,
    // no en la parábola — así que ese "hasta ~30% del ancho del modelo" no
    // era curvatura anatómica real, era el artefacto del bug. Con el origen
    // de la curva ya corregido (ajustada contra `lidCenter`, no contra el
    // ancla desplazada por NOSE_AVOID_SHIFT), 0.25f amortigua CUATRO VECES
    // una señal que ya no es la misma que cuando se calibró ese número — el
    // resultado es una curva casi invisible, que es justo el síntoma
    // reportado ("las pestañas no se arquean").
    //
    // Subido a 1.0f (sin amortiguar) como punto de partida para volver a
    // calibrar desde cero en dispositivo real. Para ajustar: mirar en
    // logcat (tag "LashRenderer") la línea `bendApply ... deviationSample=`
    // — es curve.deviationAt(0f) en píxeles de imagen, SIN aplicar todavía
    // `strength` ni la conversión a unidades del mesh. Si el arco se ve
    // MUY exagerado/inestable, bajar este número; si sigue plano, el
    // problema ya no está acá (revisar minLocalX/maxLocalX del log o el
    // riesgo de espejado de eje X documentado en LashMeshBender).
    //
    // Ajuste 2026-08-08 (calibración fina, con el envolvente en Z ya
    // confirmado funcionando): con 1.0f el ala exterior de Cat Eye seguía
    // con una leve tendencia a levantarse hacia la ceja en las puntas.
    // Bajado a 0.5f para amortiguar la parábola vertical (menos agresiva en
    // los extremos, donde `deviationAt` alcanza sus valores más altos) sin
    // aplanarla del todo — pendiente de confirmar en dispositivo, ver
    // sección 5.11.
    const val LASH_BEND_STRENGTH = 0.5f

    /**
     * Suavizado temporal (EMA) del doblado, en posición Y ya deformada —
     * NO de los coeficientes a/b/c de [LashLineCurve]. Diagnosticado en
     * dispositivo real (2026-07-31, logs `bendCheck`/`bendApply`): la curva
     * recalculada desde cero en cada resultado de MediaPipe saltaba fuerte
     * frame a frame (~1px a ~12px de desviación con el rostro quieto) — puro
     * ruido de landmarks amplificado por el ajuste cuadrático, sin filtrar
     * (a diferencia de posición/rotación/escala, que sí pasan por
     * [EyeTrackingFilter]). Visualmente esto se veía como que la pestaña
     * "no se adaptaba" al párpado — en realidad temblaba en vez de asentarse
     * en una curva estable. `1f` = sin suavizado (valor nuevo tal cual);
     * valores bajos = más estable pero más lento en alcanzar la forma real.
     */
    const val LASH_BEND_SMOOTHING = 0.3f

    // ── Envolvente de curvatura del párpado (LashLineCurve/LashMeshBender) ──
    //
    // Multiplicador sobre el ancho real ajustado (`maxLocalX - minLocalX`)
    // que define la distancia de transición en la que la pendiente del
    // borde decae a cero (ver `LashLineCurve.falloffDistancePx`) — antes
    // `0.5f` (la mitad del ancho ajustado).
    //
    // CORRECCIÓN 2026-08-08 (hipótesis, sin confirmar): reportado en
    // dispositivo real que el ala se despega hacia la comisura exterior en
    // estilos "wing" (Cat Eye) — la hipótesis era que la mayoría de esos
    // vértices caían fuera de `[minLocalX, maxLocalX]` y chocaban con la
    // meseta casi de inmediato. Subir el multiplicador a 1.75 alarga esa
    // zona de transición.
    //
    // REVERTIDO 2026-08-08 (mismo día, confirmado en dispositivo real,
    // Infinix X669): con 1.75 la pestaña se ve MUCHO peor que antes — la
    // punta sale disparada en diagonal hacia la ceja/frente en vez de
    // seguir el párpado, en ambos ojos por igual (capturado con `adb
    // screencap` + logcat en vivo). Causa más probable: `edgeSlope ×
    // falloffDist × 0.5` (el techo de la meseta en `deviationAt`, ver
    // `LashLineCurve`) crece proporcional a `falloffDist`, así que
    // multiplicar el ancho de la zona de transición por 3.5× (0.5→1.75)
    // también multiplica la meseta ~3.5× — con un `edgeSlope` no trivial en
    // el borde del rango fitteado (normal en un párpado real), eso es
    // suficiente para disparar la punta del ala muy por encima de donde
    // debería quedar. Vuelto a `0.5f` (el valor confirmado funcionando en
    // 5.5/5.6/5.7, antes de este experimento) hasta poder recalibrar con
    // captura en vivo en vez de a ciegas.
    const val LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER = 0.5f

    // Fuerza de la envolvente en Z (profundidad) que hace que la pestaña
    // retroceda hacia adentro de la órbita a medida que se aleja del centro
    // del ojo, en vez de quedar plana frente a la cámara — ver
    // `LashMeshBender.bendInPlace()`. 0 = sin envolvente (Z intacto); 1 =
    // la aproximación cuadrática de una esfera de radio `eyeWidthPx/2` sin
    // amortiguar. Desde la sección 5.9 del doc (`LashStyleConfig`), este
    // valor es solo el DEFECTO de `LashStyleConfig.foxyLiftMultiplier` — el
    // knob real por-estilo vive ahí, no acá.
    //
    // APAGADO 2026-08-08 (confirmado en dispositivo real, Infinix X669,
    // mismo día que se agregó): con `1.0f` la pestaña salía deformada en
    // ambos ojos — no fue posible aislar en el momento si el causante
    // principal era esto o `LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER` (ver esa
    // constante, también revertida el mismo día), así que se apagaron los
    // DOS efectos nuevos a la vez para volver al último estado confirmado
    // bueno (5.1-5.7) en vez de seguir ajustando a ciegas sin poder ver el
    // resultado en tiempo real. `radiusPx = eyeWidthPx × fracción` acota el
    // PIXEL crudo, pero convertido a unidades locales del mesh
    // (`× meshUnitsPerPixel`) puede seguir siendo grande respecto al propio
    // espesor en Z de un mesh de pestaña (una tarjeta casi plana) — sospecha
    // sin confirmar todavía, pendiente de aislar con captura en vivo antes
    // de reactivar. `0f` = comportamiento idéntico a antes de la sección 5.8
    // (solo shear en Y, sin envolvente en Z).
    const val LASH_BEND_DEPTH_DROP_STRENGTH = 0.0f
}