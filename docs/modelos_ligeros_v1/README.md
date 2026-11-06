# Modelos ligeros de pestañas, versión 1

Historial de la primera versión ligera. El estado activo posterior (Cat Eye
original y otros diseños ensanchados) se describe en `../lash_width_v2/README.md`.

Activos en `assets/modelos/`, con las mismas rutas declaradas en `pubspec.yaml`.
Cada diseño tiene un GLB izquierdo y su reflejo derecho. Son modelos
procedurales nuevos, no una reducción destructiva de los originales.

| Diseño | Vértices por ojo | Triángulos por ojo | Forma |
|---|---:|---:|---|
| Cat Eye | 4.514 | 4.080 | Largo progresivo hacia el extremo exterior |
| Wispy | 6.434 | 5.808 | Fibras suaves con picos largos intercalados |
| Cat Classic | 4.994 | 4.512 | Abanico uniforme y elongación exterior moderada |
| Foxy Eye | 4.874 | 4.404 | Dirección exterior más marcada y menor rizo |
| Natural | 2.514 | 2.280 | Menor densidad y largo, máximo suave en el centro |

## Geometría compatible con el probador

- Una malla, un primitive indexado y un nodo sin transformaciones por GLB.
- Raíces en Y=0 y fibras hacia +Y. El anclaje actual de la app adapta esa
  base a los landmarks; el asset no impone un arco vertical fijo al párpado.
- Cintas cruzadas, curvas y afinadas, con normales y color por vértice.
- Sin texturas, transparencias ni dependencias externas.
- El raíl de unión es fino; la fila inferior coincide con la raíz detectada.

`vista_previa.png` muestra vistas calculadas de estas mallas, abiertas,
cerradas y oblicuas. No sustituye la validación estética ni de FPS en cámara.
La app conserva por ahora su material magenta de diagnóstico.

## Originales conservados

Los 12 GLB anteriores están completos en
`modelos_respaldo/originales_2026-11-06_85488b5/`, fuera del bundle activo.
`manifest_originales.json` contiene tamaños y SHA-256, comprobados después
del traslado. Incluye los dos Cat Eye alternativos que no estaban declarados
en el bundle. No se borraron ni se modificaron los GLB originales.

Para volver a ellos, conservar primero esta versión y copiar las cinco
carpetas de estilos de ese respaldo a `assets/modelos/`. No copiar el
manifiesto de respaldo como parte de los assets de la app. Recompilar y
reiniciar la app para que vuelva a extraer los modelos del bundle.

## Reproducir y validar

Desde la raíz del proyecto:

```powershell
python tools/glb/generate_mobile_lashes.py --styles cateye wispy catclassic foxyeye natural --out build/modelos_ligeros_v1/modelos --preview build/modelos_ligeros_v1/vista_previa.png
python tools/glb/validate_mobile_lashes.py --models build/modelos_ligeros_v1/modelos --fixtures build/modelos_ligeros_v1/fixtures
```

El generador es determinista. La exportación GLB usa Python estándar; la
vista previa necesita Pillow y NumPy. La validación verifica estructura,
índices, normales, ausencia de triángulos degenerados, raíz y simetría.
También se probaron los diez GLB con el deformador real y las transformaciones
abierta/cerrada: error máximo observado de la banda respecto al contorno
objetivo, 0,093 píxeles en la prueba geométrica de referencia.

La sustitución afecta los cinco presets locales. No cambia archivos del
catálogo remoto ni los filtros de seguimiento.
