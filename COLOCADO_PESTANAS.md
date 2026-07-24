# Colocado de pestañas 3D — cómo se calcula la posición

Este documento explica, archivo por archivo, cómo el paquete nativo `render/`
(Android/Kotlin) decide DÓNDE y CÓMO colocar el modelo `.glb` de pestañas sobre
cada ojo, en cada frame de MediaPipe. Es un corte específico sobre el "colocado
de pestañas" — para el pipeline completo de reconocimiento/tracking de ojos
(cámara → MediaPipe → Flutter) ver [RECONOCIMIENTO_OJOS.md](RECONOCIMIENTO_OJOS.md)
sección 9 (esa sección está desactualizada respecto al cálculo de posición: ya
no usa `WORLD_SCALE_X`/`WORLD_SCALE_Y` lineales, ver sección 4 de este documento).

## 1. Flujo general (por cada frame)

```
FaceLandmarkerResult (478 landmarks + matriz de pose facial)
        │
        ▼
FaceRenderPipeline.compute()  ── orquestador, una vez por ojo
        │
        ├─► 1. EyePoseEstimator       → pose 3D de la CABEZA completa
        ├─► 2. EyeLandmarks.from()    → landmarks del OJO en píxeles
        ├─► 3. EyeAnchorCalculator    → punto de anclaje 2D (dónde "clavar" el modelo)
        ├─► 4. EyePlaneCalculator     → rotación local del ojo (plano + inclinación propia)
        ├─► 5. EyeTransformCalculator → posición 3D real + escala (des-proyección con cámara)
        └─► 6. LashLineCurve.fit      → curva del párpado (doblado de mesh — hoy DESACTIVADO)
        │
        ▼
EyeTrackingFilter (One Euro Filter)  → suaviza jitter, por componente
        │
        ▼
PoseInterpolator  → predice la pose hacia adelante (compensa latencia de MediaPipe)
        │
        ▼
LashRenderer.writeInterpolatedPose()  → escribe position/rotation/scale
                                          en el ModelNode, en cada vsync (~60Hz)
```

Archivos involucrados (`android/app/src/main/kotlin/com/example/test_face/render/`):

| Archivo | Rol |
|---|---|
| `FaceRenderPipeline.kt` | Orquesta el cálculo completo por ojo, por frame. |
| `EyeLandmarks.kt` | Extrae ring (16 pts) + párpado superior + iris, en píxeles. |
| `EyeAnchorCalculator.kt` | Calcula el punto de anclaje 2D del modelo. |
| `EyePoseEstimator.kt` | Convierte la matriz 3D de MediaPipe en `HeadPose`. |
| `EyePlaneCalculator.kt` | Rotación local del ojo (plano/normal). |
| `EyeTransformCalculator.kt` | Posición 3D final + escala (des-proyección de cámara real). |
| `LashLineCurve.kt` | Ajuste cuadrático del párpado (para doblar el mesh). |
| `LashMeshBender.kt` | Aplica esa curva a los vértices del mesh — **desactivado** (ver sección 6). |
| `EyeTrackingFilter.kt` | One Euro Filter por componente (posición/rotación/escala). |
| `PoseInterpolator.kt` | Predicción hacia adelante, desacopla MediaPipe (~20-30Hz) del vsync (~60Hz). |
| `EyeModelSlot.kt` | Estado por ojo: nodo, filtro, interpolador, malla. |
| `RendererConfiguration.kt` | Única fuente de constantes de tuning. |
| `LashRenderer.kt` | Dueño del `SceneView`: carga `.glb`, aplica transform, ilumina. |

## 2. Landmarks del ojo (`EyeLandmarks.kt`)

De los 478 puntos de MediaPipe se toman 16 por ojo (`FaceLandmarkIndices.
LEFT_EYE_RING` / `RIGHT_EYE_RING`) que forman el anillo completo del ojo,
convertidos de coordenadas normalizadas `[0,1]` a píxeles de imagen
(`lm.x() * imageWidth`, `lm.y() * imageHeight`).

El **párpado superior no es un subconjunto fijo de índices**: se calcula
dinámicamente como la mitad del anillo con menor Y (más arriba en la imagen),
más robusto ante variaciones de orientación/numeración de MediaPipe.

También se calcula `opennessRatio = altura_anillo / ancho_anillo` — un proxy
barato de apertura del ojo (no el EAR clásico de 6 puntos), usado más adelante
para atenuar el modelo al parpadear.

