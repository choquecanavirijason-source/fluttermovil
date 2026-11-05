# Forma de párpado en coordenadas del ojo

El filtro anterior guardaba puntos en píxeles de cámara. Al combinar esos puntos
atrasados con el ancla y la tangente actuales, un movimiento rígido podía modificar
artificialmente la curva. Ahora se filtra alrededor del centro del párpado, en los
ejes de su tangente y perpendicular, normalizado por la distancia entre cantos.
La reconstrucción usa el marco del frame actual. Se conservan los parámetros de
One Euro; la referencia de 46 px aproxima el ancho de ojo de la calibración previa.

Se usa `FaceLandmarkerResult.timestampMs()` para ambos ojos en lugar de la hora
de ejecución. Se inicializa el filtro desde la primera muestra y se descarta el
historial después de 250 ms sin mediciones fiables, un reinicio del reloj,
un cambio de cantidad de puntos o geometría inválida.

Ejecutar desde la raíz:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File offline_analysis/upper_lid_local_checks/run_checks.ps1
```

Compila los filtros Kotlin reales con adaptadores mínimos de ImagePoint y las
constantes leídas de RendererConfiguration. Comprueba que la misma secuencia
de forma con ruido tenga resultados equivalentes bajo traslación, giro y escala
variables; también verifica suavizado desde la segunda muestra y reinicialización.

Incluye OpennessTracker real: comprueba una apertura visual continua entre los
umbrales de parpadeo, conservando la histéresis independiente que protege la forma.
La reapertura intermedia ya no cambia bruscamente la rotación, la elevación del
ancla y la compensación de banda de 0 a 1. Esto no calibra los coeficientes de
MediaPipe para una anatomía concreta; hace falta validación visual en dispositivo.

Estas pruebas verifican el filtro, no la precisión de MediaPipe ni la calidad
visual del render completo. Falta comparar en teléfono: reposo, desplazamiento
lateral, inclinación, acercamiento y parpadeos. No se ha sustituido ni reentrenado
el modelo de detección ni modificado la sincronización de cámara existente.
