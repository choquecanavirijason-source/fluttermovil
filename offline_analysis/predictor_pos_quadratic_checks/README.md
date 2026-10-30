# A/B: término cuadrático de posición

Las regresiones usan `event_fixtures.json`: seis entradas numéricas mínimas revisadas. No requieren capturas, CSV ni rutas personales. El baseline elimina únicamente la guarda diagnóstica de la fórmula comprometida, por lo que las pruebas siguen funcionando después del commit.

Rama confirmada: `experiment/tracking-v2`. Esta implementación añade `predictor_pos_quadratic=on` (default). No se instalaron aplicaciones, ejecutó Flutter, cambiaron ramas ni hicieron commits/push. Las capturas y resultados anteriores no se modificaron.

## Cambio funcional

Archivos de esta tarea:

- `android/app/src/main/kotlin/com/example/test_face/PerfFlags.kt`: campo Config, parser ON/OFF, descripción, log requested/effective y fijación por sesión.
- `android/app/src/main/kotlin/com/example/test_face/CameraXManager.kt`: start llama a `PerfFlags.load(activity, cameraSessionStart = true)`; la recarga en caliente conserva la llamada normal.
- `android/app/src/main/kotlin/com/example/test_face/render/PoseInterpolator.kt`: una sola expresión condicional al formar predictedPos.

Los cambios previos de lash_deformation_freeze en estos archivos y LashRenderer permanecen; no se reimplementaron ni alteraron en esta tarea. No se modificaron OneEuro, PoseFollower, sample_blend, timestamps, horizonte, cap, cola soft, rotación, escala, bender, BufferLifetime, cámara o cálculos MediaPipe.

Fórmula original y ON:

```text
v0 = (p1 - p0) / dt0
v1 = (p2 - p1) / dt1
a  = (v1 - v0) / ((dt0 + dt1)/2)
T  = t * dt1
V  = v1*T
A  = 0.5*a*T²
L  = A limitado en magnitud a 0.5*|V|, con la misma guarda existente
P_ON = p2 + V + L
```

Modo OFF para `t > 0`:

```text
P_OFF = p2 + V
```

El cálculo de L y sus límites siguen presentes; solo se omite su suma. No se resta L de una posición ya redondeada: se calcula directamente p2+V. ON conserva literalmente la expresión original y el orden de las operaciones Float. Para t<=0 se mantiene la expresión original incluso en OFF. La función lerpTransform y las rutas de una/dos muestras no se modifican. Actualmente predict utiliza el avance futuro acotado; no se añade una nueva ruta de interpolación entre muestras.

## Uso y seguridad de sesión

```properties
predictor_pos_quadratic=on
buffer_lifetime_trace=off
lash_deformation_freeze=off
```

Para B, usar `predictor_pos_quadratic=off`. Dejar todos los demás parámetros iguales y reiniciar la sesión de cámara con stop/start. La clave ausente, vacía o inválida vuelve a ON **al iniciar la próxima sesión**. El parser existente acepta mayúsculas y espacios.

PerfFlags.read devuelve el valor solicitado. PerfFlags.config contiene el valor efectivo: load durante start toma el solicitado; load durante recarga conserva el valor efectivo anterior solo para esta bandera. Otros flags mantienen su política previa de recarga. Reenlaces automáticos, cambio de modelo o recuperación de tracking no aplican el nuevo modo.

Log de ejemplo (tag CameraXManager):

```text
PREDICTOR_POS_QUADRATIC requested=off effective=on fixed_until_next_camera_start=true
```

No se permite cambiar en caliente porque saltar de p2+V+L a p2+V dentro de una misma muestra cambiaría el objetivo sin el reanclaje que sample_blend realiza al incorporar otra muestra. Fijarlo por sesión evita introducir ese salto como interferencia en la A/B. No hay reasignación de buffers, cambios de propiedad de memoria ni nuevos callbacks Filament.

El flag es global a PoseInterpolator. LinerModelSlot usa la misma clase: si hay delineador visible, también cambia su extrapolación posicional; su geometría/deformación y renderer no se modifican. Para interpretar las pestañas, mantener el mismo estado del delineador entre bloques y distinguir ambos elementos visualmente.

## Pruebas ejecutadas

`powershell -NoProfile -ExecutionPolicy Bypass -File offline_analysis/predictor_pos_quadratic_checks/run_checks.ps1`

