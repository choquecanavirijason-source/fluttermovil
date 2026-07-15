# Reconocimiento de ojos — estructura y funcionamiento actual

Este documento explica cómo funciona hoy todo el pipeline de detección/tracking de ojos
(cámara → MediaPipe → Flutter) y qué parte del "reconocimiento de forma de ojo" está rota
o duplicada, con la propuesta concreta para dejarla funcionando.

## 1. Visión general del pipeline

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

Además, **en paralelo y en el lado nativo**, el paquete `render/` (ver sección 9) usa el
resultado crudo de MediaPipe para anclar los modelos 3D de pestañas (`.glb`, vía
SceneView/Filament) a cada ojo — esto no es "reconocimiento", es renderizado AR, pero
consume la misma fuente de landmarks. Este paquete se reescribió por completo en esta
sesión (antes era todo lógica embebida en `CameraXManager.updateModelPositions`/
`applyEyeTransform`) — ver sección 9 para el estado actual, que a la fecha **no está
verificado funcionando en dispositivo** (pendiente de diagnóstico con logcat).

## 2. Archivos involucrados

### Lado nativo (Android / Kotlin)
| Archivo | Rol |
|---|---|
| `android/.../CameraXManager.kt` | **Coordinador delgado** (reescrito): solo CameraX (bind/unbind, selección de cámara, orientación de frame) y el puente hacia MediaPipe. Ya NO contiene matemática de render — delega todo a `render/LashRenderer`. |
| `android/.../FaceLandmarkerHelper.kt` | Configura y ejecuta `FaceLandmarker` de MediaPipe (modelo `face_landmarker.task`, CPU, `LIVE_STREAM`, 1 cara, umbrales de confianza 0.5, **ahora con `outputFacialTransformationMatrixes(true)`**). El callback `onResult` entrega tanto el `Map` para Flutter como el `FaceLandmarkerResult` crudo para el render 3D. |
| `android/.../EyeTrackingResultMapper.kt` | **Sin cambios** — convierte el `FaceLandmarkerResult` a un `Map` con solo los índices que interesan a Flutter: contorno de ojo (8 pts c/u), iris (promedio de 5 pts), óvalo facial (36 pts). El paquete `render/` NO usa este mapper — lee los landmarks crudos directamente con sus propios índices (ver sección 9). |
| `android/.../EyeTrackingPlugin.kt` | Expone `MethodChannel("eye_tracking/methods")` y `EventChannel("eye_tracking/events")` a Flutter; registra el `PlatformView` de la cámara. Sin cambios. |
| `android/.../CameraPreviewFactory.kt` | Crea el `PlatformView` híbrido: `PreviewView` (feed de cámara) + `SceneView` (capa 3D) apilados. Ahora pasa la instancia de vista al hacer `dispose()` (`detachPreview(previewView)` / `detachSceneView(sceneView)`) para evitar una condición de carrera al recrear la vista (ver sección 9.5). |
| `android/.../MainActivity.kt` | Instancia `EyeTrackingPlugin` al arrancar el engine de Flutter. Sin cambios. |
| `android/.../render/*.kt` | **Paquete nuevo** — todo el motor de renderizado 3D de pestañas. Ver sección 9. |

### Lado Flutter (Dart)
| Archivo | Rol |
|---|---|
| `lib/native_eye_tracking_service.dart` | Singleton que envuelve los canales nativos: `trackingStream` (frames crudos → `TrackingFrame`), `eyeShapeStream`, y métodos `startTracking/stopTracking/switchCamera/refreshPreviewBind/loadEyeModels`. |
| `lib/eye_tracking_model.dart` | Modelos `EyePoint` y `TrackingFrame` (parseo del `Map` que llega del canal). |
| `lib/core/recommendation/eye_shape_analyzer.dart` | **Clasificador real de forma de ojo**, 100% en Dart, a partir de la geometría de `leftEye`/`rightEye` (aspect ratio, inclinación canthal, apertura, asimetría). Devuelve un `EyeShape` (Almendrado/Encapotado/Redondo/Rasgado/Asimétricos). |
| `lib/eye_tracking_page.dart` | Pantalla principal: arranca el tracking, dibuja el preview híbrido, llama a `_detectEyeTypeFromFrame` en cada frame, maneja la guía de alineación y la captura de foto. |
| `lib/eye_tracking_mapping_painter.dart` | Dibuja el overlay "abanico" (posiciones 7-13) sobre cada ojo cuando se activa `_showMapping`. |
| `lib/features/catalogo/presentation/providers/catalogo_provider.dart` | `filteredCatalogProvider`: se supone que filtra el catálogo de diseños de pestañas según la forma de ojo detectada, escuchando `eyeShapeStream`. |

