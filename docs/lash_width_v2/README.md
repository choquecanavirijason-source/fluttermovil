# Cat Eye original y fibras más visibles

Versión activa de prueba, sin commit.

- Cat Eye utiliza `cateyeleft.glb` y `cateyeright.glb` originales, copiados
  sin modificación del respaldo `modelos_respaldo/originales_2026-11-06_85488b5/`.
  Se comprobó igualdad SHA-256; no son los alternativos con sufijo `1`.
- Los otros diez estilos se regeneraron con `--width-multiplier 3`.
  Se mantienen el número de fibras, segmentos y vértices, los largos,
  direcciones y curvaturas. Se incrementa el ancho de las cintas afinadas.
- Las once miniaturas muestran sus modelos actuales. La de Cat Eye se
  renderizó desde su GLB original.
- Se conserva el material negro, el render por ambos lados y el anclaje actual.

El catálogo ligero previo completo está en
`modelos_respaldo/ligeros_11_antes_grosor_2026-11-06/`, con hashes de respaldo.
No se sobrescribió el respaldo inicial de los modelos pesados.

Los veinte GLB ensanchados pasaron la validación geométrica y el ensayo del
deformador real con ojos abiertos/cerrados; error máximo observado en esa
prueba: 0,165 píxeles. `vista_previa.png` contiene las vistas de esos modelos.
El grosor aparente final necesita confirmación en el teléfono.

Para reproducir únicamente los diez estilos ensanchados:

```powershell
python tools/glb/generate_mobile_lashes.py --styles wispy catclassic foxyeye natural dolleye squirrel kitten wetlook anime kimk --width-multiplier 3 --out build/lash_width_v2/modelos --preview build/lash_width_v2/vista_previa.png --thumbnails
python tools/glb/validate_mobile_lashes.py --models build/lash_width_v2/modelos --fixtures build/lash_width_v2/fixtures --expected-pairs 10
```

Cat Eye se restaura del respaldo en lugar de regenerarlo. El catálogo activo
ahora es mixto (Cat Eye original y veinte GLB procedurales); el validador
específico de raíces Y=0 se aplica al staging procedural, no al Cat Eye antiguo.

La extracción de assets a la caché compara también contenido. Un GLB de
igual tamaño pero distinta geometría ya no reutiliza silenciosamente su
copia anterior.
