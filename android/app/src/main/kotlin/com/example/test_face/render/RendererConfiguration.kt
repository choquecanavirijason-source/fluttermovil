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

    // ── One Euro Filter: balance estabilidad/respuesta ──────────────────
    //
    // PROBLEMA resuelto: con minCutoff=3.0Hz el filtro era casi transparente
    // y el jitter de MediaPipe pasaba directo al modelo, causando movimiento
    // errático ("pestañas locas"). Con 1.8Hz hay suficiente suavizado para
    // limpiar el jitter sin agregar lag visible en movimiento normal.
    //
    // minCutoff = 1.8Hz → τ ≈ 88ms en reposo (suaviza jitter de landmarks)
    // Target rápido = 20Hz → τ ≈ 8ms (movimiento rápido responde bien)
    const val ONE_EURO_D_CUTOFF = 1.0f

    private const val FAST_MOTION_TARGET_CUTOFF_HZ = 20f

    const val POSITION_MIN_CUTOFF = 1.8f
    private const val FAST_MOTION_POSITION_VELOCITY_MPS = 1.0f
    const val POSITION_BETA =
        (FAST_MOTION_TARGET_CUTOFF_HZ - POSITION_MIN_CUTOFF) / FAST_MOTION_POSITION_VELOCITY_MPS

    const val ROTATION_MIN_CUTOFF = 1.5f
    private const val FAST_MOTION_ROTATION_VELOCITY = 1.5f
    const val ROTATION_BETA =
        (FAST_MOTION_TARGET_CUTOFF_HZ - ROTATION_MIN_CUTOFF) / FAST_MOTION_ROTATION_VELOCITY

    const val SCALE_MIN_CUTOFF = 1.5f
    private const val SCALE_TO_POSITION_BETA_RATIO = 0.05f / 0.3f
    const val SCALE_BETA = POSITION_BETA * SCALE_TO_POSITION_BETA_RATIO

    // ── Profundidad ─────────────────────────────────────────────────────
    const val MIN_DEPTH = -2.2f
    const val MAX_DEPTH = -0.35f
    const val FACE_DISTANCE_MULTIPLIER = 1.0f

    // ── Escala del modelo ───────────────────────────────────────────────
    // 1.15f (2026-09-02): medido con el overlay de landmarks en dispositivo,
    // el ojo real da W=44px y con 1.8f el modelo se renderizaba a 79px — un
    // 80% más ancho que el ojo, desbordando por ambas esquinas. Ese desborde
    // hacia el lagrimal es lo que se leía como "corrida a la nariz", y es lo
    // que NOSE_AVOID_SHIFT intentaba tapar empujando todo hacia la sien en
    // vez de corregir la causa. 1.15 = apenas más ancho que el ojo, que es
    // como se ve una extensión real (sobresale un poco en la esquina externa).
    const val WIDTH_MULTIPLIER = 1.15f
    // HEIGHT_OFFSET = 0.12: mueve el ancla 12% de la altura del ojo hacia arriba
    // desde el centroide. Como rootLocalY=0 (centro del modelo en el ancla),
    // esto sitúa el centro del modelo en la línea real de pestañas (borde inferior
    // del párpado superior, donde nacen las pestañas reales).
    // 2026-09-03: pasa de -0.15f a 0f. Con la fórmula
    // `anchorY = meanY - height * HEIGHT_OFFSET` y la Y de imagen creciendo
    // hacia abajo, un valor NEGATIVO BAJA el ancla — -0.15f la hundía un 15%
    // del alto del ojo por debajo del arco del párpado superior. Junto con el
    // canto que se coló en `EyeLandmarks.upperLid` (ver el fix 9..15 ahí),
    // eran los dos términos que metían la pestaña en la parte de abajo del
    // ojo, reportado en dispositivo con una marca de dónde debía ir.
    //
    // 0f = el ancla cae EXACTAMENTE en el centroide de los 7 puntos del arco
    // del párpado superior (173,157,158,159,160,161,246), que es la línea de
    // pestañas real — donde se pega una extensión. No es un valor elegido a
    // ojo: es la ausencia de desplazamiento artificial.
    //
    // Para mover desde acá: POSITIVO sube (hacia la ceja), NEGATIVO baja
    // (hacia el centro del ojo). La magnitud es fracción del alto del ojo, o
    // sea escala sola con la distancia a la cámara.
    //
    // (El valor anterior se había restaurado el 2026-09-02 como "la
    // configuración que funcionaba bien", pero eso fue medido cuando
    // `upperLid` todavía incluía el canto y arrastraba `meanY` hacia abajo:
    // compensaba un bug que ahora ya no existe.)
    const val HEIGHT_OFFSET = 0.0f
    const val HEAD_TILT_MULTIPLIER = 1.0f

    /**
     * Grados que la pestaña se levanta hacia ADELANTE (fuera de la cara)
     * desde el plano del párpado — ver [EyePlaneCalculator].
     *
     * 0f = el abanico queda plano contra el párpado, que es como estaba: de
     * frente se ve bien, pero desde abajo queda de canto y se proyecta como
     * una rayita. Una pestaña real nace en la línea y se levanta, por eso
     * desde abajo se ve MÁS.
     *
     * 30f es un punto de partida, NO un valor calibrado en dispositivo:
     * subir si desde abajo todavía se ve plana; bajar si de frente empieza a
     * verse despegada del párpado o demasiado hacia la cámara.
     */
    const val LASH_FORWARD_TILT_DEGREES = 0f
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

    // NOSE_AVOID_SHIFT = 0: sin desplazamiento horizontal del ancla.
    // El centro del modelo va exactamente sobre el centroide de los puntos verdes.
    // A 0f (2026-09-02): con el overlay de debug de landmarks activado se vio
    // que la pestaña quedaba desplazada hacia la sien respecto al arco verde
    // del párpado. 0.68 desplaza el ancla un 68% del ancho del ojo — con un
    // ojo de 45px medidos en el overlay, son ~30px de corrimiento. Se calibra
    // desde 0f hacia arriba SOLO si vuelve a invadir la nariz, verificando
    // contra los puntos verdes.
    const val NOSE_AVOID_SHIFT = 0.0f

    // LATERAL_LASH_OFFSET = 0: sin corrección lateral adicional.
    const val LATERAL_LASH_OFFSET = 0.0f

    // ── Parpadeo ────────────────────────────────────────────────────────
    const val EYE_CLOSED_OPENNESS_THRESHOLD = 0.12f
    const val EYE_OPEN_OPENNESS_THRESHOLD = 0.22f

    /**
     * Umbral de parpadeo RELATIVO al ojo de cada persona — ver
     * [OpennessTracker]. Reemplaza a los dos umbrales absolutos de arriba,
     * que quedan solo como referencia histórica.
     *
     * Los absolutos (0.12 / 0.22) asumían una forma de ojo. Medido en
     * dispositivo sobre un ojo rasgado, la apertura oscilaba entre 0.108 y
     * 0.198: cruzando el de "cerrado" todo el tiempo y sin llegar nunca al de
     * "abierto", o sea pestaña permanentemente atenuada y parpadeando entre
     * visible y oculta.
     *
     * Como fracciones de la propia base de la persona: por debajo del 30% de
     * su apertura normal se considera cerrado, por encima del 60% totalmente
     * abierto. Un parpadeo real lleva la relación casi a cero, así que sigue
     * detectándose; lo que ya no pasa es confundir "ojo rasgado" con "ojo
     * cerrado".
     */
    const val OPENNESS_CLOSED_FRACTION = 0.30f
    const val OPENNESS_OPEN_FRACTION = 0.60f

    /** Sube rápido (un valor más alto = el ojo está más abierto de lo que
     * creíamos) y baja muy lento: si bajara rápido, tras un par de parpadeos
     * la base sería la del ojo CERRADO y no se ocultaría nunca. Ver
     * [OpennessTracker]. */
    const val OPENNESS_BASELINE_RISE = 0.15f
    const val OPENNESS_BASELINE_DECAY = 0.9995f

    /** Muestras antes de confiar en la base. Mientras tanto no se atenúa: sin
     * base confiable es preferible mostrar la pestaña de más que ocultarla
     * justo al aparecer el rostro. */
    const val OPENNESS_WARMUP_SAMPLES = 15

    // ── Congelado de forma por parpadeo (ver OpennessTracker/LidShape) ──
    // Los dos valores están en apertura NORMALIZADA: 0 = cerrado
    // (OPENNESS_CLOSED_FRACTION de la base de la persona), 1 = abierto
    // (OPENNESS_OPEN_FRACTION o más). Un ojo en reposo se clampea a 1.
    //
    // Son DOS umbrales y no uno (histéresis) porque con uno solo el estado
    // oscilaba frame a frame en la frontera — el `hideSlot -> OCULTO` /
    // `-> VISIBLE` alternando cada decenas de milisegundos que ya se vio en
    // logcat.
    //
    // Ninguno de los dos decide si la pestaña se VE: con el ojo cerrado se
    // sigue dibujando (ver LashRenderer.applyTransform).

    /** Por debajo de esto se deja de confiar en la geometría del párpado y
     * se congela la forma ([LidShapeHold]).
     *
     * BAJADO de 0.75 a 0.25 (2026-09-04): con 0.75 la forma se congelaba a
     * ~52% de apertura, o sea durante el USO NORMAL — mirando el teléfono
     * desde abajo, con los párpados algo caídos, la pestaña dejaba de
     * adaptarse al párpado (reportado en dispositivo). Congelar es para el
     * PARPADEO, que lleva la apertura casi a cero en 2-3 frames; una mirada
     * entrecerrada no es un parpadeo y ahí la pestaña tiene que seguir
     * ajustándose. Con 0.25 hace falta bajar a ~37% de la apertura normal de
     * la persona, cosa que fuera de un parpadeo real no pasa. */
    const val SHAPE_TRUST_DROP_BELOW = 0.25f

    /** Para volver a medir la forma en vivo hace falta superar este umbral,
     * con margen sobre el de arriba (histéresis). */
    const val SHAPE_TRUST_RESTORE_ABOVE = 0.45f

    // ── Iluminación mejorada para pestañas estéticas ────────────────────
    // Luz ambiente más intensa y cálida para que las pestañas se vean
    // bien iluminadas como en fotos de belleza profesionales.
    const val INDIRECT_LIGHT_INTENSITY = 35000f
    const val KEY_LIGHT_INTENSITY = 60000f
    val KEY_LIGHT_COLOR = Float3(1f, 0.95f, 0.88f)  // Blanco cálido
    // Luz casi frontal, ligeramente desde arriba — ilumina las pestañas
    // sin crear sombras duras que las oscurezcan.
    val KEY_LIGHT_DIRECTION = Float3(-0.1f, -0.5f, -0.85f)

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
    //
    // SIN USO desde la reescritura de LashMeshBender a FloatBuffer directo +
    // VertexBuffer.setBufferAt in-place (ver LashMeshBender/EyeModelSlot):
    // ese throttle existía para acotar la TASA de asignaciones de heap
    // (Geometry.Vertex/Float3 por vértice + FloatBuffer.allocate() de
    // geometry.setVertices()), no la tasa de recálculo en sí — con cero
    // asignaciones por vértice, ya no hay presión de GC que limitar. Se deja
    // definida por su valor histórico/documental (todo el comentario de
    // arriba), no porque algo la siga leyendo.
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
    //
    // Subido de vuelta a 1.0f (2026-08-10, ver sección 6.1 del doc): pedido
    // explícito del usuario de que el modelo 3D tenga "esa misma silueta"
    // que los 8 puntos reales del párpado — con `strength < 1f`, el mesh
    // sigue solo una fracción de `LashLineCurve.deviationAt()`, así que NO
    // puede coincidir exactamente con la curva aunque esta ya interpole los
    // 8 puntos con precisión (6.1). El caso que motivó bajarlo a 0.5f era
    // específicamente la PUNTA del ala de Cat Eye, que cae FUERA de
    // `[minLocalX, maxLocalX]` (fuera del rango con datos reales) — ahí
    // sigue aplicando el falloff con smoothstep (ver `LashLineCurve`,
    // sección 5.6/5.8), que ya amortigua esa zona por separado de
    // `strength`; la sospecha era que la combinación de AMBOS mecanismos
    // amortiguando lo mismo era lo que sobre-corregía.
    //
    // REVERTIDO 2026-08-10 (confirmado en dispositivo real, Infinix X669,
    // misma sesión, con `LASH_DEFORMATION_ENABLED=false` como prueba de
    // aislamiento — sección 6.2): con el TRANSFORM solo (sin doblado), la
    // pestaña queda perfecta en los dos ojos — raíz y dirección correctas.
    // Al reactivar el doblado con `strength=1.0f` (uniforme, sin distinguir
    // zona), el ala se distorsionaba de nuevo. Bajado a `0.5f` (5.11) como
    // parche uniforme — amortiguaba TODO, incluida la zona con los 8 puntos
    // reales, donde el spline (6.1) no tiene ningún riesgo de overshoot.
    //
    // SEPARADO 2026-08-10 (sección 6.4): en vez de un único `strength`
    // uniforme, `LashMeshBender.bendInPlace()` ahora amortigua distinto
    // según la zona (ver [LashLineCurve.wingBlend]) — este valor vuelve a
    // `1.0f` porque SOLO se aplica dentro de `[minLocalX, maxLocalX]` (los 8
    // landmarks reales), donde es matemáticamente seguro (spline exacto,
    // monótono, sin overshoot). La amortiguación que antes hacía este valor
    // en el ala ahora vive en [LASH_BEND_WING_STRENGTH], por separado.
    const val LASH_BEND_STRENGTH = 1.0f

    // Fuerza en la extrapolación MÁS ALLÁ de los 8 puntos reales (ej. la
    // punta del ala de un Cat Eye, sección 6.4) — zona sin datos reales,
    // donde `strength=1.0` uniforme causó una distorsión confirmada en
    // dispositivo real (sección 6.3). Mismo valor que el `LASH_BEND_STRENGTH`
    // ya confirmado seguro en 5.11 — punto de partida conservador; subir
    // esto (no [LASH_BEND_STRENGTH]) si hace falta más fidelidad en el ala,
    // siempre confirmando en dispositivo real antes de dejarlo.
    const val LASH_BEND_WING_STRENGTH = 0.5f

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

    // ── Diagnóstico: aislar TRANSFORM de DEFORMACIÓN ──────────────────────
    // `false` desactiva el doblado de mesh (LashMeshBender) por completo —
    // el modelo se renderiza con su forma de fábrica, solo con
    // posición/rotación/escala (EyeTransformCalculator) aplicadas. Sirve
    // para confirmar, en dispositivo real, si un desalineamiento viene del
    // ANCLA/TRANSFORM (con esto en `false`, el mesh sin doblar debería
    // seguir naciendo en la línea del párpado) o del DOBLADO (si el mesh sin
    // doblar ya está bien ubicado pero se desvía al activar esto de nuevo).
    // `true` = comportamiento normal en producción.
    //
    // REESCRITO Y REACTIVADO: LashMeshBender ya no asigna Geometry.Vertex/
    // Float3 por vértice ni pasa por geometry.setVertices() (que
    // internamente hacía FloatBuffer.allocate() + recálculo de AABB en cada
    // llamada) — usa FloatBuffer directo preasignado +
    // VertexBuffer.setBufferAt() in-place, el mismo patrón que
    // FaceMeshRenderer (Fase 1). El OOM original venía de esas asignaciones
    // a ~30Hz sin límite, no de recalcular el doblado en sí — con cero
    // asignaciones por vértice, ya no hace falta el throttle de
    // LASH_BEND_MIN_INTERVAL_NANOS (ver esa constante, ya sin uso). También
    // recalcula TANGENTS por frame (ver LashMeshBender.computeRestTangents),
    // agregado tras confirmar en dispositivo que dejar la normal estática
    // se veía como una línea negra dura junto a la pestaña.
    // TEST DE AISLAMIENTO TEMPORAL (a pedido, no permanente): con esto en
    // `false`, la línea negra de la base debería seguir apareciendo IGUAL
    // (predicción, ver historial de conversación: se reportó por primera vez
    // con el doblado ya apagado, junto con el fix de rootLocalY) — si es así,
    // confirma que el doblado/tangentes NO la causaron. Revertir a `true`
    // después de esta prueba puntual.
    const val LASH_DEFORMATION_ENABLED = true

    // Piso de color por vértice (ver RawMesh.withColorFloor) — el COLOR_0
    // del .glb trae un degradado raíz→punta intencional del artista
    // (raíz≈0.03 casi negro puro, punta≈0.14, medido en cateyeleft.glb).
    // Con la raíz ahora anclada exactamente en el borde del párpado, ese
    // extremo casi-negro-sólido se leía como una línea dura en dispositivo
    // real. 0.08f es un primer valor sin confirmar todavía — mismo criterio
    // que cualquier constante nueva de este proyecto: ajustar según lo que
    // se vea, no asumir que es el correcto. Subir (más cerca de 0.14) si
    // sigue viéndose como línea; bajar (más cerca de 0.03) si la pestaña
    // queda demasiado clara/plana.
    const val LASH_COLOR_FLOOR = 0.08f

    // ── Suavizado de los puntos del párpado (ver UpperLidFilter) ───────
    /**
     * One Euro sobre los 7 puntos del arco del párpado superior, en PÍXELES
     * de la imagen de análisis — NO reusar los de posición/rotación, que
     * operan en unidades de mundo (~0.01-0.6): el término `beta*|velocidad|`
     * depende de la escala de la señal.
     *
     * En reposo un landmark oscila ~1-2 px; al mover la cabeza rápido se
     * desplaza del orden de cientos de px/s. Con `minCutoff = 1.5 Hz` el
     * filtro corta fuerte quieto, y con `beta = 0.03` a ~300 px/s el corte
     * sube a ~10 Hz (1.5 + 0.03*300), o sea casi sin suavizar cuando de
     * verdad te movés.
     *
     * SIN CALIBRAR EN DISPOSITIVO — son un punto de partida derivado de esas
     * magnitudes, no valores medidos. Si la pestaña "arrastra" la forma al
     * parpadear, SUBIR `LID_POINT_BETA`; si sigue vibrando quieta, BAJAR
     * `LID_POINT_MIN_CUTOFF`.
     */
    const val LID_POINT_MIN_CUTOFF = 1.5f
    const val LID_POINT_BETA = 0.03f

    /**
     * Luminancia de la PUNTA tras pasar la pestaña a negro neutro (ver
     * [RawMesh.toNeutralBlack]). La raíz queda proporcionalmente más oscura,
     * conservando el degradado.
     *
     * El `COLOR_0` original es cálido (punta R=0.151 G=0.096 B=0.066 en
     * `cateyeleft.glb`), o sea marrón oscuro — por eso la pestaña no se
     * leía negra. Esto neutraliza el tinte y baja el nivel.
     *
     * 0.04f ≈ negro con una variación de fibra apenas perceptible. Bajar
     * hacia 0f = negro absoluto (pero se pierde el relieve de fibra y
     * vuelve el riesgo de "mancha plana"); subir = más gris/visible.
     * La luminancia máxima del asset original era ≈ 0.106 para referencia.
     */
    const val LASH_BLACK_TIP_LUMINANCE = 0.04f

    /**
     * Gira el modelo de pestañas 180° sobre su eje `right`. Ver
     * [EyePlaneCalculator] para por qué se niegan `up` y `normal` juntos y
     * nunca uno solo.
     *
     * CRITERIO (no es preferencia estética, es cómo funciona el producto
     * real): una pestaña postiza nace pegada en la línea de pestañas y las
     * fibras SUBEN desde ahí. Cualquier cambio a este flag tiene que
     * respetar eso — si el modelo se ve "arriba pero mirando hacia abajo",
     * el valor correcto es `false`.
     *
     * `false` = las fibras MIRAN HACIA ARRIBA desde la línea de pestañas
     *           (orientación pedida, y la que sale directa de la matriz de
     *           MediaPipe).
     * `true`  = volcadas: las fibras caen hacia abajo desde esa misma raíz.
     *
     * No mueve el nacimiento de la pestaña: el ancla sigue en el arco del
     * párpado superior (ver [HEIGHT_OFFSET], hoy 0f). Solo cambia hacia
     * dónde salen las fibras desde ahí.
     */
    const val FLIP_EYE_UP_AXIS = false

    // ── Malla facial de 468 puntos (Fase 1, ver FaceMeshRenderer) ─────────
    // Interruptor maestro: `false` no crea ni actualiza la malla — rollback
    // de una línea, mismo espíritu que LASH_DEFORMATION_ENABLED. El pipeline
    // de pestañas (LashRenderer/FaceRenderPipeline) es independiente de esto
    // en cualquier caso: no se ve afectado ni con esto en `true` ni en `false`.
    const val FACE_MESH_ENABLED = false

    // Signo de la profundidad relativa que entrega MediaPipe por landmark
    // (NormalizedLandmark.z()) al convertirla a Z de mundo en
    // FaceMeshRenderer.onFaceResult. SIN CONFIRMAR EN DISPOSITIVO — misma
    // situación que la convención row/column-major de EyePoseEstimator: si
    // en pantalla la malla se ve con la nariz HUNDIDA en vez de sobresaliendo
    // (cóncava en vez de convexa), cambiar a -1f.
    const val FACE_MESH_DEPTH_Z_SIGN = 1f

    // Color de depuración semitransparente (Fase 1: sin textura ni pestañas
    // ancladas todavía — solo para validar visualmente que la malla sigue la
    // cara). metallic=0/roughness=1/reflectance=0 en FaceMeshRenderer para
    // que el material PBR de SceneView se vea lo más plano/parejo posible sin
    // normales por vértice reales (esas llegan recién en una fase futura).
    const val FACE_MESH_DEBUG_COLOR_R = 0.15f
    const val FACE_MESH_DEBUG_COLOR_G = 0.85f
    const val FACE_MESH_DEBUG_COLOR_B = 1.0f
    const val FACE_MESH_DEBUG_COLOR_A = 0.35f

    // ── Anclaje de pestaña desde la malla facial (Fase 2) ─────────────────
    // `false` (default): EyePlaneCalculator + EyeTransformCalculator, tal
    // cual funcionan hoy — sin cambio de comportamiento. `true`: posición/
    // rotación/escala se derivan de MeshEyeTransformCalculator (3 landmarks
    // reales de la malla de 468 puntos por ojo) en vez de pose de cabeza +
    // residuo 2D. Rollback de una línea, mismo espíritu que
    // LASH_DEFORMATION_ENABLED/FACE_MESH_ENABLED — comparar A/B en
    // dispositivo cambiando solo esto.
    // REACTIVADO 2026-09-02 con MeshEyeTransformCalculator ya simplificado:
    // el ancla es directamente el promedio de los 8 puntos reales del párpado
    // superior (sin heightOffset ni nudges manuales encima), que era el
    // objetivo original de este sistema. Rollback de una línea a `false` si
    // hace falta volver al camino 2D+headPose.
    const val LASH_ANCHOR_FROM_FACE_MESH = false

    // ── Calibración temporal: malla vs. sistema viejo (tag "MESH_CALIB") ──
    // Ver FaceRenderPipeline.logMeshCalibration / MeshEyeTransformCalculator.
    // computeWithDebug. `true`: además del sistema activo (el que decide
    // LASH_ANCHOR_FROM_FACE_MESH), calcula y loguea EL OTRO sistema para el
    // mismo frame/ojo — compara posición/escala lado a lado en vez de
    // calibrar a ciegas por foto. Puramente diagnóstico: no participa en qué
    // transform se usa para renderizar. Apagar (rollback de una línea)
    // cuando termine esta ronda de calibración de LASH_ANCHOR_FROM_FACE_MESH.
    // Apagado 2026-09-02 junto con LASH_ANCHOR_FROM_FACE_MESH — sin el
    // sistema nuevo activo, esto solo agregaba trabajo por frame y ruido en
    // logcat. Volver a `true` solo si se retoma la calibración de la malla.
    const val MESH_CALIBRATION_LOGGING = false

    // Ajuste directo de altura del ancla del sistema nuevo (ver
    // MeshEyeTransformCalculator) — fracción de eyeWidthWorld que se resta
    // adicionalmente a lo largo de `up`, para bajar el ancla hacia la línea
    // real de pestañas. Confirmado en dispositivo (2026-09-01): con
    // heightOffset=0.12 (el término existente, indirecto, chico) el ancla
    // seguía quedando arriba de la línea real después de arreglar orientación
    // y altura por arco de 8 puntos — la corrección de raíz por sí sola no
    // alcanza a compensarlo. Valor inicial estimado a partir de las capturas
    // reales (el hueco visible es del orden de una fracción sustancial del
    // ancho del ojo) — MISMO patrón de calibración iterativa que
    // LATERAL_LASH_OFFSET (COLOCADO_PESTANAS sección 5.13): probar, ajustar
    // según lo que se vea, no una constante final.
    // REVERTIDO a 0f (2026-09-02): el 0.4f anterior fue un valor puesto a ojo,
    // sin captura que lo respaldara, y desplazaba el ancla ~40% del ancho del
    // ojo hacia abajo — aproximadamente una altura de ojo entera, lo que
    // hacía caer el abanico sobre el globo ocular en vez de nacer en la línea
    // del párpado. Confirmado contra una captura anotada por el usuario
    // (líneas rojas marcando dónde debe ir la raíz). Si hace falta un ajuste
    // fino de altura, calibrar desde 0f en pasos chicos (0.05f) confirmando
    // en dispositivo cada paso, como se hizo con LATERAL_LASH_OFFSET.
    const val MESH_ANCHOR_HEIGHT_NUDGE = 0.0f

    // ── Delineado (Fase 4) ──────────────────────────────────────────────
    // Interruptor maestro de LinerRenderer — mismo patrón que
    // FACE_MESH_ENABLED (guard temprano en attachSceneView/onFaceResult).
    // `false`: LinerRenderer nunca crea su nodo/ribbon ni recibe resultados
    // de MediaPipe — se aísla por completo del resto de la escena. Se
    // apagó para descartar el ribbon placeholder (opaco, plano, sin
    // textura, comparte LASH_DEFORMATION_ENABLED con LashMeshBender.
    // bendInPlace) como origen de la "línea negra recta y dura" reportada
    // en dispositivo — más consistente con ese síntoma que el mesh de
    // pestañas con fibras. Reactivar solo tras confirmar en dispositivo
    // que la línea desaparece con esto en `false`.
    const val ENABLE_EYELINER = false

    // Flag PROPIO, independiente de LASH_ANCHOR_FROM_FACE_MESH — el
    // anclaje-por-malla de pestañas todavía no se confirmó en dispositivo,
    // así que el delineado no debe heredar ese riesgo sin probar (ver plan
    // Fase 4). Mismo significado que su contraparte de pestañas: `false` =
    // EyePlaneCalculator+EyeTransformCalculator (2D+headPose, probado);
    // `true` = MeshEyeTransformCalculator (3 landmarks de la malla).
    const val EYELINER_ANCHOR_FROM_FACE_MESH = false

    // Color sólido placeholder del ribbon procedural de delineado (ver
    // LinerRibbonMesh/LinerRenderer) — no hay `.glb`/material de arte
    // todavía. Alpha=1 -> material OPACO (ver MaterialLoader.
    // createColorInstance): un delineado real no es translúcido como el
    // overlay de debug de la malla facial.
    const val LINER_PLACEHOLDER_COLOR_R = 0.08f
    const val LINER_PLACEHOLDER_COLOR_G = 0.06f
    const val LINER_PLACEHOLDER_COLOR_B = 0.05f
    const val LINER_PLACEHOLDER_COLOR_A = 1.0f
}