## 3. Qué landmarks se usan

`EyeTrackingResultMapper.kt` usa los índices estándar de MediaPipe Face Landmarker (478 pts):

- `leftEyeIdx = [33, 133, 160, 159, 158, 144, 145, 153]`
- `rightEyeIdx = [362, 263, 387, 386, 385, 373, 374, 380]`
- `leftIrisIdx = [468, 469, 470, 471, 472]` (promedio → centro de iris)
- `rightIrisIdx = [473, 474, 475, 476, 477]`
- `faceOvalIdx` → 36 puntos del contorno facial

Todos se devuelven en **coordenadas de píxel de la imagen analizada** (`x * width`, `y * height`),
no normalizadas 0-1. Por eso Flutter necesita `imageWidth`/`imageHeight` del frame para
reproyectar sobre el canvas (`BoxFit.cover`, ver `_imageToCanvas` en el painter y
`_computeEyesAligned` en la página).

## 4. Cómo se usa hoy la forma del ojo (lo que SÍ funciona)

En `eye_tracking_page.dart`, cada frame del stream dispara `_detectEyeTypeFromFrame(frame)`:

1. Si el usuario ya eligió manualmente el tipo de ojo (`_eyeTypeSetManually`), no hace nada.
2. Si no, llama a `EyeShapeAnalyzer.analyze(frame)`:
   - Requiere `frame.faceDetected` y al menos 4 puntos por ojo.
   - Calcula el punto medio de la cara (centroide izq/der) para distinguir esquina interna
     (cerca de la nariz) vs externa de cada ojo — así es robusto sin importar espejado.
   - `aspectRatio = ancho / alto` del ojo.
   - `tiltDeg` = ángulo entre la esquina interna y externa (canthal tilt): positivo = mirada
     elevada ("foxy"), negativo = caída.
   - `asymmetry` = diferencia relativa de aspect ratio entre ambos ojos.
   - Clasifica con umbrales fijos:
     - `asymmetry > 0.32` → **Asimétricos**
     - `tilt <= -6°` → **Encapotado**
     - `aspect < 2.6` → **Redondo**
     - `aspect > 3.6` → **Rasgado**
     - resto → **Almendrado**
3. Busca en `_eyeTypes` (catálogo precargado desde backend, `CatalogKind.eyeType`) el item
   cuyo `name` coincide (case-insensitive) con el nombre clasificado, y actualiza el pill
   `_selectedEyeType` en la UI.

Esto **sí funciona** porque solo depende de `leftEye`/`rightEye` (que Kotlin sí envía).

## 5. Qué está roto / duplicado

`TrackingFrame.fromMap` (línea 67-68 de `eye_tracking_model.dart`) y
`NativeEyeTrackingService.eyeShapeStream` (línea 38-41 de `native_eye_tracking_service.dart`)
esperan que Kotlin mande estas claves en el `Map`:

- `leftEyeShape` (String: `ALMOND` | `ROUND` | `UPTURNED` | `DOWNTURNED` | `UNKNOWN`)
- `leftOpenRatio`, `rightOpenRatio` (double)

**`EyeTrackingResultMapper.kt` nunca incluye esas claves.** Su `map(...)` solo devuelve
`faceDetected`, `imageWidth`, `imageHeight`, `leftEye`, `rightEye`, `leftIris`, `rightIris`,
`faceContour`. Consecuencias:

- `TrackingFrame.leftOpenRatio` / `rightOpenRatio` son **siempre `null`** (no hay ningún
  código Dart que dependa de ellos hoy, así que no rompe nada visible, pero es un campo
  muerto).