## 3. Punto de anclaje 2D (`EyeAnchorCalculator.kt`)

Este es el corazón del posicionamiento. El modelo 3D se centra en
`anchor.point`, así que ese punto debe ser el CENTRO VISUAL de las pestañas,
no el borde del párpado.

```
X del ancla  = promedio de X de todos los puntos del párpado superior
Y del borde  = promedio del 30% de puntos con mayor Y del párpado superior
               (el borde visible, donde "nacen" las pestañas reales)
Y del ancla  = Y_del_borde − altura_del_ojo × HEIGHT_OFFSET
```

`HEIGHT_OFFSET = 0.30` (constante en `RendererConfiguration.kt`). En
coordenadas de imagen Y crece hacia abajo, así que restar sube el ancla hacia
la frente. Con `HEIGHT_OFFSET = 0`, el centro del modelo cae en el borde del
párpado (mitad del modelo quedaría dentro del ojo); con `0.30`, el centro
visual de las pestañas queda ~30% de la altura del ojo por encima del borde,
que es donde se ven naturalmente.

También se calcula la **tangente del párpado** (ajuste PCA de los puntos del
párpado superior alrededor de su centroide) — la dirección de inclinación
real de ESE ojo en particular, usada en el siguiente paso.

## 4. Rotación local del ojo (`EyePlaneCalculator.kt`)

Combina dos fuentes de rotación sin duplicarlas:

- **Pose global de cabeza** (`HeadPose.right/up/forward`), que viene de
  `EyePoseEstimator.fromMediaPipeMatrix()` — convierte
  `FaceLandmarkerResult.facialTransformationMatrixes()` (pose 3D completa que
  resuelve el propio MediaPipe ajustando su modelo facial canónico) al espacio
  de mundo de Filament. Si esa matriz no está disponible en el frame,
  `EyePoseEstimator.fallback()` da una pose neutra (sin rotación, profundidad
  fija) para que el anclaje siga funcionando solo con landmarks 2D.
- **Residuo angular local**: diferencia entre el ángulo de la tangente del
  párpado (paso anterior) y el ángulo de la línea recta esquina-a-esquina del
  ojo. Esto captura la asimetría/curvatura propia de cada ojo que la pose
  global de cabeza no puede, sin volver a girar lo que la cabeza ya giró.

Ese residuo rota `right`/`up` de la cabeza alrededor de `forward` (fórmula de
Rodrigues) para obtener el plano local final del ojo, del que sale el
quaternion de rotación del modelo.

## 5. Posición 3D final y escala (`EyeTransformCalculator.kt`)

1. El ancla en píxeles se normaliza y convierte a NDC (`[-1,1]`), invirtiendo
   Y (imagen crece hacia abajo, NDC/Filament crece hacia arriba).
2. La profundidad Z sale de la posición Z de la cabeza (de `HeadPose`),
   clamped entre `MIN_DEPTH = -2.2` y `MAX_DEPTH = -0.35`.
3. Ese NDC + Z se **des-proyecta a un punto real en el mundo 3D** usando la
   matriz de cámara real de Filament (`CameraProjection.unproject`, extraída
   de `sceneView.cameraNode` en `LashRenderer`) — no un mapeo lineal con
   constantes calibradas a una sola distancia. Esto reemplazó un enfoque
   anterior (`WORLD_SCALE_X`/`WORLD_SCALE_Y`) que se desalineaba al
   acercarse/alejarse de la cámara porque nunca dependía de la profundidad
   real.
4. El **ancho real del ojo en unidades de mundo** se mide des-proyectando
   ambos bordes del ojo (izquierdo/derecho) a la MISMA profundidad y
   calculando la distancia real entre ellos.
5. **Escala del modelo**:
   ```
   corrección_escorzo = min(1 / max(|normal.z|, 0.35), 2.2) × HEAD_TILT_MULTIPLIER
   ancho_deseado      = ancho_ojo_mundo × WIDTH_MULTIPLIER(1.65) × corrección_escorzo
   escala             = ancho_deseado / ancho_natural_del_modelo_glb
   ```
   `normal.z` es qué tan de frente mira el plano del ojo a la cámara: cerca de
   1 = de frente (sin corrección), cerca de 0 = ojo de perfil (se compensa
   dividiendo, con clamp para no explotar en ángulos extremos de tracking
   ruidoso).

