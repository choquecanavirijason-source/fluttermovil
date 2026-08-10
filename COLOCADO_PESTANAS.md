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
        └─► 6. LashLineCurve.fit      → curva del párpado (doblado de mesh — ACTIVO, ver sección 6)
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
| `LashMeshBender.kt` | Aplica esa curva a los vértices del mesh — **activo** (ver sección 6). |
| `LashStyleConfig.kt` | Parámetros por estilo de diseño (Cat Eye/Natural/Wispy...), ver sección 5.9. |
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

El **párpado superior es un subconjunto FIJO de índices** (corregido
2026-07-24, ver sección 5.2): dentro de los 16 puntos del anillo, los
primeros 8 trazan el párpado inferior y los últimos 8 el superior — orden
anatómico constante de MediaPipe, verificado cruzando contra landmarks
individuales muy conocidos (159/145 y 386/374). Antes se calculaba
dinámicamente como "la mitad del anillo con menor Y en la imagen", que
parecía más robusto pero en realidad se rompía con la cabeza en roll (Y de
imagen deja de ser "arriba anatómico" cuando la cabeza se inclina de
costado).

También se calcula `opennessRatio = altura_anillo / ancho_anillo` — un proxy
barato de apertura del ojo (no el EAR clásico de 6 puntos), usado más adelante
para atenuar el modelo al parpadear.

## 3. Punto de anclaje 2D (`EyeAnchorCalculator.kt`)

Este es el corazón del posicionamiento. `anchor.point` es el punto de mundo
donde debe renderizar la **raíz real** de la pestaña (ver sección 5.1 —
corregido el 2026-07-24; hasta esa fecha se asumía que el modelo se
centraba en `anchor.point` por su centro geométrico, una asunción que
resultó falsa y causaba que la pestaña apareciera a la altura de la ceja).

```
X del ancla  = promedio de X de todos los puntos del párpado superior
Y del borde  = promedio del 30% de puntos con mayor Y del párpado superior
               (el borde visible, donde "nacen" las pestañas reales)
Y del ancla  = Y_del_borde − altura_del_ojo × HEIGHT_OFFSET
```

`HEIGHT_OFFSET = 0.0` (constante en `RendererConfiguration.kt`, bajada de
`0.30` el 2026-07-24 — ver sección 5.1). En coordenadas de imagen Y crece
hacia abajo, así que restar sube el ancla hacia la frente. Con
`HEIGHT_OFFSET = 0`, y como ahora se ancla la RAÍZ real del modelo (no su
centro geométrico), la raíz de la pestaña nace exactamente en el borde del
párpado — anatómicamente correcto. `HEIGHT_OFFSET > 0` solo agregaría un
margen estético por encima del borde, si hiciera falta tras confirmar en
dispositivo.

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

### 5.1 Corrección de raíz (2026-07-24) — por qué la pestaña aparecía en la ceja

**Síntoma reportado con capturas reales en dispositivo**: en 4 fotos con
distintos ángulos de cabeza, el modelo aparecía consistentemente a la altura
de la ceja, nunca del párpado — el mismo patrón en los 4 ángulos, lo que
descartaba un bug de rotación/handedness de la matriz de cabeza (eso se
vería como pestañas rotadas o corridas de forma distinta según el ángulo,
no siempre arriba).

**Diagnóstico (sin necesidad de dispositivo, con los `.glb` reales del
repo)**:
1. Se parsearon los 10 modelos de `assets/modelos/` con un script propio
   (mismo formato que lee `GlbMeshReader.kt`). El bounding box en Y de los
   10 es perfectamente simétrico (`minY = -maxY` exacto) — el pivote SÍ
   está en el centro geométrico del bounding box.
2. Pero un **histograma de densidad de vértices por banda de Y** mostró que
   la masa real del mesh (la banda densa donde nace la fibra, la "raíz"
   visual de la pestaña) está concentrada cerca del `minY` — el origen
   local (Y=0, el centro geométrico) cae bastante por encima de la raíz
   real, ya adentro del abanico de fibras.
3. Decompilando `sceneview-android` v2.1.1 (bytecode del `.aar` + fuente
   real en GitHub) se confirmó que `node.centerOrigin()` — llamado en
   `LashRenderer.loadIntoSlot` con argumentos por defecto — es la fórmula
   `position += Float3(0,0,0) * size`, un **no-op literal**. Y aunque no lo
   fuera, `LashRenderer.writeInterpolatedPose()` sobreescribe
   `node.position` por completo en cada vsync, así que cualquier ajuste que
   `centerOrigin()` hiciera se perdería en el primer frame visible de
   todos modos. Esa llamada nunca tuvo efecto en el render final.
4. `EyeModelSlot.modelYRatio` (el mecanismo que, según su comentario, debía
   compensar esto) también era código muerto: se escribía en
   `loadIntoSlot` pero nunca se leía en ningún otro lugar — el comentario
   que afirmaba que `writeInterpolatedPose` lo usaba "para subir el modelo
   media-altura" describía un comportamiento que jamás ocurría en el código
   real.

**Conclusión**: el motor anclaba el CENTRO GEOMÉTRICO del bounding box del
modelo en `anchor.point`, pero la raíz visual real está bien por debajo de
ese centro — y encima `HEIGHT_OFFSET=0.30` sumaba otro 30% de la altura del
ojo hacia arriba, sobre una premisa (centrado) que ya era incorrecta. La
suma de ambos errores empujaba la pestaña hacia la ceja, en cualquier
ángulo de cabeza — consistente con lo reportado.

**Fix aplicado** (código, compilado y verificado con
`gradlew compileDebugKotlin`, **sin confirmar visualmente en dispositivo
real** — no hay uno disponible en este entorno):
- `GlbMeshReader.RawMesh` ahora expone `minY` (el punto más bajo real del
  mesh, calculado de los vértices, igual que ya se hacía para `minX`/`maxX`).
- `EyeModelSlot.rootLocalY` reemplaza al `modelYRatio` muerto: se fija en
  `loadIntoSlot` a `rawMesh.minY`, en las mismas unidades locales que
  `naturalSpan`.
- `EyeTransformCalculator.compute()` ahora recibe `rootLocalY` y corrige la
  posición final: `position - eyePlane.up * (scaleFactor * rootLocalY)` —
  desplaza el origen del modelo hacia ARRIBA (ya que `rootLocalY` es
  negativo) la distancia justa para que sea la RAÍZ, no el origen/centro,
  la que quede exactamente en `anchor.point`. Usa el mismo `scaleFactor`
  isotrópico que ya escala X/Y/Z del modelo, así que no hace falta ningún
  factor de conversión nuevo.
- `node.centerOrigin()` se eliminó de `LashRenderer.loadIntoSlot` (no-op
  confirmado, ver punto 3 arriba).
- `RendererConfiguration.HEIGHT_OFFSET` bajó de `0.30` a `0.0` — con la raíz
  ya anclada correctamente, `0.0` es el punto de partida anatómicamente
  correcto (raíz exactamente en el borde del párpado), sin necesidad de
  ningún valor "mágico" que compensara el bug de arriba.

**Confirmado en dispositivo real (2026-07-24, continuación)**: con un
`Infinix X669` conectado, se instrumentó `EyeAnchorCalculator`/
`EyeTransformCalculator` con logs temporales (`Log.i`), se pidió al usuario
sostener el rostro de frente frente a la cámara, y se capturó `adb
exec-out screencap` + `adb logcat -d` en el mismo instante. La captura
muestra la pestaña naciendo justo en la línea de pestañas real (no en la
ceja), y los números del log (`edgeLidY`/`anchor` calculados a partir de
`upperLid`/`ring` crudos) coinciden con la posición visible en la imagen.
Confirma que este fix (raíz real, no centro geométrico) resolvió el síntoma
original. Los logs de diagnóstico ya se quitaron del código. Pendiente:
ajuste fino estético de `HEIGHT_OFFSET`/`WIDTH_MULTIPLIER` si hiciera falta,
y la verificación de la convención de la matriz de pose (`DEBUG_LOG_POSE`,
sección 9) — ninguna de las dos es bloqueante.