- `eyeShapeStream` **nunca emite nada**: `m['leftEyeShape']` siempre es `null` → se castea a
  `''` → el `.where((s) => s.isNotEmpty && ...)` lo descarta siempre.
- `filteredCatalogProvider` (en `catalogo_provider.dart`) hace `await for (shape in
  service.eyeShapeStream)` esperando reclasificar el carrusel de diseños de pestañas cada
  vez que cambia la forma de ojo detectada — **ese `await for` nunca progresa**. El
  provider solo emite la lista completa inicial (`yield allItems`) y se queda ahí para
  siempre. El filtrado automático de diseños compatibles por forma de ojo **no ocurre
  nunca**; el usuario ve todo el catálogo sin filtrar, silenciosamente (no hay error visible
  porque el fallback es "mostrar todo").

En resumen: **hay dos sistemas de clasificación de forma de ojo pensados, y solo uno vive**
(el de Dart, `EyeShapeAnalyzer`, que alimenta el pill de tipo de ojo). El otro (pensado para
vivir en Kotlin y alimentar el filtrado del catálogo) nunca se implementó del lado nativo.

## 6. Cómo dejarlo funcionando

La forma más simple (sin tocar Kotlin, reutilizando el clasificador que ya funciona y ya
está probado) es hacer que `eyeShapeStream` derive del mismo `EyeShapeAnalyzer` que usa la
página, en vez de esperar un campo que Kotlin nunca manda:

1. En `native_eye_tracking_service.dart`, reemplazar la definición de `eyeShapeStream` para
   que mapee `trackingStream` a través de `EyeShapeAnalyzer.analyze(frame)` y tome
   `analysis.shape.catalogName` (o un enum equivalente) en lugar de leer `m['leftEyeShape']`:
   - Filtrar por `analysis.reliable`.
   - Aplicar `.distinct()` igual que ahora para no emitir repetido.
2. Ojo con el **vocabulario**: `EyeShapeAnalyzer` clasifica en español
   (`Almendrado/Encapotado/Redondo/Rasgado/Asimétricos`, que es el mismo vocabulario del
   catálogo `eye_types` del backend), mientras que el contrato viejo de Kotlin usaba
   `ALMOND/ROUND/UPTURNED/DOWNTURNED` (inglés, otro esquema). Hay que unificar
   `filteredCatalogProvider` para comparar contra `catalogName` (español) en vez del
   esquema inglés viejo — y revisar qué valores tiene realmente `tipoOjoCompatible` en los
   `CatalogItem` del backend para que el `compat == shapeLower` funcione.
3. Eliminar los campos muertos `leftOpenRatio`/`rightOpenRatio` de `TrackingFrame` si no se
   van a usar, o implementarlos en `EyeTrackingResultMapper.kt` (relación distancia
   vertical/horizontal entre los puntos 159/145 y 386/374 del ojo, por ejemplo) si de verdad
   se necesita detectar parpadeo/apertura más adelante.

Alternativa (más trabajo, evitar salvo que se necesite performance/consistencia entre
plataformas): mover la clasificación a Kotlin dentro de `EyeTrackingResultMapper.map(...)`,
replicando la misma heurística de `EyeShapeAnalyzer` para que el propio Map incluya
`leftEyeShape` ya calculado. Esto duplicaría la lógica en dos lenguajes y las dos
implementaciones tendrían que mantenerse sincronizadas — por eso se recomienda la opción 1.

## 7. Otras piezas que consumen los mismos datos (no son "reconocimiento" pero comparten pipeline)

- **Guía de alineación de ojos** (`_computeEyesAligned` en `eye_tracking_page.dart`): antes
  de abrir el "asistente de trabajo", reproyecta `leftEye`/`rightEye`/`leftIris`/`rightIris`
  al espacio de pantalla (misma transform `BoxFit.cover` que el painter) y compara contra
  una franja/guía fija en pantalla. Si ambos ojos quedan dentro de la tolerancia durante
  `900ms` seguidos, dispara automáticamente la captura de foto.
- **Overlay de mapeo de pestañas** (`LashMappingPainter`): dibuja el abanico de líneas
  7-13 sobre cada ojo usando el bounding box de `leftEye`/`rightEye`; es solo visual, no
  clasifica nada.
