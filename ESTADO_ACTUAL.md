# Estado actual — reconocimiento de ojos y renderizado 3D de pestañas

Snapshot del estado del proyecto a la fecha. Cubre las dos partes: el pipeline de
reconocimiento/tracking de ojos (cámara → MediaPipe → Flutter) y el motor de renderizado 3D
de pestañas (`.glb` vía SceneView/Filament). Ver también [RECONOCIMIENTO_OJOS.md](RECONOCIMIENTO_OJOS.md),
que se mantiene como documento vivo de análisis — este archivo es la foto fija de "cómo
quedó" al cierre de esta sesión de trabajo.

## 1. Pipeline de reconocimiento de ojos

```
CameraX (Kotlin, Android)
   └─ ImageAnalysis (960x720) ──► FaceLandmarkerHelper (MediaPipe FaceLandmarker, LIVE_STREAM)
                                        └─ 478 landmarks faciales por frame
                                             └─ EyeTrackingResultMapper.map(...)
                                                  └─ Map<String, Any?> con:
                                                       faceDetected, imageWidth, imageHeight,
                                                       leftEye[8pts], rightEye[8pts],
                                                       leftIris, rightIris, faceContour[36pts]
   └─ EventChannel "eye_tracking/events" ──────────────────────────────────► Flutter
                                                                                  │
                                                                    NativeEyeTrackingService
                                                                    (lib/native_eye_tracking_service.dart)
                                                                                  │
                                                              trackingStream: Stream<TrackingFrame>
                                                                                  │
                              ┌───────────────────────────────────────────────────┼─────────────────────────────┐
                              ▼                                                   ▼                             ▼
                 EyeShapeAnalyzer.analyze(frame)                 LashMappingPainter /                 _computeEyesAligned
                 (lib/core/recommendation/                       eye_tracking_mapping_painter.dart      (guía de alineación
                  eye_shape_analyzer.dart)                       (overlay visual "abanico" 7-13)         antes de capturar foto)
                              │
                              ▼
                 _selectedEyeType (pill "tipo de ojo" en la UI)
```

**No se tocó nada de esto en esta sesión.** Sigue igual que antes:

- ✅ Detección de landmarks (MediaPipe FaceLandmarker) — funciona.
- ✅ Envío de landmarks a Flutter vía `EventChannel` — funciona.
- ✅ Clasificación de forma de ojo 100% en Dart (`EyeShapeAnalyzer.analyze`, geometría de
  `leftEye`/`rightEye`: aspect ratio, canthal tilt, asimetría) → pill "tipo de ojo" en la UI
  — funciona.
- ✅ Guía de alineación antes de capturar foto (`_computeEyesAligned`) — funciona.
- ✅ Overlay visual de mapeo de pestañas (`LashMappingPainter`) — funciona.
- ❌ `eyeShapeStream` / filtrado automático del catálogo por forma de ojo — **roto**.
  `EyeTrackingResultMapper.kt` nunca manda la clave `leftEyeShape` que espera
  `NativeEyeTrackingService.eyeShapeStream`, así que ese stream nunca emite nada y
  `filteredCatalogProvider` (en `catalogo_provider.dart`) se queda esperando para siempre —
  el catálogo de diseños de pestañas nunca se filtra automáticamente por forma de ojo
  detectada (se ve el catálogo completo sin filtrar, sin error visible).
- ❌ `leftOpenRatio`/`rightOpenRatio` en `TrackingFrame` — campo muerto, nunca poblado por
  Kotlin, sin consumidores en Dart hoy.

Detalle completo, con propuesta de arreglo para esos dos últimos puntos, en
[RECONOCIMIENTO_OJOS.md](RECONOCIMIENTO_OJOS.md) secciones 5 y 6.

## 2. Renderizado 3D de pestañas (paquete `render/`)

Se reescribió por completo lo que antes era una sola función (`CameraXManager.
updateModelPositions`/`applyEyeTransform`) con toda la matemática embebida y un único
suavizado compartido (`LERP_ALPHA`). Ahora es un paquete de **14 archivos** en
`android/app/src/main/kotlin/com/example/test_face/render/`:

