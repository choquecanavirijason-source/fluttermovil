# Presentación sincronizada a la tasa de cámara

Se revisó el trabajo sin confirmar recibido sobre c4c2673. Su copia original
quedó en build/pre_sync_review, junto con el diff, antes de modificarlo.

La revisión conserva el anillo de imágenes, la entrega asíncrona y SyncPresenter,
pero corrige la asociación de datos:

- Cada imagen intermedia usa pose, ancho del ojo, curva y cierre interpolados
  entre dos observaciones reales de ese intervalo. Sin pareja válida, no se
  coloca una pose futura sobre una imagen antigua. Los endpoints medidos sí se usan.
- La deformación se calcula y se sube al mostrar esa imagen, no al recibir un
  resultado futuro. Se reutilizan buffers preasignados, con callbacks nativos de
  finalización antes de permitir su siguiente escritura. Si están ocupados, se
  descarta el paquete completo, manteniendo coherentes imagen y pestañas.
- Cambio de cámara, rebind, stop y nueva SceneView invalidan las colas anteriores.
  Los pedidos del anillo también tienen epoch y las superficies, generación.
- El retraso adaptativo cambia gradualmente. La cola es limitada y descarta
  duplicados; el reloj se reinicia al cambiar de sesión. El contador de FPS se
  incrementa al entregar imagen y pose al renderer, no al recibir detecciones.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File offline_analysis/sync_presenter_checks/run_checks.ps1
```

Compila SyncPresenter y LashLineCurve reales con kotlin-math y adaptadores mínimos
para Android/estructuras de datos. Con 30 imágenes/s y 20 resultados/s, la simulación
mostró 90/90 imágenes, 60 en dos segundos de reproducción estable. Comprueba tiempos,
curva, ancho, cierre, pérdida de muestras, cambios de modelo, duplicados, límites de
recursos y cambios del origen de reloj. No es una medida del rendimiento del teléfono.

La interpolación estima el movimiento entre observaciones: no reconstruye exactamente
movimientos impredecibles ni corrige una detección errónea. Requiere un pequeño buffer
de presentación y puede descartar paquetes si el dispositivo no alcanza la tasa de
cámara. Medir SyncPresenter (fps_mostrados, retraso, deform_ms) y los tiempos de vsync
en el teléfono; comparar movimientos suaves, bruscos, del dispositivo, parpadeos y
cambio de cámara antes de dar por corregido el despegue.

Esta tarea corresponde a la primera mejora. No añade sombras, adaptación de luz,
deformación por GPU ni oclusión de perfil.

## Primera medición y refinamiento

La primera instalación revisada mostró ~12.4 entregas/s y ~41–43 ms de deformación
en las ventanas iniciales: no se alcanzaban 30 FPS en el dispositivo. El usuario
reportó mayor fluidez pero separación residual en movimientos bruscos.

Se añadió un muestreo reutilizable de 2048 intervalos para la deformación. Los
cálculos de spline y trigonometría se hacen por intervalo y luego se interpolan
para cada vértice, usando arrays preasignados por ojo/modelo. El camino anterior
del bender permanece disponible y se usa en el fallback no sincronizado.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File offline_analysis/sync_presenter_checks/check_deformation_lookup.ps1
```

El test compila el bender real y compara ambos caminos en 100 combinaciones de
ancho, arco y compensación con 2500 vértices: error máximo observado ~0.0000198 px
en posición y ~0.0000378 en componentes de tangentes. Esos límites corresponden
a las curvas probadas, no a todos los assets o geometrías degeneradas posibles.

La interpolación ahora reconstruye el origen del modelo desde la raíz interpolada.
Interpolar directamente orígenes mientras gira un asset con pivote desplazado
describe otra trayectoria de raíz y puede despegar la banda del párpado. La prueba
incluye rotación con un ancla fija y verifica que la raíz no se desplace.

La ruta sincronizada también escribe en arrays reutilizables y realiza dos
copias masivas a los buffers directos, en vez de siete escrituras directas por
vértice. El test compara el resultado del bender completo, incluidos estos buffers.
