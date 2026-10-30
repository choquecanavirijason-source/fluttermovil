# Controles diagnósticos y revisión de tracking AR

Trabajo experimental para revisión en `experiment/tracking-v2`. No implica una corrección definitiva de toda vibración.

## Controles y observación en dispositivo

- `predictor_pos_quadratic=on` por defecto conserva la fórmula original. OFF omite solo el término de aceleración posicional futura. El modo efectivo se fija al iniciar cámara; recargas registran solicitado/efectivo y difieren el cambio al siguiente stop/start.
- `lash_deformation_freeze=off` por defecto conserva deformación. ON mantiene pose y geometría base, omitiendo doblado y subidas dinámicas. También se fija por sesión y restaura la geometría base al iniciar ON si el modelo sobrevivió a un stop/start.
- `buffer_lifetime_trace=off` por defecto; instrumentación observacional incorporada en el checkpoint anterior. No decide propiedad ni sincroniza buffers.

Configuración experimental reportada como mejor en Samsung Galaxy Note 10+:

```properties
predictor_pos_quadratic=off
sample_blend=on
preview_latency=80
lash_deformation_freeze=off
buffer_lifetime_trace=off
pose_trajectory_trace=off
```

No se cambian defaults de producción con este documento. ON/OFF/ON/OFF de predicción mostró mejora ligera repetible con OFF y buena respuesta al detenerse, pero persiste vibración. Congelar deformación cambia la curvatura sin eliminar el temblor. Desactivar sample_blend empeoró visualmente el resultado.

## Hallazgos y límites

- BufferLifetime: 3.390 eventos, 678 callbacks y dos escrituras de tangentes anteriores al callback Java observado (7,216615 ms y 0,740154 ms hasta el callback). No demuestran lectura CPU/Filament simultánea, corrupción ni causalidad de vibración. La demora de despacho del callback sigue siendo una explicación posible.
- Una captura cuadrática anterior muestra revisiones fuertes de predicción al llegar nuevas muestras. Los timestamps funcionales usados para velocidad difieren de captura. No se demuestra un timestamp corrupto ni se dispone de referencia física/presentación sincronizada.
- sample_blend reancla al vsync anterior; preserva el último valor muestreado, pero no garantiza continuidad de velocidad. El follower reproduce su ecuación prevista.
- C1 se evaluó solo offline y NO se implementó: redujo variabilidad de velocidad en condiciones ideales, pero aumentó sobrepaso y asentamiento en frenada sintética. No trasladar la variante sin protección a Android.
- No se implementaron coordinación binocular, instantáneas temporales compartidas ni protección heurística de correcciones. La correspondencia pose/geometría y las ventanas de propiedad requieren garantías adicionales; una corrección hacia atrás puede ser necesaria ante frenada real.

La bandera posicional afecta a todos los usuarios de PoseInterpolator, incluido el delineador si está activo. `PoseTrace.forecast_same_time` conserva un shadow cuadrático: no usarlo como comparación equivalente en OFF. Capturas antiguas cuadráticas y ablaciones numéricas no equivalen a una captura completa del modo lineal actual.

## Validación y revisión

- [BufferLifetime](buffer_lifetime_checks/README.md): implementación y verificaciones JVM ya versionadas.
- [Congelación de deformación](lash_deformation_freeze_checks/README.md): parser, fijación por sesión, guardas y comprobación de GLB locales.
- [Predicción posicional](predictor_pos_quadratic_checks/README.md): seis fixtures de eventos, 500 casos reproducibles y baseline ON bit a bit.

Ejecutar desde la raíz, con Node, Java y las dependencias Kotlin en caché indicadas por los scripts:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File offline_analysis/buffer_lifetime_checks/run_checks.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File offline_analysis/lash_deformation_freeze_checks/run_checks.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File offline_analysis/predictor_pos_quadratic_checks/run_checks.ps1
```

Los checks son JVM/estáticos; no ejecutan Flutter, instalan ni controlan el dispositivo. La compilación Kotlin release arm64 se validó durante la implementación, excluyendo la tarea de compilación Flutter. La visualización de todos los estados y recursos sigue requiriendo revisión en dispositivo.

Se excluyen de esta entrega capturas, CSV/JSON de resultados, SVG generados, vídeos, logs, cachés, reportes Gradle y el script local `run_exp.ps1`. Los fixtures pequeños de regresión son entradas de pruebas, no una captura completa. Los informes extensos y scripts exploratorios nuevos permanecen locales; este documento conserva sus conclusiones pertinentes y límites.
