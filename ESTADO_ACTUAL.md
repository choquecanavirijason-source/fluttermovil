# Estado actual — reconocimiento de ojos y renderizado 3D de pestañas

**Última actualización: 2026-07-24**, releído archivo por archivo contra el código real del
repo (no contra lo que este documento decía antes). Cubre las dos partes del sistema: el
pipeline de reconocimiento/tracking de ojos (cámara → MediaPipe → Flutter) y el motor de
renderizado 3D de pestañas (`.glb` vía SceneView/Filament), más la UX de Flutter alrededor de
la captura (alineación, personalización, guardado). Ver también
[RECONOCIMIENTO_OJOS.md](RECONOCIMIENTO_OJOS.md) (documento vivo de análisis) y
[COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) (detalle dedicado solo al cálculo de
posición/escala de las pestañas, con las fórmulas completas) — este archivo es la foto fija
de "cómo está" a la fecha de arriba.

---

## 1. Arquitectura general

```
┌───────────────────────────────────────────────────────────────────────────────────┐
│                                   FLUTTER (Dart)                                   │
│                                                                                     │
│   eye_tracking_page.dart  (orquestador de la pantalla, ver 2.1)                   │
│      ├─ HybridCameraPreview (PlatformView "camera_preview_view")                  │
│      │     creationParams: { leftModelPath, rightModelPath }                      │
│      ├─ EyeTrackingPhotoPipeline   (captura overlay + foto real, compone/recorta) │
│      ├─ EyeAlignmentGuide          (¿ojos dentro de la guía? → auto-captura)      │
│      ├─ LashCustomizationCatalog   (catálogos diseño/técnica/efecto/grosor)       │
│      └─ Bottom sheets: EyeTypePickerSheet / SaveOptionsSheet / ClientPickerSheet  │
│                                                                                     │
│   NativeEyeTrackingService ◄──EventChannel "eye_tracking/events"─┐                │
│      trackingStream: Stream<TrackingFrame>                       │                │
│           │                                                       │                │
│  ┌────────┼──────────────────┬──────────────────────┐            │                │
│  ▼        ▼                  ▼                       │            │                │
│ EyeShapeAnalyzer  LashMappingPainter   EyeAlignmentGuide          │                │
│ (tipo de ojo, UI) (overlay "abanico")  (guía antes de foto)       │                │
└─────────────────────────────────────────────────────────────────┼────────────────┘
                                                                    │
                          MethodChannel / EventChannel "eye_tracking"
                                                                    │
┌───────────────────────────────────────────────────────────────────────────────────┐
│                                  ANDROID (Kotlin)                                  │
│                                                                                     │
│  CameraPreviewFactory.create()  — PlatformView, una vez por entrada a la pantalla  │
│     ├─ PreviewView   (Z=0, feed de cámara — androidx.camera.view)                  │
│     └─ SceneView     (Z=1, translúcido — io.github.sceneview, Filament)            │
│           │                                                                        │
│           ▼ (síncrono, misma invocación — ver sección 4)                          │
│     CameraXManager.attachPreview() / .attachSceneView() / .loadEyeModels()         │
│                                                                                     │
│  CameraXManager  — coordinador delgado: CameraX (bind/unbind, cámara) +            │
│     medición de latencia real de MediaPipe (EMA, ver sección 4)                    │
│     ├─ ImageAnalysis (960×720) ──► FaceLandmarkerHelper (MediaPipe, LIVE_STREAM)   │
│     │                                  ├─ Map<String,Any?> ──► Flutter (2D, UI)    │
│     │                                  └─ FaceLandmarkerResult crudo ──► render/   │
│     ├─ Preview (1440×1080) ──► PreviewView.surfaceProvider (feed visible)          │
│     └─ VideoCapture (grabación local, sin audio)                                   │
│                                                                                     │
│  LashRenderer (package `render/`)  — TODA la matemática de posicionar el .glb      │
│     dueño del SceneView: iluminación, carga de modelos, filtro, interpolación,     │
│     escritura final al ModelNode. Ver sección 3 para el detalle completo.          │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

**Principio de diseño que se mantiene desde la reescritura del motor**: `CameraXManager` no
calcula geometría/posición — solo bindea CameraX, mide timing y reenvía datos. Todo el
cálculo de "dónde va la pestaña" vive en `render/`, con `RendererConfiguration.kt` como única
fuente de constantes de tuning. Confirmación línea por línea en la sección 4.

---

## 2. Parte 1 — Pipeline de reconocimiento de ojos

```
CameraX (Kotlin, Android)
   └─ ImageAnalysis (960×720) ──► FaceLandmarkerHelper (MediaPipe FaceLandmarker, LIVE_STREAM)
                                        └─ 478 landmarks faciales por frame
                                             └─ EyeTrackingResultMapper.map(...)
                                                  └─ Map<String, Any?>: faceDetected,
                                                     imageWidth, imageHeight, leftEye[8pts],
                                                     rightEye[8pts], leftIris, rightIris,
                                                     faceContour[36pts]
   └─ EventChannel "eye_tracking/events" ──────────────────────────────────► Flutter
                                                                                  │
                                                                    NativeEyeTrackingService
                                                                                  │
                                                              trackingStream: Stream<TrackingFrame>
                              ┌───────────────────────────────────┼─────────────────────┐
                              ▼                                   ▼                     ▼
                 EyeShapeAnalyzer.analyze(frame)     LashMappingPainter        EyeAlignmentGuide
                 (aspect ratio, canthal tilt,        (overlay "abanico")       (guía de alineación
                  asimetría) → pill "tipo de ojo"                              antes de capturar foto,
                                                                                 ver 2.1)