| Archivo | Responsabilidad |
|---|---|
| `RendererConfiguration.kt` | Única fuente de las constantes de tuning (One Euro Filter, profundidad, escala, openness thresholds, iluminación). |
| `FaceLandmarkIndices.kt` | Índices canónicos de MediaPipe: anillo completo de 16 puntos por ojo + iris. |
| `EyeLandmarks.kt` | Extrae el anillo del ojo, el párpado superior (calculado dinámicamente, no por índice fijo) y `opennessRatio` (proxy de apertura del ojo). |
| `EyePoseEstimator.kt` | Convierte `facialTransformationMatrixes()` de MediaPipe (pose 3D completa de la cabeza) a un `HeadPose` en espacio Filament con conjugación de espejo correcta (`F·R·F`); `fallback()` si esa matriz no está disponible. `DEBUG_LOG_POSE` activado. |
| `EyeAnchorCalculator.kt` | Punto de anclaje real: promedio de toda la curva del párpado superior, desplazado por `HEIGHT_OFFSET`. |
| `EyePlaneCalculator.kt` | Plano/normal local de cada ojo (pose de cabeza + curvatura propia del párpado). |
| `CameraProjection.kt` | **[NUEVO — Fase 1]** Des-proyección real usando las matrices projection/cameraToWorld del `SceneView.cameraNode`. Reemplaza el mapeo lineal `WORLD_SCALE_X`/`_Y` (eliminadas). |
| `EyeTransformCalculator.kt` | Posición/rotación/escala final — usa `CameraProjection.unproject()` para mapear puntos de pantalla a posiciones 3D a la profundidad real de la cabeza; `worldDistanceAtDepth()` para el ancho real del ojo en mundo. |
| `OneEuroFilter.kt` | **[NUEVO — Fase 2]** Filtro 1€ (Casiez, Roussel & Vogel 2012): corte adaptativo a la velocidad instantánea. |
| `EyeTrackingFilter.kt` | 10 instancias de `OneEuroFilter` independientes (3 posición + 4 rotación quaternion + 3 escala), con renormalización de quaternion post-filtro. |
| `EyeModelSlot.kt` | Estado por ojo (nodo, tamaño natural, su filtro). |
| `MaterialManager.kt` | Intenta cargar `lash_fiber.filamat` (material anisotrópico real); fallback a ajuste PBR genérico (`doubleSided`) si no existe. No cachea Material entre ciclos de vida de Engine. |
| `LashRenderer.kt` | Dueño del `SceneView`: iluminación de estudio (SH + key light), carga de `.glb`, blink damping via smoothstep sobre `opennessRatio`, oculta/muestra según haya rostro, aplica la transformación filtrada. |
| `FaceRenderPipeline.kt` | Orquesta el flujo por frame para cada ojo; recibe `CameraProjection` del `SceneView` activo. |

`CameraXManager.kt` quedó como coordinador delgado: solo CameraX (bind/unbind, cámara,
orientación de frame) — toda la lógica de render vive en `LashRenderer`.
`FaceLandmarkerHelper.kt` ahora activa `outputFacialTransformationMatrixes(true)` y entrega
tanto el `Map` para Flutter como el `FaceLandmarkerResult` crudo para el render 3D.
`EyeTrackingResultMapper.kt` (el que habla con Flutter) **no cambió** — el paquete `render/`
lee los landmarks crudos directamente, con sus propios índices.

### Bugs encontrados y corregidos, en orden

1. **Cámara en negro** — condición de carrera entre `attachPreview`/`detachPreview`: al
   recrear la vista de cámara, el `dispose()` de la vista vieja podía anular la vista nueva
   si llegaba tarde. Arreglado comparando identidad de instancia antes de limpiar.
2. **Tone mapping/antialiasing rompía la transparencia** — `ToneMapping.ACES` + `FXAA` +
   MSAA son pases de post-procesado de framebuffer completo; en un `SceneView` translúcido
   eso forzaba alfa=1 de fondo y tapaba la cámara de negro. Desactivados.
3. **Posición muy alta** (a la altura de las cejas) — `WORLD_SCALE_Y` amplificaba de más el
   desplazamiento vertical del mapeo lineal imagen→mundo. Bajado de `0.8` a `0.4`.
4. **Intento de proyección de cámara real revertido** — se probó `CameraNode.viewToRay`
   (proyección exacta de Filament) en vez del mapeo lineal, para no depender de una
   constante inventada. No se pudo verificar en dispositivo y el modelo dejó de mostrarse
   por completo — revertido a la fórmula lineal.