## 6. Curva del párpado y doblado de mesh (actualmente inactivo)

`LashLineCurve.fit()` ajusta una parábola (`f(x) = ax² + bx + c`, mínimos
cuadrados) a los puntos del párpado superior, en un sistema de coordenadas
local alineado con la tangente del párpado — captura SOLO la curvatura
adicional respecto a la inclinación promedio (la rotación recta ya la aplica
el paso 4).

`LashMeshBender.bend()` usaría esa curva para desplazar cada vértice del mesh
en el eje Y local (glTF es Y-up) y así seguir la forma real del párpado en vez
de la forma genérica de fábrica del `.glb`.

**Está desactivado.** En `LashRenderer.applyTransform()`
([LashRenderer.kt:263-278](android/app/src/main/kotlin/com/example/test_face/render/LashRenderer.kt#L263-L278))
hay un comentario explicando por qué: reconstruir la lista completa de
vértices (17k-85k objetos según el modelo) y volver a subirla a GPU en CADA
resultado de MediaPipe no fue solo "lento" — tumbó el proceso en dispositivo
(GC bloqueando 600-850ms, heap al tope de 192MB, `OutOfMemoryError`).
Reactivarlo necesita un rediseño que no reasigne buffers por vértice en cada
frame (ej. `ByteBuffer` directo reusado + throttling real), no una versión más
lenta de lo mismo. Hoy el modelo se ve rígido: solo se aplica el transform
(posición/rotación/escala), sin seguir la curvatura fina del párpado.

## 7. Suavizado y predicción (independiente del cálculo de posición)

- **`EyeTrackingFilter`**: un One Euro Filter independiente por componente
  (X, Y, Z, cada componente del quaternion, escala) — limpia el jitter de
  MediaPipe con `minCutoff` alto (3.0Hz en posición) para que el suavizado sea
  casi transparente en reposo y no agregue lag perceptible en movimiento.
- **`PoseInterpolator`**: guarda las últimas 3 muestras suavizadas y predice
  hacia adelante (posición + velocidad + aceleración) el tiempo
  `latenciaMedida + 16ms` (composición de SurfaceFlinger), para que el modelo
  se refresque a la tasa de vsync (~60Hz) aunque MediaPipe entregue resultados
  más lento (~20-30Hz) — el modelo muestra dónde el rostro ESTÁ AHORA, no
  dónde estaba cuando se capturó el frame que MediaPipe acaba de procesar.

## 8. Constantes clave (`RendererConfiguration.kt`)

| Constante | Valor | Efecto |
|---|---|---|
| `HEIGHT_OFFSET` | 0.30 | Cuánto sube el centro del modelo sobre el borde del párpado |
| `WIDTH_MULTIPLIER` | 1.65 | Cuánto más ancho que el ojo real es el modelo |
| `LEFT_EYE_X_NUDGE` / `RIGHT_EYE_X_NUDGE` | 0.0 | Corrección fina de X por ojo (fracción de pantalla) |
| `HEAD_TILT_MULTIPLIER` | 1.0 | Multiplicador extra sobre la corrección de escorzo |
| `EYE_CLOSED_OPENNESS_THRESHOLD` / `EYE_OPEN_OPENNESS_THRESHOLD` | 0.12 / 0.22 | Umbral de apertura para ocultar/atenuar al parpadear |
| `MIN_DEPTH` / `MAX_DEPTH` | -2.2 / -0.35 | Rango de profundidad válido |
| `FACE_DISTANCE_MULTIPLIER` | 1.0 | Multiplicador sobre la posición 3D de la cabeza |

## 9. Puntos abiertos / riesgos conocidos

- **Convención row/column-major de `facialTransformationMatrixes()`**: no
  verificable sin dispositivo real (ver comentario extenso en
  `EyePoseEstimator.kt`). Si el yaw/pitch/roll logueado con `DEBUG_LOG_POSE =
  true` no coincide con el movimiento real de la cabeza, la lectura es
  column-major y hay que transponer `m(r,c)` a `matrix[c*4+r]`.
- **Sentido del eje X local del mesh** en `LashMeshBender`: no verificable sin
  dispositivo si está invertido respecto a la tangente del párpado (doblaría
  espejado en vez de seguir la curva real) — hoy es irrelevante porque el
  doblado está desactivado.
- **Doblado de mesh desactivado** (sección 6) — pendiente de rediseño para no
  reasignar buffers por vértice cada frame.