```

| Pieza | Estado |
|---|---|
| Detección de landmarks (MediaPipe FaceLandmarker) | ✅ Funciona |
| Envío de landmarks a Flutter vía `EventChannel` | ✅ Funciona |
| Clasificación de forma de ojo (Dart) → pill "tipo de ojo" | ✅ Funciona |
| Guía de alineación antes de capturar foto | ✅ Funciona |
| Overlay visual de mapeo de pestañas | ✅ Funciona |
| `try/catch` en `setResultListener` (no tumba el pipeline ante un frame raro) | ✅ Funciona |
| `eyeShapeStream` / filtrado automático del catálogo por forma de ojo | ❌ Roto — ver abajo |
| `leftOpenRatio` / `rightOpenRatio` en `TrackingFrame` | ❌ Campo muerto |

**`eyeShapeStream` roto, en detalle**: `EyeTrackingResultMapper.kt` nunca calcula ni manda
`leftEyeShape`/`rightEyeShape`, así que `NativeEyeTrackingService.eyeShapeStream` nunca
emite. No deja la pantalla en blanco (`filteredCatalogProvider` primero hace `yield
allItems` sin filtrar, y el `await for (shape in eyeShapeStream)` que nunca dispara solo
significa que el catálogo jamás se reduce por forma de ojo detectada) pero la feature de
filtrado automático simplemente no existe hoy. Propuesta de arreglo en
[RECONOCIMIENTO_OJOS.md](RECONOCIMIENTO_OJOS.md) secciones 5 y 6.

### 2.1 Arquitectura Flutter — post-extracción de `eye_tracking_page.dart`

`eye_tracking_page.dart` dejó de ser un archivo monolítico: la lógica de captura, catálogos
de personalización y guía de alineación se movió a módulos propios, y la pantalla sumó tres
bottom sheets nuevos. Ninguno de estos archivos estaba documentado antes.

| Archivo | Responsabilidad |
|---|---|
| `lib/eye_tracking_page.dart` | Orquestador que queda: ciclo de vida cámara/tracking (`_start`, `didChangeAppLifecycleState`), estado del menú de personalización (índices de filtro/diseño/técnica/efecto/grosor, `_activeCategory`), auto-detección de tipo de ojo (`_detectEyeTypeFromFrame` vía `EyeShapeAnalyzer`), el flujo alineación→captura→navegación (`_startAlignmentGuide`, `_evaluateAlignment`, `_beginWorkAssistantFlow`, `_openRecommendation`), y la apertura de los bottom sheets nuevos (`_showEyeTypeSheet`, `_showSaveDesignSheet`, `_showClientPickerSheet`, `_saveToClient`). |
| `lib/eye_tracking_alignment.dart` | `EyeAlignmentGuide.isAligned(TrackingFrame, Size)` — geometría pura (sin `BuildContext`/estado): ¿ambos ojos detectados caen dentro de la zona guía en pantalla?, con el mismo transform `BoxFit.cover` que usan el painter y el recorte de foto. |
| `lib/eye_tracking_customization_options.dart` | `LashCustomizationCatalog` — catálogos estáticos (listas de imágenes + labels) para las categorías de diseño/técnica/efecto/grosor del menú de personalización, con `imagesFor`/`optionsFor`/`titleFor` y helpers para armar el texto de notas de guardado. |
| `lib/eye_tracking_photo_pipeline.dart` | `EyeTrackingPhotoPipeline` — toda la lógica de los paquetes `camera`/`image`: `captureOverlay` (PNG del overlay Flutter renderizado, vía `RepaintBoundary`), `captureAndComposite` (abre la cámara frontal y toma una foto real), `compositeAndCrop` (estático: compone overlay + foto por alpha, recorta a la banda del ojo, corrige rotación/espejo de la cámara frontal). |
| `lib/screens/widgets/client_picker_sheet.dart` | `ClientPickerSheet` — `DraggableScrollableSheet` con buscador debounced (350ms) sobre `clientSearchProvider`/`clientsListProvider`, para elegir a qué cliente guardar el diseño (avatar con iniciales, nombre, teléfono). |
| `lib/screens/widgets/eye_position_guide_painter.dart` | `EyePositionGuidePainter` (`CustomPainter`) — oscurece la pantalla salvo una banda central (y 22%–64%, la misma región que recorta `EyeTrackingPhotoPipeline`), con contorno redondeado que se pone verde cuando `aligned=true`. |
| `lib/screens/widgets/eye_type_picker_sheet.dart` | `EyeTypePickerSheet` — bottom sheet para elegir manualmente un tipo de ojo del catálogo (imagen o ícono, nombre, descripción), marca con un check el actualmente seleccionado; soporta `preloadedItems` para no re-consultar. |
| `lib/screens/widgets/save_options_sheet.dart` | `SaveOptionsSheet` — bottom sheet simple con una opción ("Lista de clientes") que dispara `onListaTap`; comentario en el código deja explícito que el layout está preparado para agregar más destinos de guardado. |

**Funcionalidad de usuario nueva que no estaba documentada**:
- Selección **manual** del tipo de ojo (antes solo se auto-detectaba desde el frame).
- Guía visual de alineación antes de capturar (posicionar los ojos dentro del marco, con
  ~900ms de sostenimiento) y **auto-captura** al quedar alineado.
- Flujo de guardado a cliente: guardar → `SaveOptionsSheet` ("Lista de clientes") →
  `ClientPickerSheet` (buscar/elegir cliente) → confirmar → se persiste vía
  `trackingRepositoryProvider.create` con notas de diseño/técnica/efecto/grosor armadas por
  `LashCustomizationCatalog`.

Cambios de alcance menor detectados en el mismo diff, sin relación con pestañas: en
`app_router.dart` se reactivó el `redirect` de autenticación (sin sesión → `/login`); en
`work_assistant_screen.dart` se quitó el botón flotante de grabar video.

---

## 3. Parte 2 — Motor de renderizado 3D (paquete `render/`)

Para el detalle matemático completo de cómo se calcula la posición/rotación/escala de cada
pestaña, ver [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md). Esta sección se queda en el mapa
de archivos, el flujo de datos y el estado real de cada pieza.

### 3.1 Mapa de archivos

19 archivos en `android/app/src/main/kotlin/com/example/test_face/render/` (18 activos + 1
stub vacío):

| Archivo | Responsabilidad |
|---|---|
| `RendererConfiguration.kt` | Única fuente de constantes de tuning: One Euro Filter, profundidad, escala, nudges por ojo, openness thresholds, iluminación. |
| `FaceLandmarkIndices.kt` | Índices canónicos de MediaPipe: anillo de 16 puntos por ojo + iris. |
| `EyeLandmarks.kt` | Extrae el anillo del ojo, el párpado superior (dinámico: mitad de menor Y, no índice fijo) y `opennessRatio` (alto/ancho del anillo, proxy de apertura). |
| `EyePoseEstimator.kt` | `facialTransformationMatrixes()` de MediaPipe → `HeadPose` en espacio Filament, con conjugación de espejo correcta (`F·R·F`, no `F·R`). `fallback()` (pose neutra) si la matriz no está disponible. `DEBUG_LOG_POSE = false` en producción (activar solo para depurar pose — logueaba en cada frame, agregaba I/O al critical path). |
| `EyeAnchorCalculator.kt` | Ancla real: X = promedio de todo el párpado superior; Y = promedio del 30% inferior (el borde visible) desplazado hacia arriba por `HEIGHT_OFFSET`, + tangente del párpado por PCA (mínimos cuadrados totales sobre todos los puntos, no solo extremo-a-extremo). |
| `EyePlaneCalculator.kt` | Plano/normal local de cada ojo: combina la rotación de cabeza con el residuo angular propio del párpado (Rodrigues). |
| `CameraProjection.kt` | Des-proyección real (`unproject`/`worldDistanceAtDepth`) desde `SceneView.cameraNode.projectionTransform`/`modelTransform` — perspectiva real, válida a cualquier distancia de cámara. |
| `EyeTransformCalculator.kt` | Posición/rotación/escala final del `EyeTransform`, sin suavizar todavía. Corrección de foreshortening por rotación de cabeza. |
| `LashLineCurve.kt` | Ajuste cuadrático (mínimos cuadrados, 3×3) del párpado superior — produce `deviationAt`/`slopeAt`. Se calcula cada frame (barato) y queda colgado de `EyeTransform.lashLineCurve`, pero **no se consume en el render actual** porque `LashMeshBender` está desactivado (ver 3.4). |
| `GlbMeshReader.kt` | Parsea un `.glb` (header + chunks JSON/BIN) una vez al cargar el modelo → `RawMesh` (vértices/índices/bounding box). |
| `LashMeshBender.kt` | Dobla `RawMesh` según una `LashLineCurve` → `List<Geometry.Vertex>`. **Existe, compila, no se llama por frame** (ver 3.4 — causó un crash de producción). |
| `OneEuroFilter.kt` | Filtro 1€ (Casiez, Roussel & Vogel, CHI 2012) para una señal escalar: corte adaptativo a la velocidad instantánea. |
| `EyeTrackingFilter.kt` | 10 instancias de `OneEuroFilter` por ojo (3 posición + 4 quaternion + 3 escala), con alineación antipodal del quaternion antes de filtrar (evita glitches al cruzar el signo) y renormalización post-filtro. |
| `PoseInterpolator.kt` | Desacopla el framerate de render (vsync) del framerate de MediaPipe: guarda las últimas 3 muestras filtradas y predice hacia ADELANTE, compensando la latencia medida del pipeline (cuadrático con velocidad+aceleración; lineal si solo hay 2 muestras) — ver 3.3. |
| `EyeModelSlot.kt` | Estado por ojo: `node`, `path`, `naturalSpan`, `modelYRatio`, `filter`, `interpolator`, `rawMesh`, `geometry`. |
| `MaterialManager.kt` | Intenta `lash_fiber.filamat` (anisotrópico); si no existe, fallback a PBR genérico (`doubleSided`). |
| `FaceRenderPipeline.kt` | Orquesta el flujo por frame para ambos ojos — stateless, recibe `CameraProjection` del `SceneView` activo. |
| `LashRenderer.kt` | Dueño del `SceneView`: iluminación de estudio, carga de `.glb`, `Choreographer.FrameCallback`, blink damping, aplica la transformación filtrada e interpolada. |
| `EyelidCurveFitter.kt` | **0 bytes, sin usar.** Stub nunca escrito — no lo referencia nada. |

`FaceLandmarkerHelper.kt` activa `outputFacialTransformationMatrixes(true)` y entrega tanto
el `Map` 2D para Flutter como el `FaceLandmarkerResult` crudo para `render/`. Además intenta
el delegado **GPU** primero (`Delegate.GPU`) y cae a CPU si falla al inicializar en el
dispositivo — la inferencia con matrices de transformación en CPU agrega decenas de ms que
ningún filtro puede compensar después. `EyeTrackingResultMapper.kt` no cambia — `render/` lee
los landmarks crudos con sus propios índices, en paralelo.

### 3.2 Flujo de datos, frame por frame

```
FaceLandmarkerResult (crudo, de MediaPipe)
        │
        ▼
