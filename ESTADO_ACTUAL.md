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
| `EyeLandmarks.kt` | Extrae el anillo del ojo, el párpado superior (índice FIJO — `ring[8:16]`, orden anatómico de MediaPipe, corregido 2026-07-24, ver 3.3.2) y `opennessRatio` (alto/ancho del anillo, proxy de apertura). |
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
| `EyeModelSlot.kt` | Estado por ojo: `node`, `path`, `naturalSpan`, `rootLocalY` (raíz real del mesh en Y, ver [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.1), `filter`, `interpolator`, `rawMesh`, `geometry`. |
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
      2. GlbMeshReader.read(path) → RawMesh (incluye minY, la raíz real del mesh);
         Geometry.Builder(...).build(engine) → renderableNode.setGeometry(geometry)
         [swap de geometría, costo ÚNICO por carga] → EyeModelSlot.rootLocalY = rawMesh.minY
      3. MaterialManager.tune(node, sv)  [DESPUÉS del swap — setGeometry no garantiza
         preservar el material instance original]
      4. mide node.size → EyeModelSlot.naturalSpan
      5. sv.addChildNode(node), oculto (isVisible=false) hasta el primer rostro detectado
```

`EyeModelSlot` (uno por ojo, vive dentro de `LashRenderer`) es el único estado real de todo
`render/`: `node`, `path`, `naturalSpan`, `rootLocalY`, `filter` (10× `OneEuroFilter`),
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

### 3.3.1 Corrección de raíz del modelo (2026-07-24)

**Síntoma reportado con 4 capturas reales en dispositivo**: el modelo aparecía
consistentemente a la altura de la CEJA en todos los ángulos de cabeza probados,
nunca en el párpado — el patrón idéntico en los 4 ángulos descartaba un bug de
rotación/handedness (eso se vería como pestañas corridas de forma distinta según
el ángulo, no siempre arriba).

Diagnóstico hecho sin dispositivo (parseando los `.glb` reales de
`assets/modelos/` con un script propio, más decompilar `sceneview-android`
v2.1.1 contra su fuente real en GitHub) — ver el detalle completo y la evidencia
en [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.1. Resumen: el motor
anclaba el CENTRO GEOMÉTRICO del bounding box del modelo (vía `node.
centerOrigin()`, que resultó ser un no-op — confirmado en bytecode) en el punto
de anclaje del ojo, pero un histograma de densidad de vértices mostró que la
raíz visual real de cada pestaña está muy por debajo de ese centro. Encima,
`HEIGHT_OFFSET=0.30` sumaba otro 30% de la altura del ojo hacia arriba sobre
esa premisa ya incorrecta — la suma empujaba la pestaña hacia la ceja.
`EyeModelSlot.modelYRatio`, que según su comentario debía compensar esto, era
también código muerto (se escribía, nunca se leía).

**Fix aplicado** (compilado limpio con `gradlew compileDebugKotlin`, **sin
confirmar visualmente en dispositivo real** — no hay uno conectado en este
entorno, `adb devices` no lista ninguno):
- `GlbMeshReader.RawMesh` expone `minY` (la raíz real del mesh, de los vértices).
- `EyeModelSlot.rootLocalY` reemplaza a `modelYRatio` (eliminado).
- `EyeTransformCalculator.compute()` corrige la posición final con
  `position - eyePlane.up * (scaleFactor * rootLocalY)` para que sea la RAÍZ,
  no el centro, la que quede en el punto de anclaje.
- `node.centerOrigin()` se eliminó de `LashRenderer.loadIntoSlot` (no-op).
- `RendererConfiguration.HEIGHT_OFFSET` bajó de `0.30` a `0.0` (con la raíz ya
  bien anclada, `0.0` es el punto de partida anatómicamente correcto).

**Confirmado en dispositivo real (2026-07-24, continuación)** — ver 3.3.2 para el
detalle de la sesión de instrumentación en dispositivo que validó este fix.

### 3.3.2 Corrección de partición párpado superior/inferior + confirmación en dispositivo real (2026-07-24)

Con el fix de 3.3.1 ya instalado, el usuario probó en dispositivo real y reportó
que la altura mejoró (ya no en la ceja en ninguna foto) pero seguía sin caer en
la posición EXACTA en distintos ángulos de cabeza, sobre todo con roll (cabeza
inclinada de costado).

**Causa**: `EyeLandmarks.from()` separaba "párpado superior" con un umbral
dinámico de Y de imagen (`ring.filter { it.y <= meanY }`). Los 16 índices de
`FaceLandmarkIndices.LEFT/RIGHT_EYE_RING` tienen en cambio un orden anatómico
FIJO (primeros 8 = párpado inferior, últimos 8 = superior — verificado cruzando
contra landmarks conocidos 159/145 y 386/374). Con la cabeza derecha el umbral
de Y coincidía por casualidad con esa partición; con roll, "Y menor en imagen"
deja de ser "arriba anatómico", así que el umbral mezclaba puntos de los dos
párpados de forma dependiente del ángulo — desplazando el ancla calculada.

**Fix**: `EyeLandmarks.from()` ahora usa `ring.subList(8, 16)` (partición fija
por índice) con fallback al umbral de Y solo si el anillo no tiene los 16
puntos esperados.

**Confirmación en dispositivo real, con instrumentación**: con un `Infinix
X669` conectado por USB, se agregaron logs temporales (`Log.i`) en
`EyeAnchorCalculator`/`EyeTransformCalculator` imprimiendo todos los valores
intermedios del cálculo (landmarks crudos, `anchor`, `ndc`, `scaleFactor`,
posición final), se recompiló e instaló, y se le pidió al usuario sostener el
rostro frente a la cámara. Se capturaron `adb exec-out screencap` + `adb logcat
-d` en el mismo instante, dos veces: una vez de frente y otra con la cabeza en
roll extremo (~80-90°). En ambos casos:
- La captura de pantalla muestra la pestaña naciendo en la línea de pestañas
  real, no en la ceja.
- Los números del log confirman que `upperLid` sigue siendo exactamente
  `ring[8:16]` (no se mezcla con el párpado inferior) y que `anchor` cae
  dentro de la huella real del anillo del ojo, incluso con roll extremo.
- `worldZ` apareció siempre clampeado en `MAX_DEPTH=-0.35` — es el
  comportamiento esperado sosteniendo el teléfono muy cerca de la cara (típico
  en selfie), no un bug.

Ambos fixes (3.3.1 y este) quedan **confirmados con evidencia real de
dispositivo**, no solo compilación. Los logs de diagnóstico temporales se
retiraron del código después de la confirmación. Pendiente, no bloqueante:
ajuste fino estético de `HEIGHT_OFFSET`/`WIDTH_MULTIPLIER`; verificación de la
convención de la matriz de pose (`DEBUG_LOG_POSE`); logcat del "flote" general
(sección 6, sigue sin diagnosticar); confirmar visualmente los otros 9 modelos
de `assets/modelos/` (solo se probó uno, "Redondo"/cateye, en esta sesión).

### 3.3.3 Calidad visual: MSAA + volumen vertical (2026-07-24, misma sesión)

Con la posición ya confirmada, el usuario comparó el render contra un filtro AR
de referencia (pestañas gruesas/voluminosas) y reportó que el propio se veía
"con ruido"/como estática, fino. Dos causas, dos fixes, ambos probados en vivo
en el `Infinix X669` con `adb screencap`:

1. **Sin anti-aliasing**: `configureRenderQuality()` era no-op desde el bug
   histórico de "ToneMapping+FXAA+MSAA tapan la cámara de negro" (sección 7).
   Se activó SOLO `View.MultiSampleAntiAliasingOptions` (MSAA) — multisamplea
   color+alpha por sub-muestra, no post-procesa el framebuffer resuelto como
   FXAA/ToneMapping. Confirmado en dispositivo: cámara sigue visible, fibras
   de pestaña notablemente más limpias.
2. **Escala isotrópica**: el `scaleFactor` (X/Y/Z igual) no permitía dar más
   volumen vertical sin también estirar el ancho más allá de las esquinas del
   ojo. Se separó una escala Y propia (`HEIGHT_VOLUME_MULTIPLIER = 1.4`) en
   `EyeTransformCalculator.compute()`, y la corrección de `rootLocalY` (3.3.1)
   se actualizó para usar esa misma escala Y (no la de X/Z), porque el
   desplazamiento de la raíz es a lo largo de ese eje.

Resultado confirmado con screenshot en vivo: fibras de pestaña legibles, no
ruido, sin regresión de la cámara. Detalle completo en
[COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.3.

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
| `WIDTH_MULTIPLIER` | `1.65` | Multiplicador de ancho del modelo sobre el ancho real del ojo (escala X/Z). |
| `HEIGHT_VOLUME_MULTIPLIER` | `1.4` (nuevo 2026-07-24) | Multiplicador EXTRA solo en Y (volumen/grosor vertical), separado de X/Z — ver 3.3.3. |
| `HEIGHT_OFFSET` | `0.0` (bajado de `0.30` el 2026-07-24, ver 3.3.1) | Fracción de la altura del ojo que se desplaza la RAÍZ del modelo hacia arriba desde el borde del párpado (ver [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 3/5.1). |
| `RIGHT_EYE_X_NUDGE` / `LEFT_EYE_X_NUDGE` | `0.0` / `0.0` | Corrección fina por ojo (fracción de pantalla) — hoy sin corrección aplicada. |
| `FACE_DISTANCE_MULTIPLIER` / `HEAD_TILT_MULTIPLIER` | `1.0` / `1.0` | Ganchos cableados, hoy no-op — reservados. |
| `EYE_CLOSED_OPENNESS_THRESHOLD` / `EYE_OPEN_OPENNESS_THRESHOLD` | `0.12` / `0.22` | Rango de smoothstep del blink damping. |
| `INDIRECT_LIGHT_INTENSITY` / `KEY_LIGHT_INTENSITY` | `15000` / `100000` | Intensidad de luz ambiental sintética (armónicos esféricos) / luz clave direccional. |
| `MSAA_SAMPLE_COUNT` | `4` | **Con consumidor desde 2026-07-24** — `configureRenderQuality()` lo usa para `View.MultiSampleAntiAliasingOptions` (ver 3.3.3). |

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
- `configureRenderQuality()` en `LashRenderer` **ya NO es no-op** (cambio 2026-07-24, ver
  sección 3.3.3 y [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.3): activa SOLO
  `View.MultiSampleAntiAliasingOptions` (MSAA), confirmado seguro en dispositivo real. NO se
  reactivaron `ToneMapping`/`FXAA` — esos siguen siendo el bug histórico documentado (pases de
  post-procesado de framebuffer completo que en un `SceneView` translúcido fuerzan alpha=1 de
  fondo y tapan la cámara de negro, ver sección 7). MSAA es distinto: multisamplea color+alpha
  antes de resolver, no post-procesa.
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
| Carga y posicionamiento del modelo 3D | ✅ **Confirmado en dispositivo real** (2026-07-24, ver 3.3.1/3.3.2): anclaje de raíz + partición fija párpado superior/inferior, validados con logcat+screenshot en frontal y roll extremo. `WIDTH_MULTIPLIER=1.65`/`HEIGHT_OFFSET=0.0`/nudges en `0.0` — ajuste fino estético pendiente pero no bloqueante |
| Suavizado/timing (One Euro Filter + predicción adaptativa de latencia) | ✅ Compila; **sin confirmar en dispositivo de forma aislada** — nunca se probó un build limpio sin el crash de la sección 3.4 encima |
| Calentamiento post-reset de `PoseInterpolator` (sección 3.3) | ✅ Compila; sin confirmar en dispositivo |
| Doblado de mesh según curva del párpado | ✅ **Activo y confirmado en dispositivo real** (2026-08-02) — ver historial al final de este documento y [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) secciones 5.4/5.5/6 |
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

**Actualización 2026-07-24**: ya hubo un dispositivo real conectado (`Infinix X669`) y se usó
para confirmar con evidencia (logcat + screenshot) que el bug de posicionamiento vertical
("pestaña en la ceja") y el bug de partición por roll están resueltos — ver 3.3.1/3.3.2. Lo
que sigue de esta lista ya NO tiene ese bloqueo estructural; falta repetir el mismo patrón
(dispositivo conectado + logcat) para el resto de las preguntas pendientes:

```
adb logcat -c
# abrir la pantalla de cámara/pestañas, mover la cabeza ~5s
adb logcat -d | grep -E "LashRenderer|FaceRenderPipeline|CameraXManager|CameraPreviewFactory|AndroidRuntime|FATAL"
```

Preguntas concretas que ese log (o un reporte manual específico) tiene que responder, por
separado — no todas mezcladas en un mismo "sigue mal":

1. ~~¿El fix de anclaje de raíz resolvió que la pestaña apareciera en la ceja?~~ **Confirmado
   ✅ 2026-07-24** (3.3.1/3.3.2). Pendiente menor: ¿hace falta subir `HEIGHT_OFFSET` un poco
   por estética, o probar los otros 9 modelos de `assets/modelos/` (solo se probó "Redondo")?
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

**Fix de anclaje de raíz — "pestaña en la ceja" (2026-07-24, continuación).** A partir de
4 capturas reales en dispositivo reportando el modelo consistentemente a la altura de la
ceja en todo ángulo de cabeza, se diagnosticó la causa raíz SIN dispositivo: se parsearon
los 10 `.glb` reales de `assets/modelos/` con un script propio y se decompiló
`sceneview-android` v2.1.1 (bytecode + fuente real en GitHub). Se confirmó que el motor
anclaba el centro geométrico del bounding box del modelo (vía un `node.centerOrigin()` que
resultó ser un no-op) en vez de la raíz visual real de la pestaña (identificada por
histograma de densidad de vértices, muy por debajo del centro en los 10 modelos) — y que
`EyeModelSlot.modelYRatio`, que según su comentario debía compensar esto, era código muerto
(se escribía, nunca se leía). Fix aplicado: `GlbMeshReader.RawMesh.minY` +
`EyeModelSlot.rootLocalY` + corrección en `EyeTransformCalculator.compute()` para anclar la
raíz real (no el centro) en el punto de anclaje del ojo; `HEIGHT_OFFSET` bajado de `0.30` a
`0.0`; `node.centerOrigin()` eliminado. Compila limpio (`gradlew compileDebugKotlin`). **Sin
confirmar en dispositivo real** — no hay ninguno conectado en este entorno (`adb devices`
vacío) — pendientes también, por la misma razón, la verificación de la convención de la
matriz de pose (`DEBUG_LOG_POSE`) y el logcat del "flote" (sección 6). Ver detalle completo
y evidencia en [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.1.

**Fix de partición párpado superior/inferior + confirmación en dispositivo real (2026-07-24,
continuación).** El usuario probó el fix anterior en dispositivo real: la altura mejoró (ya
no en la ceja) pero seguía sin caer exacto según el ángulo, sobre todo con roll. Causa:
`EyeLandmarks.from()` separaba "párpado superior" por umbral de Y de imagen en vez del orden
anatómico FIJO de los 16 índices del anillo (primeros 8 = inferior, últimos 8 = superior,
verificado contra landmarks 159/145 y 386/374) — el umbral se rompe con roll. Fix:
`ring.subList(8, 16)`. Con un `Infinix X669` conectado por USB, se instrumentaron
`EyeAnchorCalculator`/`EyeTransformCalculator` con logs temporales, se recompiló, instaló, y
se capturó `adb exec-out screencap` + `adb logcat -d` en el mismo instante que el usuario
sostenía el rostro frente a la cámara — de frente y con roll extremo (~80-90°). Ambas
capturas confirman la pestaña naciendo en la línea de pestañas real, con los números del log
coincidiendo con la imagen. **Ambos fixes de esta ronda (raíz + partición) quedan
confirmados con evidencia real de dispositivo**, no solo compilación — primera vez en varias
rondas que esto pasa (ver rondas anteriores, todas terminaron "sin confirmar en
dispositivo"). Logs de diagnóstico retirados después de confirmar. Ver detalle en
[COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) secciones 5.1/5.2.

**Fix de calidad visual: MSAA + volumen vertical (2026-07-24, misma sesión, continuación).**
El usuario comparó el resultado contra un filtro AR de referencia (pestañas gruesas) y
reportó que el propio se veía como "estática" — fino y con ruido. Se reactivó `MSAA` (solo
multisampling, no `FXAA`/`ToneMapping` — esos siguen siendo el bug histórico que tapaba la
cámara) y se separó una escala Y propia (`HEIGHT_VOLUME_MULTIPLIER=1.4`) del `scaleFactor`
de X/Z, para dar volumen sin estirar el ancho. Ambos cambios probados en vivo en el mismo
`Infinix X669` con `adb screencap`: cámara sigue visible, fibras de pestaña legibles en vez
de ruido. Ver [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.3.

**Ajuste fino: X centrado pero Y de esquina (2026-07-24, misma sesión, continuación).** Con
la posición ya "casi" bien, se re-instrumentó `EyeAnchorCalculator` y se capturó logcat +
screenshot de la misma pose reportada. Los números mostraron que `anchor.x` promediaba TODOS
los puntos del párpado superior (centrado) pero `anchor.y` (`edgeLidY`) promediaba solo el
30% con mayor Y — que para un párpado en forma de arco son casi siempre las ESQUINAS, no el
centro — un desfase real de ~8px confirmado con datos de logcat. Fix: `anchor.y` ahora usa
`meanY` (mismo conjunto y peso que `meanX`), sin sesgo de esquina. Confirmado con screenshot
antes/después de la misma pose. Ver [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.4.

**Reactivación del doblado de mesh (LashMeshBender) + dos bugs de coordenadas encontrados y
arreglados (2026-08-02).** En algún punto fuera de esta conversación se reactivó
`LashMeshBender.bend()` en `LashRenderer.applyTransform()` (cómputo en hilo de MediaPipe,
subida a GPU despachada al principal, throttle `LASH_BEND_MIN_INTERVAL_NANOS`, guard
`bendPending`, suavizado `LASH_BEND_SMOOTHING`) — pero la pestaña se veía recta, no curva.
Diagnóstico: `LashLineCurve.fit()` ajustaba la parábola alrededor del ancla de RENDER
(`anchor.point`), desplazada ~68% del ancho del ojo por `NOSE_AVOID_SHIFT` — pero
`LashMeshBender` muestrea centrado en el propio mesh, así que casi todos los vértices caían
fuera del rango real ajustado y la curva se extrapolaba linealmente (recta) en vez de seguir
la parábola. Fix 1: se agregó `EyeAnchor.lidCenter` (centroide SIN desplazar) y
`lashCurveAnchorOffsetPx` (la corrección de coordenadas entre ambos) — `LashLineCurve.fit()`
ahora se ajusta contra `lidCenter`, `LashMeshBender` suma el offset a su muestreo. Con eso más
`LASH_BEND_STRENGTH` subido de 0.25 a 1.0 (el valor bajo era un parche para el bug anterior),
apareció un SEGUNDO bug: la pestaña salía como una raya diagonal recta hacia la ceja, no una
curva. Fix 2: `LashLineCurve.deviationAt()` extrapolaba más allá del rango fitteado sumando
`pendiente × distancia` — lineal, pero SIGUE creciendo sin límite; con `anchorOffsetPx` grande
y estilos "wing" (Cat Eye) que extienden el mesh bien más allá del ojo, esa distancia era
grande y la extrapolación se disparaba. Se cambió a sostener la desviación PLANA (constante,
sin término adicional) más allá del rango — la única opción que no puede explotar. Ambos fixes
confirmados en dispositivo real (Infinix X669) con logcat (`bendApply deviationSample`) +
screenshot en el mismo instante, antes/después. Resultado final: pestaña siguiendo la curva
real del párpado, sin raya ni temblor. Ver
[COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) secciones 5.4/5.5/6.

**Asimetría entre ojos: mismo `.glb` cargado en los dos ojos para diseños del backend
(2026-08-07).** Reportado: con un diseño elegido del catálogo del backend, un ojo sigue bien
la curva del párpado y el otro se ve deformado, con el ala apuntando al lado equivocado. Se
revisaron los 9 archivos de `render/` — todo el cálculo de ancla/tangente/rotación es
agnóstico de ojo izq/der, correcto. La causa real está en Dart: `eye_tracking_page.dart`
carga el MISMO `.glb` para `leftPath`/`rightPath` cuando el diseño viene del backend (solo
guarda un archivo por diseño, a diferencia del catálogo local que sí tiene pares
`cateyeleft`/`cateyeright` distintos). Se verificó con un script propio (Node, comparando el
perfil de profundidad Z de los 5 pares locales) que esos 5 pares SÍ están correctamente
espejados por el artista — no hay que tocarlos. Fix: `RawMesh.mirroredAcrossX()` en
`GlbMeshReader.kt` (posición X, normal X, winding de triángulos, minX/maxX, todo antes de que
`LashMeshBender` use la malla), activado en `LashRenderer.loadEyeModels()` solo cuando
`leftPath == rightPath` (señal explícita — el catálogo local con archivos distintos no se
toca). Compila limpio. **Sin confirmar en dispositivo real** — pendiente confirmar que
espejar el ojo DERECHO (elección no verificable sin dispositivo) es el lado correcto. Ver
[COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.7.

**Falloff C1-continuo: de "esquina/deformación" a curva redonda, con bug de signo corregido
(2026-08-05, documentado en esta misma pasada).** Reportado: "se doblan, se deforman... quiero
que tenga forma redonda". Causa: el fix de 5.5 (`deviationAt()` plana más allá del rango
fitteado) es continua en VALOR pero no en DERIVADA — la pendiente cae de golpe a 0 en el
borde, y un shear vertical con esa discontinuidad produce un pico/pliegue visible en la
silueta. Fix: la pendiente decae suavemente a cero con un smoothstep sobre una distancia
derivada del ancho ajustado (no una constante inventada), y `deviationAt()` es la integral
cerrada de esa pendiente — C1 exacto en el borde. Al implementar esto se encontró y corrigió
un bug de signo: el término de la integral se sumaba sin importar el lado, pero del lado de
`minLocalX` (`localX` decreciente) tiene que restarse — sin eso, la derivada saltaba de signo
justo en ese borde, el mismo tipo de defecto que el fix buscaba eliminar. Verificado
numéricamente (Node, no solo inspección): continuidad de valor y derivada confirmada hasta
1e-6 en ambos bordes. Compila limpio. **Sin confirmar visualmente en dispositivo real.** Ver
[COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.6.

**"Sale volando" en la comisura exterior: envolvente en Z, falloff más ancho, suavizado
vectorial completo (2026-08-08).** Reportado: el modelo encaja bien en el lagrimal pero se
despega/"sale volando" hacia la comisura exterior, sobre todo en Cat Eye. Tres causas: (1)
`LashMeshBender.bend()` no tocaba Z — el ala se quedaba plana frente a la cámara en vez de
retroceder hacia la órbita; fix: caída cuadrática en Z derivada de la geometría de una esfera
(`x²/2R`), con un clamp a `radiusPx` que se agregó después de verificar numéricamente que la
aproximación diverge sin límite para `|x|>R` (rutinario en el ala) — mismo patrón que el bug de
extrapolación de la sección 5.5, detectado a tiempo esta vez. (2) `LashLineCurve.
falloffDistancePx()` aplanaba la curva demasiado rápido (0.5× el rango ajustado) para alas que
caen mayormente fuera de ese rango; subido a 1.75× (`LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER`). (3)
El EMA de suavizado en `LashRenderer.applyTransform()` solo interpolaba Y, no X/Z — cada
vértice se movía en diagonal en vez de en línea recta hacia su posición nueva; corregido para
blend los tres ejes con el mismo `k`. Compila limpio. **Sin confirmar visualmente en
dispositivo real.** Ver [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.8.

**Sistema de estilos por diseño (`LashStyleConfig`) + doblado sin alocar por frame
(2026-08-08).** Motivación: `HEIGHT_OFFSET`/`NOSE_AVOID_SHIFT`/la envolvente en Z de 5.8 eran
`const val` fijos — correcto con un solo estilo, pero el catálogo tiene diseños genuinamente
distintos (Cat Eye vs. Wispy) que necesitan esos valores DISTINTOS por diseño. Además,
`LashMeshBender.bend()` + el suavizado EMA reconstruían una `List<Geometry.Vertex>` nueva por
resultado de MediaPipe (~30Hz/ojo) — la causa original del OOM de la sección 3.4. Fix en 4
partes: (1) `LashStyleConfig.kt` nuevo — `data class` con `heightOffset`/`noseAvoidShift`/
`zDepthDropRadiusFraction`/`foxyLiftMultiplier` + 3 presets (Cat Eye/Natural/Wispy) resueltos
por `styleId` con fallback seguro a `DEFAULT`; hilado por `FaceRenderPipeline` hasta
`EyeAnchorCalculator`/`LashMeshBender`. (2) `LashMeshBender.bendInPlace()` reemplaza a
`bend()`: escribe en un buffer PRE-ASIGNADO y funde doblado+suavizado en un solo pase (antes
dos `.map` encadenados). Límite honesto verificado con `javap` sobre el `.aar` de
sceneview-android: `Geometry.Vertex`/`Float3` son inmutables (todos los campos `final`), así
que no hay forma de mutar un vértice sin bypassear esa API — lo que sí se elimina es la
`List` nueva por frame y la doble instanciación de `Vertex` por vértice (ahora 1 sola). (3)
Double-buffer en `EyeModelSlot` (`bufferA`/`bufferB`) para que el suavizado EMA pueda leer el
frame anterior mientras se escribe el nuevo, sin aliasing. (4) `setLashStyle` nuevo en el
`MethodChannel` (`EyeTrackingPlugin` → `CameraXManager` → `LashRenderer.setStyle`), invocado
desde Dart (`NativeEyeTrackingService.setLashStyle`) junto con `loadEyeModels` en
`eye_tracking_page.dart`, derivando el `styleId` del nombre visible del diseño. Compila limpio
(`gradlew compileDebugKotlin`) y `flutter analyze` sin errores sobre los 2 archivos Dart
tocados. **Sin confirmar visualmente en dispositivo real.** Ver
[COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.9.

**Regresión confirmada y revertida con dispositivo real disponible (2026-08-08, misma
sesión).** Con un Infinix X669 conectado por `adb` durante esta sesión, se pudo por fin
verificar visualmente 5.8/5.9 — y la pestaña salía disparada en diagonal hacia la ceja en vez
de seguir el párpado, en ambos ojos (capturado con `adb exec-out screencap` + logcat en vivo,
no a partir de una descripción). Sin tiempo para aislar cuál de los dos cambios nuevos era el
causante exacto, se revirtieron los dos a la vez: `LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER` de
1.75 a 0.5 (el valor ya confirmado en 5.5-5.7) y `LASH_BEND_DEPTH_DROP_STRENGTH` de 1.0 a 0.0
(envolvente en Z apagada), más los 3 presets de `LashStyleConfig` neutralizados a `DEFAULT`
(sus valores originales sumaban más variables sin controlar a la vez). Recompilado, reinstalado
con `flutter build apk --debug` + `adb install -r`, y **confirmado visualmente en el mismo
dispositivo**: la pestaña vuelve a apoyarse sobre el párpado. Ver
[COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.10 para el diagnóstico completo y la
lección de proceso (verificar cada cambio nuevo por separado en vez de apilar varios sin
confirmar).

**Calibración fina post-regresión: raíz al borde + ala sin levantarse (2026-08-08, misma
sesión).** Con 5.10 resuelto, quedaba una leve tendencia del ala exterior a levantarse hacia la
ceja. Ajustes: `HEIGHT_OFFSET` de -0.15 a -0.05 y `LASH_BEND_STRENGTH` de 1.0 a 0.5 (amortigua
la parábola, sobre todo en los extremos del ala). Se revisó `LashMeshBender.kt` y se confirmó
que no hay ningún ajuste manual de pendiente artificial — `slope` sale directo de
`curve.slopeAt(...) * strength`. Nota de transparencia: por la convención de signos de
`EyeAnchorCalculator` (Y de imagen crece hacia abajo), `-0.15f → -0.05f` matemáticamente REDUCE
la corrección hacia abajo del ancla, no la aumenta — lo contrario de "bajar la raíz" tomado
literalmente; se probó igual como punto de partida y se verificó el resultado real en
dispositivo en vez de asumir la dirección por el nombre. Recompilado, reinstalado, y
**confirmado visualmente en dispositivo real** (Infinix X669) en dos poses (de frente y con la
cabeza inclinada): la pestaña sigue el párpado en ambos ojos sin el levantamiento hacia la ceja.
Ver [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.11.

**Raíz exactamente en el borde palpebral (2026-08-08, misma sesión).** El usuario reportó que la
raíz seguía sin tocar el borde real del párpado con `HEIGHT_OFFSET=-0.05f`. Para medirlo con
precisión (no a ojo sobre la foto completa), se recortó y amplió 2× la zona de los ojos con
`ffmpeg` sobre el mismo `adb screencap` — confirmó un espacio de piel visible entre la raíz y el
párpado en los dos ojos. Causa: la sospecha de signo ya anotada en la entrada anterior era
correcta — `-0.05f` baja el ancla MENOS que `-0.15f`, no más. Subido a `-0.22f`; comparado el
mismo recorte antes/después: la raíz ahora traza directo sobre la línea real del párpado, sin
el espacio visible y sin pasarse hacia el globo ocular. Confirmado en dispositivo real (Infinix
X669). Lección de proceso: para calibraciones de pocos píxeles, una captura completa a
resolución de pantalla no alcanza — hace falta recortar/ampliar antes de comparar. Ver
[COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.12.

**Corrección longitudinal hacia el canto lateral (2026-08-08, misma sesión).** Reportado: el
conjunto de pestañas queda demasiado cerca del canto medial/lagrimal. Causa: `NOSE_AVOID_SHIFT`
(ya existente) desplaza solo en X puro, no a lo largo de la dirección real medial→lateral del
ojo — con roll de cabeza esa dirección tiene componente en Y que el shift horizontal no cubre.
Fix aditivo en `EyeAnchorCalculator.compute()`: `cornerA`/`cornerB` (ya existentes, extremos en
X del anillo del ojo) SON el canto medial/lateral; se calcula
`normalize(lateralCanthus−medialCanthus) * (distancia(cantos) × LATERAL_LASH_OFFSET)` y se suma
al ancla ya calculada. Nuevo `RendererConfiguration.LATERAL_LASH_OFFSET=0.08f` +
`LashStyleConfig.lateralLashOffset`. Al ser proporcional a la distancia REAL entre cantos (no
píxeles fijos ni offset de mundo) y pasar por la misma des-proyección real que el resto del
ancla, escala correctamente a cualquier distancia de cámara sin tocar `EyeTransformCalculator`,
escala, rotación, curva ni el `.glb`. Compila limpio, confirmado en dispositivo real sin
crashes ni distorsión.

**Calibración iterativa de `LATERAL_LASH_OFFSET` hasta valor final (2026-08-08, misma
sesión).** Con la corrección de arriba implementada, se calibró el valor en dispositivo real
con captura recortada/ampliada en cada paso: `0.08` (correcto pero insuficiente, feedback del
usuario) → `0.16` (seguía insuficiente) → `0.28` (sobre-corrigió, la punta del ala se pasaba
hacia la sien/nacimiento del pelo en un ojo) → **`0.20` confirmado**: ambos ojos con el ala
contenida dentro del contorno real del ojo, simétrico, sin pico ni deformación, logcat limpio.
Valor final de esta ronda. Ver [COLOCADO_PESTANAS.md](COLOCADO_PESTANAS.md) sección 5.13.


flutter run --dart-define=LID_DEBUG=true --dart-define=LID_DEBUG_HQ=true