- **Anclaje 3D nativo**: ver sección 9 — se reescribió por completo esta sesión.

## 9. Renderizado 3D de pestañas (paquete `render/`)

Reescritura completa de lo que antes era `CameraXManager.updateModelPositions`/
`applyEyeTransform` (una sola función con toda la matemática embebida y un único
suavizado `LERP_ALPHA` compartido). Ahora es un paquete de 11 archivos en
`android/app/src/main/kotlin/com/example/test_face/render/`, cada uno con una sola
responsabilidad:

| Archivo | Responsabilidad |
|---|---|
| `RendererConfiguration.kt` | Única fuente de las constantes de tuning (suavizados, profundidad, escala, iluminación). Ninguna otra clase declara sus propias constantes. |
| `FaceLandmarkIndices.kt` | Índices canónicos de MediaPipe: anillo completo de 16 puntos por ojo (superset del subconjunto de 8 que usa `EyeTrackingResultMapper` para Flutter) + iris. |
| `EyeLandmarks.kt` | Extrae, desde los landmarks crudos, el anillo del ojo y el párpado superior (calculado dinámicamente: mitad del anillo con menor Y, no por índice fijo). |
| `EyePoseEstimator.kt` | Convierte `FaceLandmarkerResult.facialTransformationMatrixes()` (pose 3D completa de la cabeza que resuelve MediaPipe) a un `HeadPose` (posición + quaternion) en espacio Filament. Si esa matriz no está disponible, `fallback()` da una pose neutra para que el anclaje siga funcionando solo con landmarks 2D. |
| `EyeAnchorCalculator.kt` | Punto de anclaje real: promedio de toda la curva del párpado superior (no el mínimo Y de un solo punto), desplazado hacia arriba por `HEIGHT_OFFSET`. |
| `EyePlaneCalculator.kt` | Plano/normal local de cada ojo: combina la pose de cabeza con la curvatura propia del párpado (residuo angular 2D). |
| `EyeTransformCalculator.kt` | Combina todo lo anterior en posición/rotación/escala final. **Nota de esta sesión**: se intentó calcular la posición proyectando con la cámara real de Filament (`CameraNode.viewToRay`) en vez de una fórmula lineal — no se pudo verificar en dispositivo y terminó ocultando el modelo, así que se revirtió a la fórmula lineal (`WORLD_SCALE_X`/`WORLD_SCALE_Y`). Sigue siendo una aproximación, no una proyección de cámara real. |
| `EyeTrackingFilter.kt` | Suavizado exponencial independiente para posición/rotación/escala (reemplaza el `LERP_ALPHA` único de antes). |
| `EyeModelSlot.kt` | Estado por ojo: nodo cargado, tamaño natural medido, su instancia de `EyeTrackingFilter`. |
| `MaterialManager.kt` | Ajustes PBR defensivos sobre el material del `.glb` (hoy solo fuerza `doubleSided`). |
| `LashRenderer.kt` | Dueño del `SceneView`: entorno/iluminación de estudio (luz indirecta sintética por armónicos esféricos + luz clave reconfigurada), carga de los `.glb`, oculta/muestra los modelos según haya rostro detectado, aplica la transformación filtrada a los nodos. |
| `FaceRenderPipeline.kt` | Orquesta el flujo completo por frame para cada ojo. |

`CameraXManager` solo instancia `LashRenderer` y le reenvía `attachSceneView`/
`detachSceneView`/`loadEyeModels`/`onFaceResult`/`onFaceLost` — no le queda ninguna lógica
de render propia.

### 9.1 Qué cambió de fondo respecto a la versión anterior

- **Pose 3D completa vía MediaPipe**: se activó `outputFacialTransformationMatrixes`, algo
  que antes estaba apagado. Cuando está disponible, la rotación del modelo ya no sale de
  un `atan2` sobre dos landmarks sino de la pose de cabeza completa que resuelve MediaPipe.
- **Profundidad dinámica**: reemplaza el antiguo `FIXED_DEPTH` constante — ahora viene
  (cuando la matriz está disponible) de la pose real, clamped entre `MIN_DEPTH`/`MAX_DEPTH`.