CameraXManager: mide latencia real (EMA, ver sección 4) → smoothedLatencyMs
        │
        ▼
LashRenderer.onFaceResult(result, imageWidth, imageHeight, pipelineLatencyMs)
   — no-op si no hay ningún nodo cargado; todo envuelto en try/catch (oculta y loguea, no crashea)
   — measuredLatencyNanos = (pipelineLatencyMs + 16ms) × 1e6   [16ms = margen SurfaceFlinger]
        │
        ▼
FaceRenderPipeline.compute(...)
   1. facialTransformationMatrixes() → EyePoseEstimator.fromMediaPipeMatrix(...) → HeadPose
      (o EyePoseEstimator.fallback() si no está disponible)
   2. Por cada ojo → computeEye(...):
        EyeLandmarks.from(...)        → anillo de 16 pts + párpado superior + opennessRatio
        EyeAnchorCalculator.compute() → EyeAnchor (punto + tangente por PCA)
        EyePlaneCalculator.compute()  → EyePlane (normal + quaternion)
        EyeTransformCalculator.compute() → EyeTransform SIN suavizar:
            posición = camera.unproject(ndcX, ndcY, worldZ)      [profundidad real de cabeza]
            escala   = camera.worldDistanceAtDepth(...) × WIDTH_MULTIPLIER / naturalSpan
                       × corrección de foreshortening
        LashLineCurve.fit(...) → adjunta la curva del párpado al EyeTransform (no consumida hoy)
        │
        ▼
   FaceRenderPipeline.Result(left, right)
        │
        ▼
