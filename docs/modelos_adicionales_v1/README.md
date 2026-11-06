# Seis diseños adicionales

Los estilos se conservan; su grosor activo se actualizó posteriormente.
Ver `../lash_width_v2/README.md` para el catálogo actual y su validación.

El selector local ahora contiene once estilos. Los cinco modelos ligeros
anteriores conservan exactamente sus GLB, verificados por SHA-256.

| Diseño | Carpeta activa | Vértices por ojo | Forma |
|---|---|---:|---|
| Doll Eye | `assets/modelos/dolleye/` | 4.514 | Máximo largo central y extremos cortos |
| Squirrel | `assets/modelos/squirrel/` | 4.394 | Pico antes de la esquina exterior y cola corta |
| Kitten | `assets/modelos/kitten/` | 3.914 | Elongación exterior suave |
| Wet Look | `assets/modelos/wetlook/` | 4.514 | Grupos estrechos de fibras, efecto mojado |
| Anime | `assets/modelos/anime/` | 3.554 | Picos largos separados sobre una base corta |
| Kim K | `assets/modelos/kimk/` | 5.394 | Textura irregular y picos largos sobre base más densa |

Cada carpeta contiene dos GLB reflejados y una miniatura transparente
renderizada desde la malla. Los modelos conservan la raíz Y=0, una sola
malla/primitive y el formato del lector Android. Los seis identificadores
usan el ajuste neutro existente; la diferencia estética está en los assets.
No se modificaron los filtros ni el giro del parpadeo.

Los doce GLB nuevos pasaron la validación estructural y la prueba de
proyección de la banda con el deformador real, abiertos y cerrados; el error
máximo observado fue 0,077 píxeles en esa prueba geométrica. También se
validó la estructura de los veintidós GLB del catálogo completo. La apariencia
y el rendimiento en cámara requieren confirmación del usuario.

`vista_previa.png` contiene vistas calculadas de las seis mallas nuevas.
La app mantiene por ahora el material magenta y la referencia verde para
comprobar el anclaje. Los originales pesados permanecen en el respaldo
`modelos_respaldo/originales_2026-11-06_85488b5/`.

Las cintas ligeras necesitan `Material.CullingMode.NONE` también cuando se
sustituye su material GLTF por el magenta. El material de color estándar
no tiene capacidad de iluminación doble cara; Filament advierte que
`setDoubleSided(true)` no se aplica en ese caso. La geometría puede seguir
correctamente anclada y aun así desaparecer al presentar su reverso.
La corrección del material requiere comprobación visual en el dispositivo.

Para regenerar únicamente estos seis diseños:

```powershell
python tools/glb/generate_mobile_lashes.py --styles dolleye squirrel kitten wetlook anime kimk --out build/modelos_adicionales_v1/modelos --preview build/modelos_adicionales_v1/vista_previa.png --thumbnails
python tools/glb/validate_mobile_lashes.py --models build/modelos_adicionales_v1/modelos --fixtures build/modelos_adicionales_v1/fixtures --expected-pairs 6
```

Para un catálogo enteramente procedural, usar `--expected-pairs 11`.
El catálogo activo mixto con Cat Eye original se valida como se documenta
en `../lash_width_v2/README.md`.