- Compila el PerfFlags real con dependencias Android simuladas, no un parser reimplementado.
- Archivo/clave ausentes; ON, OFF, espacios/mayúsculas, vacío e inválido.
- Cambios solicitados ON→OFF y OFF→ON durante recarga se difieren; siguiente start los aplica. Eliminar el archivo durante OFF conserva OFF hasta siguiente start, que vuelve a ON.
- Log requested/effective y descripción del modo.
- Extrae quadraticPredict y helpers reales del archivo actual y del HEAD anterior; usa la dependencia real kotlin-math-jvm 1.5.3 y aritmética Float.
- Seis casos numéricos de evaluaciones 225/226 y 233/234 del ojo 0, y 233/234 del ojo 1. Las muestras, timestamps funcionales y avances efectivos proceden de la reconstrucción existente. ON coincide con los pronósticos reconstruidos dentro de 1e-6 unidades de mundo.
- ON coincide bit a bit con el baseline en los seis casos y en 500 casos aleatorios con semilla fija. OFF coincide bit a bit con p2+V para t>0. t<=0 conserva baseline. Rotación, escala y metadatos coinciden con baseline. Se verifica también lerpTransform.
- Comprobación estática: al retirar únicamente la expresión condicional añadida, PoseInterpolator completo coincide con HEAD. Incluye predict, horizontes, límites, blend y todos los demás métodos.
- `git diff --check`: correcto.
- Compilación Kotlin real: `:app:compileReleaseKotlin --offline -Ptarget-platform=android-arm64 -x compileFlutterBuildRelease --console=plain`. BUILD SUCCESSFUL. Caché Gradle existente; tarea de compilación Flutter excluida; ninguna instalación. Log local: kotlin_build.log.

Las escalas y metadatos de los casos de evento se proporcionan como valores sintéticos iguales en ambos modos, porque la captura original no registra escala. Se prueban las mismas fórmulas, no se pretende reconstruir una escala real ausente. Los tests de funciones extraídas son regresiones numéricas; la compilación Android verifica integración del archivo completo.

## Comparación numérica de eventos

Posiciones en unidades de mundo. Se conserva el T registrado/inferido de cada evaluación; no es replay cerrado del predictor+blend+follower experimental.

| Ojo / evaluación | Eje | ON | OFF |
|---|---|---:|---:|
| 0 / 225, antes de frame 74 | Y | +0.011618290 | +0.005351017 |
| 0 / 226, frame 74 | Y | -0.005657591 | -0.003069928 |
| 0 / 233, antes de frame 77 | X | -0.016422529 | -0.018346690 |
| 0 / 234, frame 77 | X | -0.022931106 | -0.020966135 |
| 1 / 233 | X | +0.046798546 | +0.043633364 |
| 1 / 234 | X | +0.035567950 | +0.037634890 |

La revisión Y 225→226 del ojo 0 pasa de aproximadamente −0.017275881 a −0.008420945. La revisión X 233→234 pasa de −0.006508577 a −0.002619445. Esto demuestra la contribución algebraica del término retirado, no garantiza esos cambios en la salida final de una ejecución OFF: cambiarán los objetivos y el estado posterior de blend/follower, aunque sus algoritmos se conserven.

## Riesgos y límites

- La proyección lineal puede atrasarse más al acelerar y sigue sobreproyectando velocidad antigua al desacelerar. OFF no equivale a no predecir.
- Rotación/escala conservan el mismo horizonte y fórmulas. Su trayectoria no cambia directamente por el flag; la posición sí puede describir otro modelo cinemático.
- Los datos existentes no demuestran que OFF elimine vibración visible. Sigue pendiente A–B–A en dispositivo, con condiciones comparables y estabilización tras cada inicio.
- La clase PoseTraceTelemetry.shadow mantiene su reconstrucción cuadrática: **forecast_same_time no compara dos modelos equivalentes en OFF**. No interpretar esa métrica como error físico ni como comparación válida ON/OFF. blend_applied y follower_residual observan las salidas funcionales, pero tampoco son error contra el preview. No se amplió telemetría en esta tarea.
- Los scripts offline previos que suponen predictor cuadrático tampoco reconstruyen directamente una futura captura OFF; conservar el modo efectivo junto a sus resultados.
- No se alteró la política de buffers ni la telemetría BufferLifetime. Mantener buffer_lifetime_trace=off para esta prueba.