5. **El GLB dejaba de renderizar al volver a la pantalla (salir y regresar por GoRouter)** —
   causa raíz: **no** era ninguna referencia inválida en Kotlin (`SceneView`/`Engine`/
   `ModelLoader`/`ModelNode`/`EyeModelSlot` se destruían y reconstruían correctamente,
   verificado hasta el bytecode de `sceneview-2.1.1`). El fallo era una **carrera de
   temporización**: `loadEyeModels()` se disparaba desde Flutter con `Future.delayed`
   (400/700/1000 ms) apostando a que el nuevo `SceneView` nativo ya estuviera adjuntado —
   sin ninguna garantía de ganar esa carrera en dispositivos lentos. Cuando se perdía,
   `LashRenderer.loadIntoSlot()` descartaba la carga en silencio (`sceneView == null`) y no
   había ningún reintento nativo de respaldo: cámara y MediaPipe seguían funcionando (no
   dependen de esto) pero el modelo quedaba sin cargar para siempre.
   **Fix**: las rutas de los `.glb` ahora viajan como `creationParams` del `PlatformView`
   (`_HybridCameraPreview` → `PlatformViewsService.initExpensiveAndroidView(creationParams:
   ...)`). `CameraPreviewFactory.create()` recibe esas rutas y llama a
   `manager.loadEyeModels(...)` de forma **síncrona**, en la misma invocación nativa que crea
   el `SceneView` y ejecuta `attachSceneView()` — la carrera queda eliminada
   estructuralmente, no mitigada con más delays. Se eliminaron los tres retry-loops
   temporizados que existían en `eye_tracking_page.dart` (`_start()`,
   `_restartCameraFromLifecycle()`, `_resumeEyePreviewAfterAssistant()`).
   Además se agregó instrumentación con `System.identityHashCode()` en
   `CameraPreviewFactory`, `CameraXManager` y `LashRenderer` (attach/detach/load/
   applyTransform) y en `FaceRenderPipeline.compute()`, para poder confirmar en logcat que
   cada entrada a la pantalla crea un `SceneView`/`Engine` nuevo y que el modelo se recarga
   en él de forma determinista.

### Estado real (sin adornos)

- **Compila limpio**: `gradlew compileDebugKotlin` y `gradlew :app:assembleDebug` (offline)
  sin errores, produce APK. Todas las llamadas a Filament/SceneView/MediaPipe se verificaron
  contra las firmas reales decompilando los `.aar`/`.jar` del proyecto (no contra
  documentación), así que no hay errores de API inventada. `flutter analyze` también limpio
  (solo avisos preexistentes no relacionados).
- **Fix de navegación (punto 5) implementado y compilado, pendiente de confirmar en
  dispositivo real**: el usuario va a probar el ciclo entrar→salir→entrar y avisar si el
  patrón de logcat esperado (`create() → attachSceneView → loadEyeModels → loadIntoSlot[...]
  OK`) se repite en cada reingreso.
- **Calibración de tamaño/posición pendiente**: el modelo se ve "un poco pequeño" y "no en su
  posición correcta" en ambos ojos, según reporte del usuario. Sigue siendo trabajo empírico
  guiado por capturas de dispositivo (mismo patrón que el punto 3 de arriba) — ver sección 7.

## 3. Resumen

| Parte | Estado |
|---|---|
| Detección de landmarks (MediaPipe FaceLandmarker) | ✅ Funciona |
| Envío de landmarks a Flutter vía EventChannel | ✅ Funciona |
| Clasificación de forma de ojo (Dart) → pill "tipo de ojo" | ✅ Funciona |
| Guía de alineación antes de capturar foto | ✅ Funciona |
| Overlay visual de mapeo de pestañas | ✅ Funciona |
| Motor de renderizado 3D (`render/`) | ⚠️ Compila; fix de re-render al navegar aplicado (pendiente confirmar en dispositivo); calibración tamaño/posición pendiente |
| `eyeShapeStream` / filtrado automático del catálogo por forma de ojo | ❌ Roto |
| `leftOpenRatio` / `rightOpenRatio` | ❌ Campo muerto |

## 4. Próximo paso

Lo único que desbloquea seguir arreglando el renderizado 3D sin adivinar a ciegas es el
logcat filtrado del dispositivo mientras la pantalla de cámara está abierta:

```
adb logcat -c
# abrir la pantalla de cámara/pestañas, esperar ~5s
adb logcat -d | grep -E "LashRenderer|FaceRenderPipeline|EyeTrackingResultMapper|CameraXManager|AndroidRuntime|FATAL"
```