### 5.2 Corrección de partición párpado superior/inferior (2026-07-24) — por qué variaba según el ángulo

**Síntoma reportado con capturas reales en varios ángulos**: con la raíz ya
corregida (5.1), la pestaña seguía sin quedar en la posición exacta cuando
la cabeza estaba inclinada de costado (roll), aunque en ángulos frontales
se veía bien.

**Diagnóstico**: `EyeLandmarks.from()` separaba "párpado superior" con un
umbral dinámico (`ring.filter { it.y <= meanY }`, es decir, la mitad del
anillo con menor Y de IMAGEN). Los 16 índices de `FaceLandmarkIndices.
LEFT_EYE_RING`/`RIGHT_EYE_RING` tienen en cambio un orden anatómico FIJO:
los primeros 8 trazan el párpado inferior y los últimos 8 el superior —
verificado cruzando contra landmarks individuales muy citados en cualquier
cálculo de EAR/parpadeo con MediaPipe (159/145 para el ojo izquierdo,
386/374 para el derecho: los "top" conocidos caen siempre en los últimos 8,
los "bottom" conocidos siempre en los primeros 8). Con la cabeza derecha,
el umbral de Y de imagen coincide por casualidad con esa partición fija —
pero con roll, "Y menor en imagen" deja de ser "arriba anatómico", así que
el umbral mezclaba puntos de los dos párpados de forma dependiente del
ángulo, desplazando el ancla y la tangente calculados.

**Fix aplicado**: `EyeLandmarks.from()` ahora usa la partición fija por
índice (`ring.subList(8, 16)`) cuando el anillo tiene los 16 puntos
esperados, con fallback al umbral de Y solo si algún índice quedó fuera de
rango (caso degenerado, no debería pasar en operación normal).

**Confirmado en dispositivo real**: con el mismo `Infinix X669`, se probó
un roll de cabeza extremo (~80-90°, cabeza casi de costado) y se comparó
logcat + screenshot del mismo instante. La partición `upperLid` seguía
siendo exactamente `ring[8:16]` (no se mezclaba con el párpado inferior), y
el ancla calculada cayó dentro de la huella real del anillo del ojo en
ambos ojos, sin desplazamiento sistemático hacia otro lado por el ángulo.
Con un roll tan extremo los ojos aparecen naturalmente entrecerrados
(afecta la precisión de los landmarks de MediaPipe en sí, no algo que este
motor pueda corregir), pero no se observó el patrón de error dependiente
del ángulo que motivó este fix.

### 5.3 Calidad visual: MSAA + volumen vertical (2026-07-24)

Con la posición ya confirmada (5.1/5.2), el usuario reportó que el render se veía
"con ruido"/como estática — fino y poco parecido a una pestaña real, comparado
contra un filtro AR de referencia con pestañas gruesas y voluminosas.

**Causa 1 — sin anti-aliasing**: `LashRenderer.configureRenderQuality()` era un
no-op desde una ronda anterior, por un bug histórico donde activar
`ToneMapping`+`FXAA`+MSAA juntos tapaba de negro el preview de cámara (`SceneView`
translúcido). Las fibras de pestaña son geometría muy fina (1-2px en pantalla) y
sin ningún anti-aliasing se ven como ruido/estática. Se probó reactivar SOLO MSAA
(`View.MultiSampleAntiAliasingOptions`, no FXAA ni ToneMapping — MSAA multisamplea
color+alpha por sub-muestra, no post-procesa el framebuffer ya resuelto como sí
hacen FXAA/ToneMapping) en dispositivo real (Infinix X669): la cámara sigue
visible, sin pantalla negra, y las fibras se ven notablemente más limpias.

**Causa 2 — escala isotrópica**: `WIDTH_MULTIPLIER` solo puede agrandar el ancho
sin también estirar la altura más allá de proporción, porque el `scaleFactor`
anterior era isotrópico (mismo valor en X/Y/Z). Se separó la escala del eje Y
(`RendererConfiguration.HEIGHT_VOLUME_MULTIPLIER = 1.4`, ver
`EyeTransformCalculator.compute()`) para dar más volumen/grosor vertical sin
extender la pestaña más allá de las esquinas del ojo en X. La corrección de
`rootLocalY` (5.1) se actualizó para usar esta misma escala Y (no el
`scaleFactor` de X/Z), ya que el desplazamiento de la raíz es a lo largo de ese
eje.

**Confirmado en dispositivo real**: ambos cambios juntos, probados con
`adb screencap` en vivo — resultado visiblemente más parecido a pestañas reales
(fibras legibles, no ruido), sin regresión de la cámara. El estilo de pestaña
seleccionado en la UI (catálogo, fuera del alcance de este documento) también
influye mucho en qué tan "dramático"/denso se ve — estilos como "wispy"/"natural"
son finos por diseño del asset, no por un bug de render.

### 5.4 Ajuste fino: ancla X centrado pero Y sesgado a la esquina (2026-07-24)

Con 5.1/5.2/5.3 ya confirmados, el usuario reportó que la posición seguía "casi"
bien pero no exacta — un desfase pequeño, no el bug grande de la ceja.

**Diagnóstico con logcat + screenshot de la misma pose**: `EyeAnchorCalculator.
compute()` calculaba `anchor.x` como el promedio de TODOS los puntos del párpado
superior (centrado), pero `anchor.y` (`edgeLidY`) como el promedio del 30% de
puntos con MAYOR Y — para un párpado con forma de arco (más alto en el centro,
más bajo en las esquinas, la forma real de un ojo), ese 30% con mayor Y son casi
siempre las ESQUINAS, no una muestra representativa de la línea de pestañas en
el centro. Con datos reales de logcat (pose de cabeza inclinada hacia abajo): el
párpado superior iba de Y=300 en el centro a Y=314 en las esquinas, pero
`edgeLidY` salía en 312.5 (esquina) mientras `meanX` (con el mismo conjunto de
puntos) caía en el centro — un desfase real de ~8px en la imagen de análisis
(480×640), con X centrado pero Y de esquina.

**Fix**: `anchor.y` ahora usa `meanY` (promedio de Y de TODOS los puntos del
párpado superior, el MISMO conjunto y peso que ya usa `meanX`) en vez de
`edgeLidY` — quedan geométricamente consistentes entre sí, sin sesgo de esquina.

**Confirmado en dispositivo real**: misma pose (cabeza inclinada hacia abajo),
antes/después comparados por screenshot — la pestaña ahora sigue la curva real
del párpado en vez de quedar desplazada hacia la altura de la esquina.

### 5.5 Fix de la extrapolación sin límite — de "raya diagonal" a curva real (2026-08-02)

Con 5.1-5.4 aplicados y `LASH_BEND_STRENGTH` subido a `1.0` (sin amortiguar), el doblado
reactivado NO se veía como una curva exagerada ni recta — se veía como una **raya diagonal
recta** saliendo del ojo hacia la ceja/frente, confirmado con logcat (`bendApply
deviationSample` entre -2 y -5.5px, moderado) + screenshot en el mismo instante.

