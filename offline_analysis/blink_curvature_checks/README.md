# Inversión intermitente del arco al parpadear

Base: checkpoint d2f074f más la corrección validada del espejo de la trasera.
Se conservan el ángulo de cierre, umbrales, filtros de pose, ancla y geometría
original del checkpoint. No se activan los perfiles experimentales anteriores.

La compensación 1/cos(theta) recortada saltaba entre +máximo y -máximo al pasar
90°. Además, el suavizado adicional de vértices podía mantener el signo anterior
cuando el nodo ya había cruzado ese ángulo: el arco proyectado quedaba invertido.

La corrección usa una inversa amortiguada y continua, que aplana el arco al pasar
de canto. Cuando cambia la compensación de cierre, se omite el segundo suavizado
de malla: el cierre ya llega suavizado y debe coincidir con la rotación. Si la
subida anterior de malla sigue pendiente, se retiene también su ángulo de cierre.
En modo sincronizado se capturan pose/cierre antes de encolar cada imagen para
evitar leer el parpadeo de un resultado posterior.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File offline_analysis/blink_curvature_checks/run_checks.ps1
```

Se compila LidDropRotation real con kotlin-math y las constantes actuales.
10001 cierres verifican continuidad y límites. Un replay de parpadeo con muestras
separadas reproduce la inversión con el alpha anterior y comprueba que la nueva
política conserva el sentido del arco. En reposo conserva el suavizado original.
La prueba es numérica: no sustituye la validación visual ni comprueba toda la
gestión de buffers GPU o los errores del detector.