## 5. Cómo delega `CameraXManager` — confirmación línea por línea

`CameraXManager` delega el 100% de la lógica de render a `render/`. No le queda ningún
cálculo propio — solo maneja CameraX (bind/unbind de cámara) y reenvía datos. Esto es
importante porque en algún momento se dudó de si realmente estaba delegando bien; la
respuesta es sí, y así es como se ve en el código:

```kotlin
private val lashRenderer = LashRenderer(activity, mainHandler)   // instancia el dueño del render

private val helper = FaceLandmarkerHelper(
    onResult = { data, rawResult ->
        onTrackingResult(data)                                   // esto va a Flutter, sin tocar render/
        if (data["faceDetected"] == true && ...) {
            lashRenderer.onFaceResult(rawResult, imageWidth, imageHeight)  // TODO el render pasa por acá
        } else {
            lashRenderer.onFaceLost()
        }
    },
)
```

Los otros tres puentes son igual de directos: `attachSceneView(view)` →
`lashRenderer.attachSceneView(view)`, `detachSceneView(view)` →
`lashRenderer.detachSceneView(view)`, `loadEyeModels(...)` →
`lashRenderer.loadEyeModels(...)`. Ningún cálculo de posición/rotación/escala vive en
`CameraXManager.kt`.

## 6. Flujo de datos detallado, frame por frame

```
FaceLandmarkerResult (crudo, de MediaPipe)
        │
        ▼
LashRenderer.onFaceResult(result, imageWidth, imageHeight)
   — si no hay ningún nodo cargado (leftSlot/rightSlot vacíos), no hace nada
   — envuelve todo en try/catch (si algo falla, oculta y loguea, no crashea)
        │
        ▼
FaceRenderPipeline.compute(result, imageWidth, imageHeight, naturalSpan de cada slot)
   1. result.faceLandmarks()[0]  → lista de 478 landmarks crudos
   2. result.facialTransformationMatrixes() → si MediaPipe la calculó, se pasa a:
        EyePoseEstimator.fromMediaPipeMatrix(matriz, worldScale) → HeadPose (posición+rotación 3D)
      si NO está disponible: EyePoseEstimator.fallback() → pose neutra (sin rotación)
   3. Para cada ojo (izq/der), computeEye(...):
        │
        ▼
      EyeLandmarks.from(landmarks, FaceLandmarkIndices.LEFT/RIGHT_EYE_RING, ...)
         → extrae 16 puntos del anillo del ojo (en píxeles) + el párpado superior
        │
        ▼
      EyeAnchorCalculator.compute(eyeLandmarks)
         → promedio del párpado superior, desplazado por HEIGHT_OFFSET → EyeAnchor
        │
        ▼
      EyePlaneCalculator.compute(headPose, eyeLandmarks, anchor)
         → combina la rotación de cabeza (headPose) con la curvatura propia del
           párpado → EyePlane (normal + quaternion de rotación)
        │
        ▼
      EyeTransformCalculator.compute(headPose, plane, anchor, camera, ..., naturalSpan, xNudge)
         → convierte anchor a NDC: ndcX = 2*nx - 1, ndcY = 1 - 2*ny
         → posición: camera.unproject(ndcX, ndcY, worldZ) — des-proyección real
           de Filament a la profundidad de la cabeza (headPose.position.z,
           clamped entre MIN_DEPTH/MAX_DEPTH)
         → escala: camera.worldDistanceAtDepth(borde_izq, borde_der, ndcY, worldZ)
           × WIDTH_MULTIPLIER / naturalSpan del .glb
           × corrección de foreshortening (eyePlane.normal.z, clamp 0.35, max 2.2×)
         → EyeTransform (position, rotation, scale, opennessRatio) SIN suavizar todavía
        │
        ▼
   devuelve FaceRenderPipeline.Result(left: EyeTransform?, right: EyeTransform?)
        │
        ▼
LashRenderer.applyTransform(slot, transform)
   — damping = opennessDamping(transform.opennessRatio): smoothstep entre
     EYE_CLOSED_OPENNESS_THRESHOLD (0.12) y EYE_OPEN_OPENNESS_THRESHOLD (0.22)
   — si damping ≤ 0: oculta el nodo inmediatamente, no escribe escala 0
   — slot.filter.apply(transform): EyeTrackingFilter suaviza posición/rotación/escala
     con 10 instancias de OneEuroFilter (corte adaptativo, no alpha fijo)
   — scale final = smoothed.scale * damping (blink damping)
   — mainHandler.post { node.isVisible=true; node.position=...; node.quaternion=...; node.scale=... }
     (la escritura final al ModelNode de Filament SIEMPRE en el hilo principal)
```