**Causa**: `LashLineCurve.deviationAt()` extrapolaba MÁS ALLÁ del rango `[minLocalX,
maxLocalX]` (el rango real de los landmarks del párpado que `fit()` ajustó) sumando
`pendiente_del_borde × distancia` — una extrapolación lineal, pensada como alternativa segura
a dejar seguir la parábola completa (que aceleraría mucho peor). Pero lineal SIGUE creciendo
sin límite con la distancia. `anchorOffsetPx` (5.1-5.4, necesario para que la curva se ajuste
en el centroide real del párpado) es grande (~68% del ancho del ojo), así que la mayoría de
los vértices del mesh — sobre todo el "wing" de un estilo Cat Eye, que por diseño se extiende
bien más allá del ancho natural del ojo — caían lejos del rango fitteado. Sobre esa distancia
grande, `pendiente × distancia` se disparaba a decenas de píxeles: la raya diagonal.

**Fix**: `deviationAt()` ahora se sostiene PLANA (el valor exacto del borde, sin ningún
término adicional) más allá del rango fitteado, en vez de seguir extrapolando linealmente —
no hay datos reales del párpado ahí, así que no hay base para asumir que la curva sigue
cambiando; sostenerla plana es la única opción que no puede explotar sin importar cuán lejos
esté `localX` del rango real. `slopeAt()` (usada solo para inclinar la normal/iluminación, no
la posición) se dejó igual — no crece con la distancia, así que no había nada que arreglar
ahí, y mantenerla evita un salto visual de iluminación justo en el borde del clamp.

**Confirmado en dispositivo real**: misma pose, antes/después por screenshot — la pestaña
ahora sigue la curva real del párpado (dentro del rango con datos reales) y se mantiene
estable/plana en la parte "wing" en vez de dispararse. Se ve como una pestaña real.

### 5.6 Falloff C1-continuo — de "esquina triangular"/deformación a curva redonda (2026-08-05)

Con 5.5 confirmado, apareció un defecto más sutil pero visible reportado por el usuario como
"se doblan, se deforman... quiero que tenga forma redonda" — una esquina/pico/pliegue en el
extremo del rango fitteado, más notorio en el "ala" de un estilo Cat Eye.

**Causa exacta**: el fix de 5.5 sostiene `deviationAt()` PLANA (constante, igual al valor del
borde) más allá de `[minLocalX, maxLocalX]` — continua en VALOR (C0) pero con la PENDIENTE
saltando de golpe de `2a·borde+b` a `0` exactamente en el borde (discontinuidad C1).
Geométricamente, un shear vertical (`LashMeshBender`, solo mueve `y`, no rota) con una función
de derivada discontinua produce, en la silueta del mesh, exactamente un pico/pliegue en ese
punto — no es un defecto del asset ni de la topología del `.glb`, es consecuencia matemática
directa de la discontinuidad C1 en la función de deformación.

**Fix**: la PENDIENTE ahora decae suavemente a cero con un `smoothstep` (`u²(3−2u)`, la misma
función que ya usa `LashRenderer.opennessDamping`) sobre una distancia derivada del propio
ancho ajustado (mitad de `[minLocalX,maxLocalX]` — no una constante inventada), y
`deviationAt()` es la integral cerrada de esa pendiente decayente: continuidad **C1 exacta**
en el borde (mismo valor y misma pendiente que la parábola ahí mismo) y sigue acotada más
allá (se aplana en una meseta), preservando la garantía de 5.5 de que nunca puede explotar.
Verificado numéricamente (no solo por inspección): con una parábola de prueba, el salto de
valor en el borde es ~1e-3 (error de paso finito, no un salto real) y la pendiente analítica
coincide con la derivada numérica hasta 1e-6 en ambos bordes (`minLocalX`/`maxLocalX`).

**Bug de signo encontrado y corregido en el mismo fix**: la primera versión de esta integral
sumaba `edgeSlope · falloffDist · integral(u)` sin importar de qué lado del rango caía
`localX`. Eso es correcto del lado de `maxLocalX` (`localX` crece en la misma dirección en que
se integra la pendiente), pero del lado de `minLocalX` (`localX` decrece, alejándose del borde
hacia -x) el término tiene que RESTARSE — recorrer esa dirección acumula la integral con signo
contrario, igual que caminar "hacia atrás" sobre una función. Sin el signo correcto,
`F'(minLocalX⁻)` salía `-edgeSlope` en vez de `+edgeSlope`: un salto de signo en la derivada
justo en el borde que se buscaba hacer continuo — geométricamente, el mismo tipo de pliegue
que este fix pretendía eliminar, pero ahora solo del lado de `minLocalX`. Corregido con un
`sign = if (signedDist < 0f) -1f else 1f` explícito en `deviationAt()`.

Ningún número mágico nuevo: todo sale de `minLocalX`/`maxLocalX` (ya existentes, del propio
ajuste de la curva) y de una función smoothstep que ya usaba el proyecto. `MIN_FALLOFF_PX` es
solo un piso de seguridad numérica (evitar división por cero en un ajuste degeneradamente
angosto), no un parámetro de ajuste visual.

Nota: en una iteración anterior de este mismo diagnóstico se probó además reemplazar el shear
vertical de `LashMeshBender` por un bend con ROTACIÓN (marco tangente/normal 2D, pivotando
desde `raw.minY`) — matemáticamente más correcto para una cinta continua, pero este asset es
un ABANICO de fibras individuales (muchas altas, punta lejos de la raíz en Y); rotar cada
vértice según la pendiente LOCAL de su propia columna X hacía que fibras vecinas giraran
cantidades distintas y sus puntas se enroscaran/cruzaran entre sí (confirmado como
visualmente incorrecto). Por eso `LashMeshBender` se mantiene como shear vertical puro
(`x`/`z` intactos, solo `y' = y + desviación(x)`) — el falloff C1-continuo de esta sección es
lo que realmente elimina el pico, no hace falta rotación para este tipo de malla.

**Estado**: compila limpio (`gradlew compileDebugKotlin`) y verificado numéricamente
(continuidad de valor y derivada, ver arriba). **Sin confirmar visualmente en dispositivo
real** — no hay uno disponible en este entorno.

### 5.7 Asimetría entre ojo izquierdo y derecho — un solo `.glb` cargado en los dos ojos (2026-08-07)

**Síntoma reportado**: con un diseño elegido desde el catálogo del backend, un ojo sigue bien
la curva del párpado y el otro se ve deformado/con el ala apuntando al lado equivocado (no
hacia la comisura externa).

**Diagnóstico**:
1. `EyeAnchorCalculator`, `EyePlaneCalculator`, `EyeTransformCalculator`, `FaceRenderPipeline`,
   `LashLineCurve` son agnósticos de ojo izquierdo/derecho por diseño — correcto, no es ahí.
2. El catálogo LOCAL (`assets/modelos/`, 5 estilos × 2 archivos) sí carga un `.glb` distinto
   por ojo (`cateyeleft.glb`/`cateyeright.glb`, etc.) — y esos pares SÍ están correctamente
   espejados: se verificó comparando el perfil de profundidad Z por banda de X de los 5 pares
   con un script propio (Node, parseo directo del `.glb`) — los 5 correlacionan mucho mejor en
   orden ESPEJADO que en el mismo orden (ej. `catclassic`: -0.94 sin espejar vs 0.998
   espejado; `cateye`: 0.63 vs 0.88; los 5 pares dan el mismo patrón). No hay bug ahí.