LashRenderer.applyTransform(slot, transform)
   — damping = opennessDamping(opennessRatio): smoothstep entre thresholds cerrado/abierto
   — damping ≤ 0 → oculta el nodo, no escribe escala 0
   — smoothed = slot.filter.apply(transform): EyeTrackingFilter, 10× OneEuroFilter
   — damped = smoothed con scale × damping
   — slot.interpolator.push(damped, nowNanos)   [NO escribe el nodo todavía]
        │
        ▼ (en paralelo, a vsync — Choreographer.FrameCallback de LashRenderer)
writeInterpolatedPose(slot, frameTimeNanos)
   — transform = slot.interpolator.sample(frameTimeNanos, measuredLatencyNanos)
   — predice la pose a (frameTimeNanos + measuredLatencyNanos), no solo sostiene/extrapola
     entre las últimas dos muestras — ver 3.3
   — node.position / node.quaternion / node.scale = transform.*
```

El desacople render/MediaPipe (`PoseInterpolator` + `Choreographer.FrameCallback`) existe
porque el nodo 3D antes solo se actualizaba cuando llegaba un resultado nuevo de MediaPipe
(más lento que el refresco de pantalla) — ahora el hilo de render escribe la pose en cada
vsync, con **compensación adaptativa de latencia**: `CameraXManager` mide la latencia real de
MediaPipe EN ESE DISPOSITIVO (no un valor fijo adivinado) y `PoseInterpolator` predice hacia
ese instante futuro — técnica equivalente a la que usan TikTok/DeepAR para que el modelo
muestre dónde el rostro ESTÁ AHORA, no dónde estaba cuando terminó de procesarse el frame.

### 3.3 Carga del `.glb`, estado y predicción de pose

```
LashRenderer.loadEyeModels(leftPath, rightPath)  ← desde Flutter, vía CameraXManager
   → loadIntoSlot(slot, path, eye):
      1. lee bytes del .glb → sv.modelLoader.createModelInstance(buffer) → ModelNode
      2. GlbMeshReader.read(path) → RawMesh; Geometry.Builder(...).build(engine) →
         renderableNode.setGeometry(geometry)  [swap de geometría, costo ÚNICO por carga]
      3. MaterialManager.tune(node, sv)  [DESPUÉS del swap — setGeometry no garantiza
         preservar el material instance original]
      4. mide node.size → EyeModelSlot.naturalSpan / modelYRatio
      5. sv.addChildNode(node), oculto (isVisible=false) hasta el primer rostro detectado
