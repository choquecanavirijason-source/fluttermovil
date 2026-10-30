# Prueba A/B de deformación de pestañas

Implementada en `experiment/tracking-v2`. No modifica filtros, calibración, cámara, matemática de transformación, bender, RendererConfiguration, delineador ni FaceMeshRenderer.

Configuración para una futura prueba manual:

```properties
lash_deformation_freeze=off
buffer_lifetime_trace=off
```

Usar `lash_deformation_freeze=on` para B. Clave ausente, vacía o inválida: OFF. El parser existente acepta espacios y mayúsculas. Mantener los demás flags idénticos entre A y B. No se ha escrito ningún archivo en el teléfono ni se ha habilitado telemetría.

## Sesión y comportamiento

CameraXManager.start lee el valor solicitado junto con PerfFlags y lo captura para ese inicio. En el hilo principal, antes de habilitar la captura y scheduleRebind, llama a LashRenderer.beginCameraSession. El valor efectivo vive en un campo volatile del renderer; no se consulta el valor recargable por frame. Cambios de archivo durante la sesión registran requested y effective con el tag LashRenderer / LASH_DEFORMATION_SESSION y se aplican en el siguiente stop/start. Un reenlace automático de CameraX, recarga de flags, cambio de modelo, parpadeo o recuperación de tracking no vuelve a fijarlo.

OFF conserva los argumentos y cuerpo funcional anterior. ON impide entrar al bloque de bendInPlace y a sus escrituras/subidas de posiciones y tangentes. El filtro y la publicación al interpolador continúan; writeInterpolatedPose, PoseFollower, LidDropRotation, escala, ancla y visibilidad no se modifican. Los cálculos de curva/apertura siguen actualizando su estado normal.

Un stop/start puede conservar una malla ya doblada. Por eso ON restaura una sola vez por inicio las geometrías existentes mediante Geometry.setVertices(engine, raw.vertices), sin reemplazar nodos ni tocar sus transforms. rawMesh conserva la geometría base preparada por la carga normal, incluidos espejo y colores. No significa restaurar los bytes del GLB ignorando esas preparaciones. Los modelos cargados posteriormente ya se construyen en reposo por la ruta habitual.

Se inspeccionó el bytecode de SceneView 2.1.1 disponible localmente: Geometry.setVertices delega en GeometryKt.setVertices, que asigna FloatBuffers nuevos, los rellena y entrega los atributos a setBufferAt. No escribe en positionBufferA/B o tangentBuffer. La restauración inicial puede subir atributos de reposo; ON elimina las subidas dinámicas por resultado, no la inicialización necesaria. No se usa Geometry.update porque puede omitir el trabajo cuando la lista de vértices no cambia aunque el VBO sí haya sido deformado por setBufferAt.

Una subida de la sesión anterior ya encolada comprueba el modo efectivo en el Runnable y se saltea en ON. El finally existente libera bendPending y finaliza el estado diagnóstico. El return está dentro del Runnable de subida, no en applyTransform; no impide publicar la pose. Llamadas ya ejecutadas antes del inicio quedan antes de la restauración en la secuencia del hilo principal. No se modifica la política de propiedad de buffers del modo OFF.

## Validaciones ejecutadas

- `git diff --check`: correcto.
- `powershell -NoProfile -ExecutionPolicy Bypass -File offline_analysis/lash_deformation_freeze_checks/run_checks.ps1`: correcto. Compila el PerfFlags real con stubs de Android; comprueba archivo/clave ausentes, ON/OFF, normalización, valores vacíos e inválidos, logging, descripción y bufferLifetimeTrace apagado por defecto. Compila y ejecuta los métodos de sesión extraídos del renderer con dependencias simuladas; verifica cambios en caliente diferidos y restauración por nueva sesión ON.
- `static_checks.cjs`: el cuerpo OFF de applyTransform coincide con HEAD al retirar las guardas añadidas; ON rodea la única llamada al bender y todas sus subidas; push al interpolador sigue fuera del bloque; otros renderers y configuración no cambiaron.
- Los 12 GLB en assets/modelos tienen geometría no vacía y cero animations, skins y morph targets. autoAnimate permanece intacto: esos modelos no tienen animaciones que ejecutar.
- Compilación real: `:app:compileReleaseKotlin --offline -Ptarget-platform=android-arm64 -x compileFlutterBuildRelease --console=plain`, con GRADLE_USER_HOME en la caché existente E:/AndroidBuildCache/gradle. BUILD SUCCESSFUL. La tarea de compilación Flutter fue excluida; no se lanzó Flutter ni se instaló nada. Log: kotlin_arm64_build.log (ignorado por Git).
- Los intentos iniciales debug/release para todas las arquitecturas fallaron por dependencias Flutter armeabi_v7a/x86_64 no disponibles offline. La verificación arm64 posterior sí compiló el código Kotlin de la aplicación.

## Límites y prueba visual pendiente

Las pruebas JVM usan dependencias simuladas para parser/sesión y no renderizan Filament. No se confirmó la apariencia en pantalla: requiere una ejecución posterior autorizada. La geometría original tiene una ruta válida de construcción y atributos; el ajuste al párpado puede ser peor en reposo. No se inspeccionaron modelos descargados externos a assets/modelos: comprobar que no tengan animaciones antes de usarlos para comparar.

Evaluar A–B–A con el mismo modelo/estilo y movimientos suaves, primero con ojos abiertos. No cambiar parámetros entre bloques. Al parpadear siguen los movimientos de cierre del nodo, pero la banda ya no recibe compensación geométrica dinámica; separación o penetración durante el cierre no demuestra un fallo de pose. Separar también pérdidas de tracking y cambios de modelo del tramo evaluado.

Si persiste el temblor de todo el conjunto en B, la deformación dinámica no es necesaria para ese temblor. Si mejora, se implica la ruta de deformación (forma, tangentes, subidas o coste de ejecución), sin demostrar corrupción ni aislar automáticamente el mecanismo. La comparación cambia la carga de CPU/subidas y no garantiza idéntica temporización. Este cambio no corrige ni amplía la telemetría de Filament.