### 6.1 El otro flujo: carga del `.glb`

```
LashRenderer.loadEyeModels(leftPath, rightPath)  ← llamado desde Flutter vía CameraXManager
   → loadIntoSlot(leftSlot, leftPath) / loadIntoSlot(rightSlot, rightPath)
      1. lee el archivo .glb (bytes)
      2. sv.modelLoader.createModelInstance(buffer) → crea el ModelNode
      3. MaterialManager.tune(sceneView, node) → intenta cargar `lash_fiber.filamat`
         (anisotrópico); si no existe, fallback a PBR genérico (`doubleSided`)
      4. mide node.size → EyeModelSlot.naturalSpan (usado en el cálculo de escala de arriba)
      5. sv.addChildNode(node) → lo agrega a la escena, oculto (isVisible=false) hasta el
         primer frame con rostro detectado
```

### 6.2 Quién guarda estado (lo único con estado en todo `render/`)

`EyeModelSlot` (uno por ojo, viven dentro de `LashRenderer`): `node` (el `ModelNode` de
Filament), `path` (para no recargar si es el mismo), `naturalSpan` (tamaño medido del
`.glb`), y su propio `EyeTrackingFilter` (10 instancias de `OneEuroFilter` — memoria del
suavizado frame a frame). Todo lo demás (`FaceRenderPipeline`, `EyeAnchorCalculator`,
`EyePlaneCalculator`, `EyeTransformCalculator`, `EyePoseEstimator`, `CameraProjection`) son
objetos `object` o clases sin estado propio — funciones puras que reciben datos y devuelven
datos.

`RendererConfiguration` es la única fuente de las constantes que estos cálculos usan
(`HEIGHT_OFFSET`, `WIDTH_MULTIPLIER`, `MIN_DEPTH`/`MAX_DEPTH`, `*_MIN_CUTOFF`/`*_BETA`
para los One Euro Filters, `EYE_CLOSED/OPEN_OPENNESS_THRESHOLD` para blink damping,
iluminación, etc.) — si algo hay que calibrar, se toca ahí y en ningún otro lado.

**Constantes eliminadas** respecto a la versión anterior: `WORLD_SCALE_X`, `WORLD_SCALE_Y`
(reemplazadas por `CameraProjection`), `POSITION_LERP`, `ROTATION_LERP`, `SCALE_LERP`
(reemplazadas por One Euro Filter con `*_MIN_CUTOFF`/`*_BETA`), `FIXED_DEPTH`.

**Conclusión**: `CameraXManager` no tiene lógica de render — si el modelo no se ve bien en
pantalla no es un problema de "falta de delegación", es de calibración o algún bug en el
cálculo dentro de `render/` que todavía no se pudo diagnosticar sin el logcat (ver sección 4).

## 7. Calibración pendiente: tamaño y posición del modelo

Reporte del usuario: el modelo se veía "un poco pequeño" y "muy abajo" respecto al ojo, en
ambos ojos (izquierdo y derecho). Ajustes aplicados en `RendererConfiguration.kt` (única
fuente de verdad, ver sección 6.2) a partir de esa confirmación:

| Constante | Antes | Ahora | Motivo |
|---|---|---|---|
| `WIDTH_MULTIPLIER` | `1.15` | `1.35` | Reporte: modelo "un poco pequeño" en ambos ojos. |
| `HEIGHT_OFFSET` | `0.10` | `0.14` | Reporte confirmado: "muy abajo". Historial: `0.15` (muy arriba) → `0.06` (muy abajo) → `0.10` (seguía abajo) → `0.14`. |
| `WORLD_SCALE_X` / `WORLD_SCALE_Y` | `0.6` / `0.4` | **eliminadas** | Reemplazadas de raíz por proyección de cámara real en la Fase 1 del motor (ver sección 8) — dejaron de existir, no hace falta calibrarlas más. |
| `RIGHT_EYE_X_NUDGE` / `LEFT_EYE_X_NUDGE` | `0.02` / `0` | sin cambio | No se reportó desvío lateral. |