```

`EyeModelSlot` (uno por ojo, vive dentro de `LashRenderer`) es el único estado real de todo
`render/`: `node`, `path`, `naturalSpan`, `modelYRatio`, `filter` (10× `OneEuroFilter`),
`interpolator` (últimas 3 muestras + contador de "pushes desde el último reset"),
`rawMesh`/`geometry` (la malla parseada y la geometría activa, dormidas desde la sección 3.4).
Todo lo demás en `render/` son `object`s o clases sin estado propio — funciones puras.

**`PoseInterpolator`, calentamiento post-reset**: justo al reaparecer un rostro (tras
`onFaceLost`), las primeras muestras post-reset no son "velocidad real" — la primera sale de
`OneEuroFilter` sin filtrar y el tracking todavía se está asentando. Los primeros
`WARMUP_PUSHES = 3` `push()` después de un `reset()` devuelven la última muestra tal cual
(sin extrapolar); desde el 4° `sample()` predice cuadráticamente (velocidad + aceleración,
usando las 3 últimas muestras), clampeando la extrapolación a `MAX_EXTRAPOLATION_FACTOR = 3.0×`
el intervalo entre muestras y la aceleración a `MAX_ACCEL` para no producir overshoot en
sacudidas bruscas de cabeza. Compila; **sin confirmar en dispositivo**.

### 3.4 Lo que existe pero está DESACTIVADO: doblado del mesh según la curva del párpado

Hay una ruta completa para que la pestaña siga la curva real del párpado superior
("Upper Lash Line") en vez de mantener su forma rígida de fábrica — `LashLineCurve.fit(...)`
se calcula cada frame y queda colgada del `EyeTransform`, y `LashMeshBender.bend(raw, curve,
eyeWidthPx)` sabe cómo producir la malla doblada a partir de ella. **Ninguna de las dos
piezas de código está rota** — el problema fue de rendimiento, no de corrección:

Se probó llamar `LashMeshBender.bend(...)` + `geometry.setVertices(engine, ...)` una vez por
resultado de MediaPipe (reconstruyendo 17 563–85 104 objetos `Geometry.Vertex` por ojo, cada
vez). En dispositivo real esto no fue "lento" — **tumbó el proceso**: GC bloqueando
600–850ms seguidos, heap clampeado a 192MB, `OutOfMemoryError` real dentro de
`ImageReader.acquireNextImage`, la app entera murió (logcat completo documentado en el
historial de conversación de esa sesión). Se removió la llamada; el modelo vuelve a verse
rígido (como antes de esa ronda) con la malla original asignada una única vez al cargar
(barato). Si se retoma, **no puede reintentarse reconstruyendo `List<Vertex>` por frame** —
necesita buffers nativos reusados (`ByteBuffer` escrito en sitio) y throttling real.

### 3.5 `RendererConfiguration.kt` — constantes actuales (verificadas contra el código)

| Constante | Valor real | Qué controla |
|---|---|---|
| `POSITION_MIN_CUTOFF` | `3.0` Hz | Corte mínimo del One Euro Filter de posición — alto a propósito: en reposo el filtro es casi transparente (τ≈53ms), prioriza velocidad sobre estabilidad (filosofía "latencia mínima", ver comentario del archivo). |
| `POSITION_BETA` | `22.0` (=(25−3)/1.0) | Cuánto sube el corte con la velocidad; a ~1m/s el corte llega a 25Hz. |
| `ROTATION_MIN_CUTOFF` / `ROTATION_BETA` | `2.0` / `≈12.78` (=(25−2)/1.8) | Ídem para el quaternion, referencia ≈1.8 rad/s de velocidad angular. |
| `SCALE_MIN_CUTOFF` / `SCALE_BETA` | `2.0` / `≈3.67` (=`POSITION_BETA`×0.05/0.3) | Ídem para escala, mantiene proporción fija respecto a `POSITION_BETA`. |
| `ONE_EURO_D_CUTOFF` | `1.0` Hz | Corte fijo con el que se suaviza la derivada (estimación de velocidad) dentro de cada `OneEuroFilter`. |
| `MIN_DEPTH` / `MAX_DEPTH` | `-2.2` / `-0.35` | Rango de profundidad de cabeza válido (clamp). |
| `WIDTH_MULTIPLIER` | `1.65` | Multiplicador de ancho del modelo sobre el ancho real del ojo. |
| `HEIGHT_OFFSET` | `0.30` | Fracción de la altura del ojo que se desplaza el ancla hacia arriba desde el borde del párpado (ver [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 3). |
| `RIGHT_EYE_X_NUDGE` / `LEFT_EYE_X_NUDGE` | `0.0` / `0.0` | Corrección fina por ojo (fracción de pantalla) — hoy sin corrección aplicada. |
| `FACE_DISTANCE_MULTIPLIER` / `HEAD_TILT_MULTIPLIER` | `1.0` / `1.0` | Ganchos cableados, hoy no-op — reservados. |
| `EYE_CLOSED_OPENNESS_THRESHOLD` / `EYE_OPEN_OPENNESS_THRESHOLD` | `0.12` / `0.22` | Rango de smoothstep del blink damping. |
| `INDIRECT_LIGHT_INTENSITY` / `KEY_LIGHT_INTENSITY` | `15000` / `100000` | Intensidad de luz ambiental sintética (armónicos esféricos) / luz clave direccional. |
| `MSAA_SAMPLE_COUNT` | `4` | **Declarada, sin consumidor** — `configureRenderQuality()` sigue siendo no-op (ver 4). |

Nota de higiene detectada en esta relectura: `HEIGHT_OFFSET` y los `*_X_NUDGE` estaban
documentados antes con valores distintos (`0.53` y `±0.08`) que ya NO coinciden con el
código — se corrigieron arriba. `DEBUG_LOG_POSE` también estaba documentado como `true` y
hoy es `false`.

Constantes eliminadas en la reescritura del motor y que NO deben reaparecer:
`WORLD_SCALE_X`/`_Y` (reemplazadas por `CameraProjection`), `POSITION_LERP`/`ROTATION_LERP`/
`SCALE_LERP` (reemplazadas por One Euro Filter), `FIXED_DEPTH`.

---

## 4. Cómo delega `CameraXManager` — casi sin lógica de render propia

```kotlin
private val lashRenderer = LashRenderer(activity, mainHandler)