- **Suavizado independiente** por posición/rotación/escala en vez de un único factor.
- **Ocultar sin rostro**: antes el modelo quedaba "congelado" en su última posición cuando
  se perdía el rostro; ahora `LashRenderer.onFaceLost()` lo oculta explícitamente.
- **Iluminación de estudio**: antes el `SceneView` no tenía ninguna luz/entorno configurado
  más allá del default de la librería — se agregó luz ambiental sintética + reconfiguración
  de la luz clave, pensadas para el material especular del `.glb` de pestañas.

### 9.2 Bugs encontrados y corregidos esta sesión (por orden cronológico)

1. **Cámara en negro**: condición de carrera en `attachPreview`/`detachPreview` —
   al recrear la vista de cámara, el `dispose()` de la vista vieja podía anular la
   referencia de la vista nueva si llegaba tarde. Se corrigió comparando identidad de
   instancia antes de limpiar (`detachPreview(view)`/`detachSceneView(view)`).
2. **Tone mapping/antialiasing rompía la transparencia**: se habían activado
   `ToneMapping.ACES` + `FXAA` + MSAA, que son pases de post-procesado de framebuffer
   completo — en un `SceneView` translúcido eso forzaba alfa=1 de fondo y tapaba la cámara
   de negro. Se desactivaron (`configureRenderQuality` quedó como no-op documentado).
3. **Posición muy alta** (a la altura de las cejas): `WORLD_SCALE_Y` (mapeo lineal
   imagen→mundo) amplificaba de más el desplazamiento vertical. Se bajó de `0.8` a `0.4`
   como corrección estimada a partir de una captura de pantalla real.
4. **Intento de proyección de cámara real revertido**: se probó reemplazar la fórmula
   lineal por `CameraNode.viewToRay` (proyección real de Filament) para que la posición no
   dependiera de una constante inventada — no se pudo verificar en dispositivo y el modelo
   dejó de mostrarse por completo, así que se revirtió a la fórmula lineal.

### 9.3 Estado actual (sin verificar en dispositivo)

**A la fecha de este documento, el usuario reporta que el modelo `.glb` sigue sin
renderizarse en pantalla**, incluso después de la última ronda de fixes. No se ha podido
confirmar la causa raíz porque no se cuenta con el logcat filtrado del dispositivo — se le
pidió explícitamente (`adb logcat -d | grep -E "LashRenderer|FaceRenderPipeline|..."`) pero
todavía no se recibió. Hasta tener ese dato, cualquier cambio adicional sobre la posición/
visibilidad sería, otra vez, una corrección a ciegas — que en las últimas rondas causó más
regresiones de las que arregló (ver 9.2, puntos 2 y 4).

**Todo lo que sí está confirmado por compilación** (no por ejecución real): el paquete
`render/` completo compila limpio (`gradlew compileDebugKotlin` y `gradlew :app:assembleDebug`
offline, sin errores) y produce un APK. Compilar no implica que la lógica sea correcta en
tiempo de ejecución — solo que el código es sintácticamente válido y usa las APIs de
Filament/SceneView/MediaPipe con las firmas correctas (verificado decompilando los `.aar`/
`.jar` reales del proyecto, no por documentación).

## 10. Resumen ejecutivo

| Parte | Estado |
|---|---|
| Detección de landmarks (MediaPipe FaceLandmarker) | ✅ Funciona |
| Envío de landmarks a Flutter vía EventChannel | ✅ Funciona |
| Clasificación de forma de ojo (Dart, `EyeShapeAnalyzer`) → pill "tipo de ojo" | ✅ Funciona |
| Guía de alineación antes de capturar foto | ✅ Funciona |
| Overlay visual de mapeo de pestañas | ✅ Funciona |
| Anclaje 3D de modelos de pestañas por ojo (paquete `render/`, ver sección 9) | ⚠️ Compila, **no confirmado en dispositivo** — reportado sin renderizar, pendiente de logcat |
| `eyeShapeStream` / filtrado automático del catálogo por forma de ojo | ❌ Roto (Kotlin nunca envía `leftEyeShape`) |
| `leftOpenRatio` / `rightOpenRatio` (apertura de ojo) | ❌ Nunca poblado (campo muerto, sin consumidores actualmente) |