Este ajuste de tamaño/altura sigue siendo empírico — depende de cómo se vea en la cámara
real del dispositivo. **Pendiente de confirmar en dispositivo.**

## 8. Reescritura del motor de render (auditoría "nivel TikTok") — Fases 0-4 implementadas

Sesión aparte, más profunda: auditoría completa del pipeline geométrico (no solo de
calibración) pidiendo un motor "prácticamente indistinguible de TikTok". Se encontraron
errores conceptuales reales (no de calibración) y se corrigieron en 5 fases, todas
compiladas y verificadas (`gradlew compileDebugKotlin`, exit 0):

- **Fase 0**: `EyePoseEstimator.DEBUG_LOG_POSE` activado. Además, auditoría encontró un bug
  real de handedness: el espejado de la rotación de cabeza (cámara frontal) negaba la
  componente X de las 3 columnas de la matriz por igual — matemáticamente eso es una
  reflexión (determinante -1), no una rotación propia. La conjugación correcta de un espejo
  sobre una rotación es `F·R·F`, no `F·R`; corregido en `EyePoseEstimator.fromMediaPipeMatrix`
  (el vector `right` ahora conserva su X y niega Y/Z, al revés de antes). Pendiente:
  confirmar en dispositivo que el yaw/pitch/roll ahora sigue el movimiento real de la cabeza.
- **Fase 1** (la de mayor impacto): `EyeTransformCalculator` ya NO usa un mapeo lineal
  imagen→mundo (`WORLD_SCALE_X`/`_Y`, eliminadas). Nueva clase `CameraProjection.kt`
  extrae la proyección/vista real del `SceneView.cameraNode` (API verificada contra el
  bytecode real de SceneView 2.1.1) y des-proyecta el punto de pantalla a la posición 3D
  correcta a la profundidad real de la cabeza — válido a cualquier distancia de cámara, no
  solo a la distancia en la que se calibraron las constantes viejas. El ancho del ojo en
  mundo también se mide des-proyectando los dos bordes reales, no con una regla de tres.
- **Fase 2**: nuevo `OneEuroFilter.kt` (Casiez, Roussel & Vogel 2012) reemplaza el EMA/slerp
  de alpha fijo en `EyeTrackingFilter` — corte adaptativo a la velocidad instantánea, sin
  jitter en reposo NI lag en movimiento rápido a la vez (imposible con un alpha constante).
  Nuevo `EyeLandmarks.opennessRatio` (proxy de apertura del ojo) + damping suave
  (smoothstep) en `LashRenderer.applyTransform` para el comportamiento de parpadeo, en vez
  de que la geometría casi cerrada lo hiciera de forma implícita y descontrolada.
- **Fase 3**: `tools/blender/generate_lash_cards.py` — generador procedural nuevo (no
  existía ningún script de Blender en el repo). Reemplaza la técnica de los `.glb` actuales
  (geometría SÓLIDA: 21 000-143 000 triángulos por ojo, 0 texturas, 0 tangentes en los 6
  diseños inspeccionados con un parser de glTF binario hecho ad-hoc para esta auditoría) por
  hair cards (tarjetas con textura, un orden de magnitud más baratas) con tangentes
  exportadas y 3 sub-mallas por ojo (interna/centro/externa) bajo un nodo raíz. **No
  ejecutado ni verificado en Blender real** (no hay Blender en este entorno) — necesita
  correrse y ajustarse visualmente por un artista antes de reemplazar los `.glb` actuales.
- **Fase 4**: `android/app/src/main/materials/lash_fiber.mat` — material Filament con
  `shadingModel: anisotropic` real (no el PBR metallic-roughness genérico que importa
  SceneView del glTF). `MaterialManager` intenta cargar el `.filamat` compilado
  (`assets/materials/lash_fiber.filamat`) y cae de vuelta al ajuste PBR anterior si no
  existe — no rompe nada mientras no se haya corrido `matc` (herramienta del Filament SDK,
  no instalada en este entorno) ni regenerado los `.glb` con tangentes (Fase 3).

**Pendiente real, honesto**: Fases 0-2 son código Kotlin puro, compilado y listo para probar
en dispositivo. Fases 3-4 dependen de herramientas externas (Blender, `matc`) que no están
disponibles en este entorno — están especificadas y con el wiring de código ya listo, pero
necesitan que alguien las ejecute y verifique visualmente antes de reemplazar los assets.