/** EMA de la latencia real de MediaPipe en ESTE dispositivo — no un valor fijo adivinado. */
@Volatile private var smoothedLatencyMs = 35f  // semilla

private val helper = FaceLandmarkerHelper(
    onResult = { data, rawResult ->
        val latencyMs = (SystemClock.uptimeMillis() - lastFrameSubmitMs).toFloat()
        smoothedLatencyMs = smoothedLatencyMs * 0.7f + latencyMs * 0.3f   // EMA alpha=0.3

        onTrackingResult(data)                                             // → Flutter, sin tocar render/
        if (data["faceDetected"] == true && ...) {
            lashRenderer.onFaceResult(rawResult, imageWidth, imageHeight, smoothedLatencyMs)
        } else {
            lashRenderer.onFaceLost()
        }
    },
)
```

`attachPreview`/`attachSceneView`/`detachPreview`/`detachSceneView`/`loadEyeModels` son
puentes directos 1:1 a `LashRenderer`. Ningún cálculo de posición/rotación/escala vive en
`CameraXManager.kt` — si el modelo se ve mal, el bug está en `render/`, no en "falta de
delegación". La única excepción es la **medición de timing** de arriba (no geometría): mide
cuánto tarda MediaPipe en ESTE dispositivo y se la pasa a `LashRenderer` para que
`PoseInterpolator` prediga hacia adelante (ver 3.2/3.3) — vale aclararlo porque técnicamente
`CameraXManager.kt` ya no es 100% ajeno al pipeline de render, aunque no calcula posiciones.

Notas de implementación vigentes:
- `configureRenderQuality()` en `LashRenderer` sigue siendo **no-op a propósito**:
  `ToneMapping`/`AntiAliasing`/MSAA son pases de post-procesado de framebuffer completo que,
  en un `SceneView` translúcido, fuerzan alpha=1 de fondo y tapan la cámara de negro (bug
  histórico, ver sección 7). No se reactivó.
- `detachPreview`/`detachSceneView` comparan identidad de instancia antes de limpiar: Flutter
  puede crear el `PlatformView` nuevo (y llamar `attachPreview`/`attachSceneView`) ANTES de
  que el anterior termine su `dispose()` — sin esa comprobación, el `detach` tardío anulaba
  la referencia recién asignada (pantalla negra intermitente).
- Las rutas de los `.glb` viajan como `creationParams` del `PlatformView`, no por una llamada
  aparte al `MethodChannel` — `CameraPreviewFactory.create()` llama a
  `manager.loadEyeModels(...)` de forma **síncrona**, en la misma invocación que crea el
  `SceneView` y ejecuta `attachSceneView()`. Elimina estructuralmente la carrera que antes
  hacía que el `.glb` no recargara al volver a la pantalla (ya no depende de que un
  `Future.delayed` en Dart gane una carrera contra el attach nativo).

---

## 5. Estado real, sin adornos

| Parte | Estado |
|---|---|
| Reconocimiento de ojos (sección 2) | ✅ Funciona, salvo `eyeShapeStream`/`leftOpenRatio` (campos muertos, no bloqueantes) |
| Carga y posicionamiento del modelo 3D | ✅ Compila; calibración actual (`WIDTH_MULTIPLIER=1.65`/`HEIGHT_OFFSET=0.30`/nudges en `0.0`) sin confirmar visualmente en la última ronda |
| Suavizado/timing (One Euro Filter + predicción adaptativa de latencia) | ✅ Compila; **sin confirmar en dispositivo de forma aislada** — nunca se probó un build limpio sin el crash de la sección 3.4 encima |
| Calentamiento post-reset de `PoseInterpolator` (sección 3.3) | ✅ Compila; sin confirmar en dispositivo |
| Doblado de mesh según curva del párpado | ❌ Desactivado — código presente, no se ejecuta por frame (ver 3.4) |
| Reporte de "flote"/lag del modelo respecto al rostro | ⚠️ **Sin resolver** — ver intento revertido abajo |
| Material anisotrópico de fibra (Fase 4 histórica) | ⏸️ Bloqueado — necesita `matc` (no disponible acá) y `.glb` con tangentes |
| Hair cards proceduales (Fase 3 histórica) | ⏸️ Bloqueado — necesita Blender (no disponible acá) |
| Selección manual de tipo de ojo (`EyeTypePickerSheet`, sección 2.1) | ✅ Compila; UX nueva, sin confirmar en dispositivo |
| Guía de alineación + auto-captura (`EyeAlignmentGuide`/`EyePositionGuidePainter`) | ✅ Compila; sin confirmar en dispositivo |
| Flujo de guardado a cliente (`SaveOptionsSheet`→`ClientPickerSheet`→`trackingRepositoryProvider`) | ✅ Compila; sin confirmar en dispositivo |

**Nota de higiene de repo**: a la fecha de esta actualización, `git status` muestra sin
commitear tanto archivos nuevos del motor de render (`GlbMeshReader.kt`, `LashLineCurve.kt`,
`LashMeshBender.kt`, `PoseInterpolator.kt`) como toda la nueva UX de Flutter descrita en 2.1
(alineación, selector de tipo de ojo, guardado a cliente) — es trabajo real y sustancial
viviendo solo en el working tree, sin respaldo en el historial de git.

### Intento revertido: cámara embebida en Filament (2026-07-22)

Para atacar el "flote" de raíz se intentó meter el feed de cámara DENTRO del mismo render
de Filament (un `SurfaceTexture`/`Stream`/`Texture` propio + un plano de fondo colgado de
`cameraNode`, reemplazando el `PreviewView` separado) — la idea: cámara y modelo 3D
comparten el mismo frame/timestamp, en vez de ser dos `View` independientes compuestas por
separado por SurfaceFlinger (que es la causa estructural real del "flote": el modelo
siempre reacciona a un resultado de MediaPipe más viejo que lo que el preview en vivo ya
está mostrando).

El intento (`CameraBackgroundRenderer.kt`) compiló pero produjo **pantalla completamente
negra** en dispositivo real. Sin logcat disponible para diagnosticar la causa exacta (se
pidió dos veces, no se consiguió), y dado que esto convirtió un problema cosmético en una
regresión total (cámara invisible), **se revirtió por completo**: `PreviewView` está de
vuelta, `CameraBackgroundRenderer.kt` fue eliminado, `CameraXManager`/`CameraPreviewFactory`
volvieron a su forma anterior. El fix de `PoseInterpolator` (sección 3.3) es independiente
y se mantuvo — no toca superficies de render.

**El "flote" sigue sin resolver.** Los 6 fixes de timing (sección 7, ronda 2026-07-21) y la
compensación adaptativa de latencia (sección 3.2/3.3) siguen activos y son la mejor
mitigación disponible hoy, pero nunca se confirmaron limpios en dispositivo. Revisitar la
cámara-en-Filament requiere, como mínimo, un logcat real del intento anterior — repetirlo a
ciegas ya demostró que puede salir peor que el problema original.

---

## 6. Próximo paso

Lo único que desbloquea seguir sin adivinar es un logcat real del dispositivo. Con la
pantalla de cámara abierta:

```
adb logcat -c
# abrir la pantalla de cámara/pestañas, mover la cabeza ~5s
adb logcat -d | grep -E "LashRenderer|FaceRenderPipeline|CameraXManager|CameraPreviewFactory|AndroidRuntime|FATAL"
```

Preguntas concretas que ese log (o un reporte manual específico) tiene que responder, por
separado — no todas mezcladas en un mismo "sigue mal":

1. ¿El modelo carga y se posiciona razonablemente bien (tamaño/lugar), con los valores
   actuales de `WIDTH_MULTIPLIER=1.65`/`HEIGHT_OFFSET=0.30`/nudges en `0.0`?
2. ¿El calentamiento post-reset de `PoseInterpolator` evita el salto ("entra grande y
   encoge") al reaparecer el rostro?
3. ¿El "flote" general mejoró con los fixes de timing + la compensación adaptativa de
   latencia, aunque sea parcialmente, o sigue exactamente igual?
4. ¿Los tres flujos nuevos de Flutter (selección manual de tipo de ojo, guía de alineación
   con auto-captura, guardado a cliente — sección 2.1) funcionan de punta a punta en un
   dispositivo real?

---

## 7. Historial de rondas anteriores (condensado)

**Sesión inicial — reescritura del motor.** Reemplazo de una función monolítica
(`CameraXManager.updateModelPositions`/`applyEyeTransform`, un `LERP_ALPHA` compartido) por
el paquete `render/` actual. Bugs resueltos en esa ronda: cámara en negro (carrera
attach/detach de `PreviewView`), tone mapping/AA tapando la cámara (desactivados), posición
muy alta (`WORLD_SCALE_Y` bajado), intento de proyección real con `CameraNode.viewToRay`
revertido por falta de verificación en dispositivo, y el fix de carrera de `creationParams`
descrito en la sección 4.

**Auditoría "nivel TikTok" — Fases 0-4.** Auditoría completa del pipeline geométrico (no
solo calibración), con 5 hallazgos reales corregidos:
- **Fase 0**: bug de handedness en `EyePoseEstimator` — el espejado de la rotación de
  cabeza usaba `F·R` (una reflexión, determinante -1) en vez de la conjugación correcta
  `F·R·F` para una rotación propia. Corregido.
- **Fase 1** (mayor impacto): `CameraProjection.kt` nuevo — reemplaza el mapeo lineal
  imagen→mundo por des-proyección real de perspectiva, válida a cualquier distancia de
  cámara (antes solo era correcta a la distancia exacta de calibración).
- **Fase 2**: `OneEuroFilter.kt` nuevo reemplaza el EMA/slerp de alpha fijo.
  `EyeLandmarks.opennessRatio` + blink damping por smoothstep.
- **Fase 3** (bloqueada): `tools/blender/generate_lash_cards.py`, generador de hair cards
  con tangentes — nunca ejecutado, no hay Blender en este entorno.
- **Fase 4** (bloqueada): `lash_fiber.mat` con `shadingModel: anisotropic` — nunca
  compilado a `.filamat`, no hay `matc` en este entorno. `MaterialManager` cae a PBR
  genérico mientras tanto.

**Ronda "flote"/lag + crash de producción (2026-07-21).** 6 fixes de timing/unidades
(detallados en la sección 3.5 y el flujo de la 3.2: GPU delegate con fallback a CPU, preview
bajado a 1440×1080, reuso de bitmap crudo por frame, desacople de framerate vía
`PoseInterpolator`+`Choreographer`, recalibración de `*_BETA` en unidades físicas reales,
tangente del párpado por PCA) + intento de doblado real del mesh que causó el
`OutOfMemoryError` documentado en la sección 3.4. Los 6 fixes de timing quedaron activos; el
doblado quedó desactivado.

**Ronda cámara-en-Filament + revert (2026-07-22).** Ver sección 5 — intento de resolver el
"flote" de raíz metiendo la cámara dentro del render de Filament, causó pantalla negra
total, revertido por falta de logcat para diagnosticar. Se mantuvo el fix de
`PoseInterpolator` (independiente, no toca superficies).

**Reauditoría de documentación + relevamiento del working tree (2026-07-24).** Se releyeron
los 19 archivos de `render/` y los archivos de Flutter modificados/nuevos contra el código
real (no contra lo que este documento decía). Se encontraron varios datos desactualizados:
`HEIGHT_OFFSET` real es `0.30` (no `0.53`), los nudges por ojo están en `0.0`/`0.0` (no
`±0.08`), `DEBUG_LOG_POSE` está en `false` (no `true`), y `PoseInterpolator` ya no extrapola
solo linealmente — predice cuadráticamente con 3 muestras más compensación adaptativa de
latencia medida en `CameraXManager` (`smoothedLatencyMs`, no documentada antes). También se
detectó una ronda completa de UX en Flutter sin documentar: extracción de
`eye_tracking_page.dart` en tres módulos (`eye_tracking_alignment.dart`,
`eye_tracking_customization_options.dart`, `eye_tracking_photo_pipeline.dart`) más tres
bottom sheets nuevos (selector de tipo de ojo, opciones de guardado, selector de cliente) —
ver sección 2.1. Ninguno de estos cambios fue verificado en dispositivo durante esta
reauditoría (fue una lectura de código, no una sesión de pruebas) — ver sección 6. Se creó
además [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md), documento dedicado solo al cálculo de
posición/escala de las pestañas.