3. `eye_tracking_page.dart` (líneas ~211-215): **"El backend solo guarda un .glb por diseño
   (no hay modelo separado por ojo izq/der como en el set por defecto cateyeleft/cateyeright),
   así que se carga el mismo archivo en ambos lados"** — `_leftModelPath = path; _rightModelPath
   = path`. Confirmado: para un diseño del backend, `LashRenderer.loadEyeModels()` recibe
   literalmente la MISMA ruta para los dos ojos. El asset está diseñado para UN lado (el ala
   apunta hacia un lado fijo del eje X local); sin espejar una de las dos copias, el ojo que
   NO coincide con ese diseño se ve con el ala apuntando hacia adentro en vez de hacia la
   comisura externa.

**Fix aplicado**: `RawMesh.mirroredAcrossX()` (`GlbMeshReader.kt`) espeja la malla CRUDA
(antes de que `LashMeshBender` la use, no después) — `position.x → -x`, `normal.x → -x`
(si no, la iluminación queda especularmente incorrecta), winding de cada triángulo invertido
(swap del 2do/3er índice — espejar en un eje invierte el frente de cada cara), y
`minX`/`maxX` recalculados (`-maxX`/`-minX` originales) para que `LashMeshBender` siga
funcionando sin saber que hubo un mirror. `LashRenderer.loadEyeModels()` solo lo activa
cuando `leftPath == rightPath` (señal explícita de "mismo archivo para los dos ojos" — ver
punto 2, el catálogo local con archivos distintos queda sin tocar, evitando espejar un
par que el artista ya exportó correcto) y lo aplica al ojo DERECHO — elección no verificable
sin dispositivo (ver Estado).

**Estado**: compila limpio (`gradlew compileDebugKotlin`); **sin confirmar en dispositivo
real**. Pendiente: confirmar que espejar el DERECHO (y no el IZQUIERDO) es el lado correcto —
si en dispositivo el resultado queda invertido, cambiar `mirrorRightEye` por su negación en
`LashRenderer.loadEyeModels()` es el único cambio necesario. Probar con al menos 2 diseños de
backend (para no depender de un solo asset) y confirmar que el catálogo local (que no pasa por
este mirror) sigue sin regresión.

### 5.8 "Sale volando" en la comisura exterior — envolvente en Z, falloff más ancho, suavizado vectorial completo (2026-08-08)

**Síntoma reportado en dispositivo real**: el modelo encaja perfectamente en el lagrimal
(esquina interna) pero, al acercarse a la comisura exterior (sobre todo en estilos "Cat Eye"),
se desvía, se despega de la piel y "sale volando" hacia adelante y hacia arriba, fuera de la
órbita del ojo.

**Tres causas distintas, cada una con su fix — sin tocar el shear vertical puro (5.6) ni
`rootLocalY` (5.1), ambos ya confirmados correctos**:

1. **Ceguera de profundidad (sin envolvente en Z)**: `LashMeshBender.bend()` solo desplazaba
   `y` — el ala exterior se quedaba en el mismo plano Z que la raíz en vez de retroceder hacia
   adentro de la órbita, como hace el párpado real al envolver el globo ocular (aprox. una
   esfera). Fix: caída cuadrática en Z, `depthDropPx = pixelLocalX² / (2·R)` con
   `R = eyeWidthPx/2` — el primer término no nulo de la expansión de Taylor del perfil real de
   un círculo (`z = R − √(R²−x²)`), no un valor inventado. Ajustable vía
   `RendererConfiguration.LASH_BEND_DEPTH_DROP_STRENGTH`. **Clamp añadido tras verificar
   numéricamente** (no a simple vista): la aproximación cuadrática se desvía ~50% de la real ya
   en `x=R`, y para `|x|>R` (rutinario en el ala, con `NOSE_AVOID_SHIFT` ~68% del ancho del
   ojo) la real está indefinida mientras la cuadrática sigue creciendo sin límite — el mismo
   patrón de extrapolación-sin-límite que ya causó el bug de 5.5. Se acota `depthDropPx` a
   `radiusPx` (la profundidad física máxima de esa esfera, no un tope arbitrario).
2. **Corte prematuro de la meseta en Y**: `LashLineCurve.falloffDistancePx()` usaba `0.5×` el
   ancho del rango realmente ajustado (`[minLocalX,maxLocalX]`) como distancia de transición.
   Los vértices del ala de un Cat Eye caen mayormente FUERA de ese rango (por diseño del
   estilo) y chocaban con la meseta casi de inmediato, dejando la punta del ala como una línea
   recta que deja de curvarse hacia abajo con el párpado. Fix: multiplicador subido a `1.75×`
   vía `RendererConfiguration.LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER` — la curva (que sigue siendo
   C1-continua, ver 5.6) tiene más recorrido antes de aplanarse.
3. **Desgarro por suavizado incompleto**: el EMA (`LASH_BEND_SMOOTHING`) contra el doblado
   anterior en `LashRenderer.applyTransform()` solo interpolaba el eje Y — X/Z saltaban directo
   al valor nuevo mientras Y se arrastraba detrás del promedio anterior, así que cada vértice se
   movía en diagonal (X/Z ya en destino, Y a mitad de camino) en vez de en línea recta hacia su
   posición nueva. Con Z ahora también deformándose (punto 1), esto se nota más — se veía como
   que la pestaña se "descuelga" de la línea del párpado al mover la cabeza. Fix: el blend con
   `k` ahora se aplica a `x`/`y`/`z` simultáneamente al construir el vértice nuevo.

Ningún número mágico añadido sin justificación: la caída en Z sale de la geometría real de una
esfera (con `R` derivado de `eyeWidthPx`, ya calculado por el pipeline); el multiplicador de
falloff y la fuerza de la envolvente en Z SÍ son constantes de calibración explícitas (mismo
estatus que `LASH_BEND_STRENGTH`), documentadas como tales en `RendererConfiguration.kt`, no
escondidas ni derivadas de otra cosa por conveniencia.

**Estado**: compila limpio (`gradlew compileDebugKotlin`); el clamp de la envolvente en Z se
verificó numéricamente (Node, comparando la aproximación cuadrática contra el perfil exacto de
un círculo en `x = 0..50px` con `R=30px` — diverge ~50% en `x=R` y sin límite más allá, de ahí
el clamp). **Sin confirmar visualmente en dispositivo real** — no hay uno disponible en este
entorno. Pendiente: probar con Cat Eye y un estilo wispy/natural, comparar el ala exterior
antes/después, y calibrar `LASH_BEND_DEPTH_DROP_STRENGTH`/`LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER`
(los valores actuales son puntos de partida, no medidos en pantalla).

### 5.9 Sistema de estilos por diseño + doblado sin alocar por frame (2026-08-08)

**Motivación**: hasta acá `HEIGHT_OFFSET`/`NOSE_AVOID_SHIFT`/la envolvente en Z de 5.8 eran
`const val` fijos en `RendererConfiguration` — correcto mientras solo existía un estilo visual,
pero el catálogo tiene diseños genuinamente distintos (Cat Eye dramático vs. Wispy natural) que
necesitan esos valores DISTINTOS por diseño, no por bug de calibración. Además,
`LashMeshBender.bend()` (y el suavizado EMA en `LashRenderer`) reconstruían una
`List<Geometry.Vertex>` nueva en cada resultado de MediaPipe (~30Hz por ojo) — la causa
original del `OutOfMemoryError` de la sección 3.4 de `ESTADO_ACTUAL.md`.

**1. `LashStyleConfig.kt` (nuevo)** — `data class` con `heightOffset`/`noseAvoidShift`/
`zDepthDropRadiusFraction`/`foxyLiftMultiplier`, más un registro fijo de 3 presets
(`CAT_EYE`/`NATURAL`/`WISPY`) resuelto por `forStyleId(styleId)` con fallback a `DEFAULT`
(mismos valores que las constantes globales de antes) para cualquier id desconocido —
degradación segura, un estilo sin registrar no rompe el render. `EyeAnchorCalculator.compute()`
y `LashMeshBender.bendInPlace()` ahora reciben este config en vez de leer
`RendererConfiguration` directamente para esos 4 parámetros; se hila por
`FaceRenderPipeline.compute(styleConfig=...)`, que `LashRenderer` invoca con
`currentStyleConfig` (un solo estilo activo, aplicado a los dos ojos — la asimetría izq/der
sigue resuelta aparte por `RawMesh.mirroredAcrossX()`, sección 5.7).

**2. `LashMeshBender.bendInPlace()` reemplaza a `bend()`** — escribe en un buffer
PRE-ASIGNADO en vez de devolver una `List` nueva, y funde en el MISMO pase el doblado (Y+Z,
sección 5.8) y el suavizado EMA contra el frame anterior (antes eran dos `.map`/`.mapIndexed`
encadenados en `LashRenderer`). **Límite honesto, verificado con `javap` sobre el `.aar` de
sceneview-android 2.1.1 (no a ojo)**: `Geometry.Vertex`/`Float3` son INMUTABLES (todos los
campos `final`, sin setters) — no existe forma de mutar un vértice ya existente sin bypassear
esa API (manejar un `VertexBuffer` crudo de Filament, fuera de alcance acá). Lo que SÍ se
elimina: la `List`/`ArrayList` nueva por frame, y la doble instanciación de `Vertex` por
vértice que había antes (doblado + suavizado por separado) — ahora es 1 sola por vértice por
frame, el mínimo posible sin cambiar de API.

**3. Double-buffer en `EyeModelSlot`** (`bufferA`/`bufferB`, `useBufferAAsTarget`,
`hasBentBefore`) — se asignan UNA vez en `loadIntoSlot` (tamaño exacto de `rawMesh.vertices`)
y se alternan cada frame: uno es el destino de `bendInPlace`, el otro es el "frame anterior"
que necesita el suavizado EMA. Necesarios los DOS (no uno solo): con un único buffer, escribir
el resultado nuevo sobre el índice `i` destruiría el valor anterior de `i` antes de que el
suavizado pudiera leerlo.

**4. Integración Flutter↔Kotlin**: nuevo método `setLashStyle` en el `MethodChannel`
`eye_tracking/methods` (mismo canal que `loadEyeModels`, ver `EyeTrackingPlugin.kt` →
`CameraXManager.setLashStyle` → `LashRenderer.setStyle`), invocado desde
`NativeEyeTrackingService.setLashStyle(styleId)` justo después de `loadEyeModels` en
`eye_tracking_page.dart` (`_switchDesignModel`/`_switchLocalPreset`). `styleId` se deriva del
nombre visible del diseño (`_lashStyleIdFor`, ej. "Cat Eye" -> "cateye") — funciona de punta a
punta para los 3 presets locales registrados (Cat Eye/Natural/Wispy); para diseños del backend
o los otros 2 presets locales (Cat Classic, Foxy Eye) cae a `DEFAULT` hasta que se registren o
el backend exponga estos 4 parámetros por diseño (ver nota en `LashStyleConfig.forStyleId`).

Ningún número mágico nuevo sin justificación: los 3 presets son puntos de PARTIDA (mismo
estatus que cualquier constante nueva de este motor sin calibrar — ver historial de
`HEIGHT_OFFSET` en la sección 3), no medidos en dispositivo real.

**Estado**: compila limpio (`gradlew compileDebugKotlin` + `flutter analyze` sobre los 2
archivos Dart tocados, ambos sin errores). **Sin confirmar visualmente en dispositivo real** —
no hay uno disponible en este entorno. Pendiente: confirmar en dispositivo que (a) el cambio de
estilo se nota visualmente al tocar un diseño distinto del catálogo, (b) no hay regresión de
jank/lag respecto al comportamiento anterior (el objetivo del punto 2/3 era reducirlo, no
cambiar el comportamiento visual), y (c) calibrar los 3 presets contra capturas reales.

### 5.10 Regresión confirmada y revertida en dispositivo real — envolvente en Z + falloff ancho (2026-08-08)

Con dispositivo real disponible en esta sesión (Infinix X669, conectado por `adb`), se pudo
verificar visualmente por primera vez la envolvente en Z de 5.8 y el multiplicador de falloff
subido a 1.75 de la misma sección — ambos quedaron marcados "sin confirmar" en su momento.

**Síntoma confirmado con `adb exec-out screencap` + logcat en vivo**: con esos dos cambios
activos, la pestaña NO seguía el párpado — la punta salía disparada en diagonal hacia la ceja/
frente, en los dos ojos por igual, con un aspecto de pico/espiga fino en vez de un abanico
apoyado sobre el párpado. `eyeWidthPx` (~40-48px) y `deviationSample` (~-4 a 0 px) en logcat no
mostraban valores absurdos en el CENTRO del ajuste — la deformación se concentraba en los
extremos del ala, donde entran en juego `falloffDistancePx` (LashLineCurve) y la envolvente en
Z (LashMeshBender), justo las dos piezas nuevas sin confirmar.

**Diagnóstico**: no fue posible aislar con certeza cuál de las dos era la causa principal en el
tiempo disponible (compilar+instalar+probar cada iteración toma varios minutos), así que se
revirtieron las DOS a la vez en vez de seguir ajustando a ciegas:
- `LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER`: `1.75f` → `0.5f` (el valor confirmado funcionando en
  5.5/5.6/5.7). Sospecha: la meseta de `deviationAt` (`edgeSlope × falloffDist × 0.5`) crece
  proporcional a `falloffDist` — multiplicar el ancho de la zona de transición por 3.5× también
  multiplica esa meseta ~3.5×, suficiente para disparar la punta del ala muy por encima de
  donde debería quedar con un `edgeSlope` no trivial (normal en un párpado real).
- `LASH_BEND_DEPTH_DROP_STRENGTH`: `1.0f` → `0.0f` (envolvente en Z apagada por completo).
  Sospecha: `radiusPx` acota el valor en PÍXELES, pero convertido a unidades locales del mesh
  (`× meshUnitsPerPixel`) puede seguir siendo grande respecto al propio espesor en Z de un mesh
  de pestaña (una tarjeta casi plana) — nunca se verificó esa proporción contra los `.glb`
  reales antes de activarlo por defecto.
- `LashStyleConfig.CAT_EYE`/`NATURAL`/`WISPY`: neutralizados a `LashStyleConfig()` (idénticos a
  `DEFAULT`) — sus valores originales (citados en la tarea de diseño, nunca medidos) alejaban
  `heightOffset`/`noseAvoidShift` de los ya confirmados en `RendererConfiguration`, sumando más
  variables sin controlar al mismo tiempo que se probaba la envolvente en Z.

**Confirmado en dispositivo real** (mismo Infinix X669, misma sesión): con los tres reversos
aplicados, recompilado (`gradlew compileDebugKotlin` limpio), reinstalado
(`flutter build apk --debug` + `adb install -r`) y verificado con captura en vivo — la pestaña
vuelve a apoyarse sobre el párpado siguiendo su curva, sin la espiga hacia la ceja, en ambos
ojos. Quedan pendientes de la lista original (integración raíz-párpado sin espacio visible,
simetría fina entre ojos) — el objetivo de este punto era específicamente detener la regresión
grave introducida el mismo día, no terminar de pulir la calidad visual.

**Lección para las próximas iteraciones de este motor**: 5.8/5.9 se escribieron y documentaron
con el disclaimer correcto ("sin confirmar en dispositivo real"), pero se apilaron VARIOS
cambios nuevos sin verificar (envolvente en Z + falloff más ancho + 4 parámetros por estilo) en
la misma pasada, sin punto de verificación intermedio — cuando algo salió mal, aislar la causa
costó más que si cada cambio se hubiera probado por separado. Con dispositivo disponible, el
flujo de trabajo debería ser: un cambio → compilar → instalar → capturar → confirmar, ANTES de
apilar el siguiente.

### 5.11 Calibración fina post-5.10 — raíz al borde del párpado, ala sin levantarse (2026-08-08)

Con la regresión de 5.10 revertida (envolvente en Z de 5.8 confirmada funcionando, sin la
espiga hacia la ceja), quedaban dos ajustes finos pendientes: (1) el ala exterior de Cat Eye
todavía tenía una leve tendencia a levantarse hacia la ceja en las puntas, y (2) alinear la
raíz exactamente al borde del párpado.

**Cambios aplicados** (`RendererConfiguration.kt`):
- `HEIGHT_OFFSET`: `-0.15f` → `-0.05f`.
- `LASH_BEND_STRENGTH`: `1.0f` → `0.5f` (amortigua la parábola vertical, sobre todo en los
  extremos del ala donde `deviationAt` alcanza sus valores más altos — sin aplanarla del todo).
- `LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER`: ya estaba en `0.5f` desde el revert de 5.10, sin
  cambios.
- `LashMeshBender.kt`: revisado — no existe ningún ajuste manual de pendiente (`slope -=` o
  similar) que fuerce la punta hacia arriba; `slope` sale directo de `curve.slopeAt(pixelLocalX)
  * strength`, sin términos artificiales añadidos.

**Nota de proceso (por transparencia)**: `HEIGHT_OFFSET` sigue la convención
`anchorY = meanY − height × heightOffset` con Y de imagen creciendo hacia ABAJO (ver
`EyeAnchorCalculator`) — un `heightOffset` MÁS negativo baja MÁS el ancla. `-0.15f → -0.05f` es
matemáticamente una REDUCCIÓN de la corrección hacia abajo, no un aumento — lo opuesto de "bajar
la raíz" tomado literalmente. Se aplicó igual como punto de partida a probar (así lo pidió la
calibración) y se verificó el resultado en dispositivo real en vez de asumir la dirección por el
nombre del parámetro.

**Confirmado en dispositivo real** (Infinix X669, misma sesión): recompilado
(`gradlew compileDebugKotlin` limpio), reinstalado (`flutter build apk --debug` + `adb install
-r`) y verificado con `adb exec-out screencap` + logcat en vivo, en dos poses distintas
(rostro de frente y con la cabeza inclinada hacia abajo) — en ambas, la pestaña sigue la curva
del párpado en los dos ojos SIN el levantamiento hacia la ceja de 5.10. `eyeWidthPx`/
`deviationSample` en logcat sin valores anómalos. Queda como próximo ajuste fino (no
bloqueante): una asimetría leve residual entre ojos en poses con la cabeza inclinada, y afinar
si `HEIGHT_OFFSET=-0.05f` es el punto óptimo o si conviene un valor intermedio entre este y
`-0.15f` — pendiente de más iteraciones de calibración con captura en vivo.

### 5.12 Raíz exactamente en el borde palpebral — medido con captura recortada, no a ojo (2026-08-08)

Con 5.11 aplicado (`HEIGHT_OFFSET = -0.05f`), el usuario reportó que la raíz seguía sin quedar
exactamente en el borde del párpado. Para diagnosticar esto con precisión (no una impresión
general de "se ve bien/mal" sobre la captura completa), se recortó y amplió 2× la zona de los
ojos con `ffmpeg` (`crop=560:280:80:380,scale=1120:560`) sobre el mismo `adb screencap` — así
se pudo ver el espacio entre la línea de raíz del mesh y la línea real del párpado con
claridad, en vez de estimarlo sobre una foto completa a resolución de pantalla.

**Confirmado con la captura recortada**: con `-0.05f` la raíz quedaba claramente por ENCIMA del
borde visible del párpado, con piel de por medio en los dos ojos — visible en la comparación
recorte-a-recorte, no solo "parecía flotar un poco".

**Causa**: la nota de la sección 5.11 razonaba "menos negativo = menos agresivo" para justificar
subir de -0.15 a -0.05 — esa lectura del signo era INCORRECTA (ya se había señalado como
sospecha en 5.11, sin confirmar en ese momento). Por la fórmula real
(`anchorY = meanY − height × heightOffset`, Y de imagen crece hacia ABAJO, ver
`EyeAnchorCalculator`), MENOS negativo es MENOS corrección hacia abajo — `-0.05f` bajaba el
ancla mucho menos que `-0.15f`, dejando la raíz más arriba, no más pegada.

**Fix**: `HEIGHT_OFFSET` subido (más negativo) a `-0.22f`. Se comparó el mismo recorte
2×-amplificado antes/después: con `-0.22f` la línea de raíz traza directamente sobre la línea
real del párpado en los dos ojos, sin el espacio de piel visible que había con `-0.05f`, y sin
invadir hacia el globo ocular (no se pasa del borde hacia adentro).

**Confirmado en dispositivo real** (Infinix X669, misma sesión): recompilado, reinstalado, y
verificado con captura + recorte ampliado — no solo con la foto completa a resolución de
pantalla, que no alcanza para juzgar un ajuste de esta escala (unos pocos píxeles de imagen).
`eyeWidthPx`/`deviationSample` en logcat sin valores anómalos durante la prueba.

**Lección de proceso**: para calibrar algo del orden de "¿la raíz toca exactamente el borde o
queda a unos pocos píxeles?", una captura de pantalla completa a resolución normal no es
suficiente para juzgarlo con confianza — hace falta recortar y ampliar la zona del ojo (ver
comando `ffmpeg` arriba) antes de comparar. Aplicar esto en cualquier calibración futura de
posición fina (no solo `HEIGHT_OFFSET`).

### 5.13 Corrección longitudinal hacia el canto lateral — vector real, no un shift de mundo (2026-08-08)

**Síntoma reportado**: el conjunto de pestañas queda demasiado desplazado hacia el canto
medial/lagrimal; hace falta correrlo un poco hacia el canto lateral/temporal, sin tocar
escala, rotación, curvatura, deformación, el `.glb`, ni el tracking.

**Análisis previo a modificar (por pedido explícito)**:
- La posición final del modelo sale de `EyeAnchor.point` (`EyeAnchorCalculator.compute()`),
  que viaja sin cambios hasta `EyeTransformCalculator.compute()`, donde se normaliza a NDC y se
  des-proyecta a mundo real con `camera.unproject()` (ver esa función, línea ~86) — CUALQUIER
  corrección aplicada sobre `anchor.point`, en píxeles de imagen, hereda automáticamente esa
  misma des-proyección real, así que es correcta a cualquier distancia de cámara sin tocar
  `EyeTransformCalculator` en absoluto.
- `cornerA`/`cornerB` (`eye.ring.minByOrNull{x}`/`maxByOrNull{x}`, ya existentes en
  `EyeAnchorCalculator`) SON, anatómicamente, el canto medial y el canto lateral — los dos
  extremos en X del anillo de 16 puntos del ojo son, por definición, las dos únicas esquinas
  reales de un ojo. No hizo falta agregar índices de landmark nuevos.
  `EyeAnchorCalculator` ya determina cuál de los dos es el lateral comparando la distancia de
  cada uno al centro horizontal de la imagen (asumiendo rostro centrado) — se reutilizó esa
  misma lógica.
- **Causa exacta del sesgo medial**: `NOSE_AVOID_SHIFT` (mecanismo YA existente, sección 5,
  activo con `0.68`) desplaza el ancla, pero SOLO en el eje X de la imagen — un signo × una
  magnitud escalar (`shiftedX = meanX + shiftSign * width * noseAvoidShift`), no a lo largo de
  la dirección real medial→lateral del ojo. Con la cabeza en roll (inclinada de costado), esa
  dirección real tiene una componente en Y que un shift puramente horizontal no cubre — el
  ancla queda corta respecto al eje verdadero del ojo, lo que se percibe como "todavía muy cerca
  del lagrimal". No era la curva (`LashLineCurve`) ni la escala (`naturalSpan`/`scaleFactor`)
  las causantes — ninguna de las dos se tocó.

**Fix aplicado** (aditivo — `NOSE_AVOID_SHIFT` queda intacto, esto se SUMA encima):
```
medialCanthus  = corner con MENOR distancia al centro horizontal de la imagen
lateralCanthus = corner con MAYOR distancia al centro horizontal de la imagen
lateralDirection = normalize(lateralCanthus - medialCanthus)      // vector real, no solo X
lateralOffsetPx  = distance(medialCanthus, lateralCanthus) * LATERAL_LASH_OFFSET
correctedPoint   = shiftedPoint + lateralDirection * lateralOffsetPx
```
Implementado en `EyeAnchorCalculator.compute()`, inmediatamente después de calcular
`shiftedX`/`anchorY` (el mecanismo existente, sin modificar). Nuevo parámetro
`RendererConfiguration.LATERAL_LASH_OFFSET` (valor inicial `0.08f`, calibrado a `0.20f` —
ver el final de esta sección), expuesto también como
`LashStyleConfig.lateralLashOffset` (mismo patrón que `heightOffset`/`noseAvoidShift` — un
estilo con ala más extendida podría necesitar más corrección que uno redondo).

**Por qué es correcto a cualquier distancia de cámara**: el offset se calcula como fracción de
`distance(medialCanthus, lateralCanthus)` — la distancia REAL entre los dos cantos, en píxeles
de la imagen de análisis de ESE frame — no un valor fijo en píxeles ni un desplazamiento en
unidades de mundo. Si el rostro se acerca, ambos cantos se separan más en píxeles y el offset
crece proporcionalmente EN LA MISMA imagen; si se aleja, se achica igual de proporcional. Como
todo el punto resultante pasa por la misma des-proyección real de `camera.unproject()` que ya
usa el resto del ancla (WIDTH_MULTIPLIER, HEIGHT_OFFSET, NOSE_AVOID_SHIFT), el resultado final
en mundo 3D escala correctamente sin ningún término de compensación por perspectiva aparte.

**Por qué no crea una esquina triangular**: `lashCurveAnchorOffsetPx` (que `LashMeshBender`
usa para mapear su `pixelLocalX` al sistema de coordenadas de `LashLineCurve`) se calcula
DESPUÉS de este fix, a partir de `anchor.point` ya corregido — se recalcula automáticamente en
línea, sin tocar `LashLineCurve.fit()`/`deviationAt()`/`slopeAt()` ni el shear de
`LashMeshBender`. El mismo mecanismo que ya evitaba el pico triangular con `NOSE_AVOID_SHIFT`
(sección 5.6) sigue aplicando sin cambios.

**Qué tocar para ajustar**: subir `RendererConfiguration.LATERAL_LASH_OFFSET` si el conjunto se
ve corrido hacia el lagrimal; bajarlo si se pasa hacia la sien. Es una fracción de la distancia
real entre cantos, así que no hace falta re-expresarlo en píxeles al cambiar de dispositivo/
distancia.

**Ronda de calibración iterativa en dispositivo real** (Infinix X669, misma sesión, cada paso
con captura recortada/ampliada — ver metodología 5.12 — antes de decidir el siguiente):
- `0.08` (valor inicial razonado): compiló y se veía correcto (sin pico, sin deformación), pero
  el usuario lo reportó insuficiente — "sigue alejado del canto externo".
- `0.16`: seguía insuficiente.
- `0.28`: SOBRE-corrigió — la punta del ala se pasaba del canto lateral real hacia la sien/
  nacimiento del pelo, visible con claridad en la captura recortada de un ojo (el otro quedó
  mejor contenido, probablemente por pose — cabeza no perfectamente de frente — no
  necesariamente asimetría de código).
- **`0.20` — CONFIRMADO**: captura recortada/ampliada de los DOS ojos muestra el ala CONTENIDA
  dentro del contorno real del ojo en ambos — ni se pasa hacia la sien ni deja hueco en el
  lagrimal —, simétrico entre los dos ojos, sin pico ni deformación. `eyeWidthPx`/
  `deviationSample` en logcat sin valores anómalos durante toda la ronda. Este es el valor
  final de esta calibración.

### 5.14 `0.20` resultó insuficiente en una foto real distinta — subido a `0.30` (2026-08-10)

**Síntoma reportado por el usuario**, con dos capturas reales nuevas (selfie de frente, diseño
Cat Eye, mismo dispositivo): el lagrimal (canto medial) quedaba bien colocado en los dos ojos,
pero el canto lateral de UN ojo se veía con un hueco claro entre la punta del ala y la esquina
real — marcado por el propio usuario con un punto rojo sobre la captura para señalar la
distancia faltante.

**Verificación por medición de píxeles (no solo impresión visual)**: se tomó una captura fresca
del dispositivo conectado (`adb exec-out screencap`, mismo Infinix X669) reproduciendo el
`HEAD_TILT`/pose de las capturas del usuario, y se recortó/amplió cada ojo por separado con una
grilla de referencia en píxeles (extensión del método de 5.12). Con `LATERAL_LASH_OFFSET=0.20`
(el valor que este documento tenía como "confirmado"):
- Ojo A (canto lateral hacia la izquierda de la imagen): lash desde x≈172 hasta la esquina real
  en x≈165 — margen de ~7px, bien contenido.
- Ojo B (canto lateral hacia la derecha de la imagen): lash terminaba en x≈560 pero la esquina
  real del ojo estaba en x≈655 — **hueco real de ~95px**, no un desajuste menor.

La asimetría (7px vs 95px) con la MISMA constante y la MISMA fórmula en los dos ojos confirma lo
que 5.13 ya dejaba anotado como sospecha sin resolver ("probablemente por pose, no
necesariamente asimetría de código") — probablemente ligado a que ese ojo específico tenía pelo
invadiendo parcialmente el canto lateral en esa pose (visible en la captura), lo que hace que
MediaPipe ubique esa esquina más cerca de lo real. No se encontró ni se buscó una causa de
código distinta a la ya usada por `LATERAL_LASH_OFFSET` — el ajuste fue subir la constante para
dar margen suficiente incluso en poses con esa clase de ruido.

**Fix**: `RendererConfiguration.LATERAL_LASH_OFFSET` subido de `0.20f` a `0.30f`.

**Confirmado en dispositivo real, en esta misma sesión** (a diferencia de varias entradas
anteriores de este documento, esta sí se verificó de punta a punta dentro de la propia sesión:
build → install → captura → medición — no es una nota "pendiente de confirmar"):
recompilado (`flutter build apk --debug`), reinstalado (`adb install -r`) en el mismo Infinix
X669, y se pidió al usuario sostener el rostro frente a la cámara de nuevo. Captura fresca,
recortada/ampliada con grilla igual que arriba: el ojo que antes tenía el hueco de ~95px ahora
termina a ~10-15px de la esquina real (pose distinta a la de la medición anterior — cabeza
inclinada hacia abajo — así que no es una comparación exacta píxel a píxel, pero la mejora es
clara y consistente con lo esperado de subir la constante en 0.10). El otro ojo sigue sin
pasarse hacia la sien — sin regresión visible.

**Nota de proceso**: esta iteración usó, por primera vez documentada en este archivo dentro de
una única sesión, control directo del dispositivo conectado (`adb`/`flutter build`/`adb
install`) para cerrar el ciclo cambio→verificación sin depender de que el usuario reportara el
resultado por separado. Al operar sobre el teléfono real del usuario, la pantalla de inicio y la
pantalla de bloqueo expusieron notificaciones/contactos personales en las capturas intermedias
— eso se evitó procesar u opinar sobre ese contenido, y se limitó la interacción a navegar hasta
la pantalla de la cámara.

**Pendiente**: `0.30` es un paso intermedio razonado a partir de la magnitud del hueco medido
(no una ronda completa de calibración como 5.13, que probó 4 valores) — si en uso normal
(fotos distintas, ángulos distintos) el ala empieza a pasarse hacia la sien en algún ojo, bajar
este valor antes de tocar cualquier otra constante.

## 6. Curva del párpado y doblado de mesh (ACTIVO desde 2026-08-02, ver 5.1-5.14)

`LashLineCurve.fit()` ajusta una parábola (`f(x) = ax² + bx + c`, mínimos
cuadrados) a los puntos del párpado superior, en un sistema de coordenadas
local alineado con la tangente del párpado (ajustada alrededor de
`EyeAnchor.lidCenter`, ver 5.4) — captura SOLO la curvatura adicional
respecto a la inclinación promedio (la rotación recta ya la aplica el paso 4).

`LashMeshBender.bend()` usa esa curva para desplazar cada vértice del mesh en
el eje Y local (glTF es Y-up) y así seguir la forma real del párpado en vez de
la forma genérica de fábrica del `.glb`.

**Estado actual: ACTIVO y confirmado en dispositivo real** (ver 5.1-5.5 para
el historial completo de bugs encontrados y arreglados). Resumen de la
arquitectura vigente en `LashRenderer.applyTransform()`:
- El doblado (`LashMeshBender.bend()`, la reconstrucción de la lista de
  `Geometry.Vertex`) corre en el hilo de MediaPipe (no el principal).
- Throttle: máximo `RendererConfiguration.LASH_BEND_MIN_INTERVAL_NANOS`
  (220ms ≈ 4.5Hz por ojo) — evita saturar de trabajo el hilo de MediaPipe/GPU.
- Guard `EyeModelSlot.bendPending`: evita encolar más subidas a GPU de las
  que el hilo principal puede consumir.
- Suavizado temporal (`RendererConfiguration.LASH_BEND_SMOOTHING`, EMA sobre
  la posición Y ya deformada) contra el doblado anterior — sin esto, el
  ruido de landmarks frame a frame se veía como temblor en vez de una curva
  estable.
- Solo la subida final a GPU (`geometry.setVertices()`) se despacha al hilo
  principal (`mainHandler.post`), no la reconstrucción de vértices.
- `LASH_BEND_STRENGTH = 0.5` (amortiguada — bajada desde 1.0 en 5.11 porque
  el ala exterior tendía a levantarse hacia la ceja en las puntas). Valores
  aún anteriores (0.25) fueron parches para tapar bugs de coordenadas ya
  corregidos (5.1-5.5), no una calibración de estilo real — distinto motivo
  del ajuste de 5.11.

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
| `HEIGHT_OFFSET` | -0.22 | Cuánto baja la RAÍZ del modelo (no el centro, ver sección 5.1) respecto al centroide del párpado — calibrado con captura recortada/ampliada en 5.12 |
| `WIDTH_MULTIPLIER` | 1.8 | Cuánto más ancho que el ojo real es el modelo (escala X/Z) |
| `HEIGHT_VOLUME_MULTIPLIER` | 1.55 | Escala EXTRA solo en Y (grosor/volumen vertical), sección 5.3 |
| `LASH_BEND_STRENGTH` | 0.5 | Amortiguación de la curva del párpado (secciones 6, 5.11) |
| `LATERAL_LASH_OFFSET` | 0.30 | Corrección aditiva hacia el canto lateral, como fracción de la distancia real entre cantos — calibrado iterativamente en dispositivo real (sección 5.13), subido de 0.20 a 0.30 tras confirmar un hueco real de ~95px en un ojo con una foto distinta (sección 5.14) |
| `LEFT_EYE_X_NUDGE` / `RIGHT_EYE_X_NUDGE` | 0.0 | Corrección fina de X por ojo (fracción de pantalla) |
| `HEAD_TILT_MULTIPLIER` | 1.0 | Multiplicador extra sobre la corrección de escorzo |
| `EYE_CLOSED_OPENNESS_THRESHOLD` / `EYE_OPEN_OPENNESS_THRESHOLD` | 0.12 / 0.22 | Umbral de apertura para ocultar/atenuar al parpadear |
| `MIN_DEPTH` / `MAX_DEPTH` | -2.2 / -0.35 | Rango de profundidad válido |
| `FACE_DISTANCE_MULTIPLIER` | 1.0 | Multiplicador sobre la posición 3D de la cabeza |
| `LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER` | 0.5 | Ancho de la zona de transición C1 más allá del rango fitteado (sección 5.8) — subido a 1.75 causó una regresión confirmada en dispositivo real, revertido en 5.10 |
| `LASH_BEND_DEPTH_DROP_STRENGTH` | 0.0 (apagado) | Fuerza de la envolvente esférica en Z (sección 5.8) — activarlo (1.0) causó una regresión confirmada en dispositivo real, revertido en 5.10; el knob por-estilo vive en `LashStyleConfig.foxyLiftMultiplier`, hoy neutralizado también |

## 9. Puntos abiertos / riesgos conocidos

- **Convención row/column-major de `facialTransformationMatrixes()`**: no
  verificable sin dispositivo real (ver comentario extenso en
  `EyePoseEstimator.kt`). Si el yaw/pitch/roll logueado con `DEBUG_LOG_POSE =
  true` no coincide con el movimiento real de la cabeza, la lectura es
  column-major y hay que transponer `m(r,c)` a `matrix[c*4+r]`.
- **Sentido del eje X local del mesh** en `LashMeshBender`: no verificable sin
  dispositivo si está invertido respecto a la tangente del párpado (doblaría
  espejado en vez de seguir la curva real). Riesgo distinto del de la
  sección 5.7 (ese era "mismo archivo en los dos ojos"; este es "la
  convención de signo de X asumida por el pipeline entero podría estar al
  revés, en los dos ojos por igual").
- **`mirrorRightEye` (sección 5.7)**: espeja el ojo DERECHO cuando
  `leftPath == rightPath`, elección no verificable sin dispositivo — si el
  resultado sale invertido, el fix es cambiar qué ojo se espeja en
  `LashRenderer.loadEyeModels()`, no la lógica de `mirroredAcrossX()`.
- ~~`rootLocalY = minY` sin confirmar visualmente~~ — **confirmado en
  dispositivo real 2026-07-24** (sección 5.1): la pestaña nace en la línea
  de pestañas real, no en la ceja, tanto de frente como con roll extremo.
  Riesgo residual menor, no observado en las pruebas: si algún OTRO modelo
  (de los 10 en `assets/modelos/`, solo se probó visualmente uno) tuviera
  geometría adicional por debajo de la raíz real (ej. un plano de colisión
  invisible), su `minY` daría un valor demasiado bajo.
