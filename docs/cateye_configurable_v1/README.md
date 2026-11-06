# Cat Eye configurable v1

Checkpoint previo: d5d82c3, rama experiment/pestanas-estilo-tiktok.

El Cat Eye original sigue siendo el inicial y Restaurar original vuelve a sus
archivos intactos. Al elegir una opción se genera una variante procedural Cat Eye;
no es una modificación de los vértices del asset original. Los otros diez estilos
conservan sus assets y aparecen también en Efecto. Esta primera fase personaliza
solo Cat Eye.

Parámetros combinables:
- Largo: corto (0.78), medio (1), largo (1.23), respecto a la raíz.
- Técnica: clásica 72 fibras individuales, volumen 48 abanicos de 3,
  megavolumen 40 abanicos de 6, híbrida 56 grupos alternados de 1 y 3.
- Grosor nominal: 0.05, 0.07, 0.10, 0.15 mm. La escala visual es proporcional,
  calibrada a 0.028 unidades para 0.15; no constituye una medición física en cámara.
  Se necesita validación visual del salón para confirmar las intensidades.

48 combinaciones; 3,074–9,794 vértices por ojo. Generación determinista en compute,
fuera del isolate de UI, solo al elegir parámetros, con debounce de 120 ms y caché
por receta/version/lado. Solicitudes antiguas se descartan antes de cargar. No se
cambia el seguimiento, la cámara, el giro del parpadeo ni el anclaje nativo.
Cada variante usa el mismo binding existente y fila de raíz Y=0.

El guardado de cliente describe solo la receta aplicada; no permite guardar una
selección aún pendiente. Cambiar de estilo vuelve a sus assets originales.

## Verificación

- flutter test --no-pub test/cat_eye_recipe_test.dart test/cat_eye_menu_test.dart
- dart run tools/lashes/export_cat_eye_recipes.dart (genera GLBs en build/)
- Prueba AssetCheckKt del harness de root_binding_checks sobre las posiciones
  extraídas de las 96 GLBs: abiertos/cerrados, error máximo 0.172 px (<2 px).
- Compilación Android arm64 debug satisfactoria.
- Miniaturas renderizadas de las propias mallas con render_lash_thumbnail.py;
  no se empaquetan las 96 GLBs, solo se generan las combinaciones utilizadas.

La apariencia, la aplicación de ajustes y el anclaje fueron confirmados
en dispositivo por el usuario durante esta sesión.

## Corrección del bloqueo «Aplicando»

La limpieza de `_pending` devolvía el resultado de Map.remove: el mismo Future
que whenComplete estaba completando. Eso creaba una espera circular tanto en
éxito como en error, antes de enviar los modelos a Android. Se usa ahora un
callback sin retorno. El proveedor de directorio es inyectable para probar la
caché real con archivos temporales, sin depender de plugins del dispositivo.

La regresión reproduce dos timeouts con el callback anterior. Con la corrección,
las siete pruebas de caché, recetas y menús pasan, incluyendo deduplicación,
reutilización de archivos y reintento después de error. No se modificó el renderer.
La corrección fue posteriormente compilada e instalada por Wi-Fi; el usuario
confirmó que ya aplica los ajustes.

## Extensión a los 11 estilos

Los controles se aplican ahora a los 11 presets locales (528 combinaciones).
Cat Eye conserva su modelo inicial, receta, escala y clave de caché v1. Los
otros diez se generan ligeros al seleccionarlos y usan claves por estilo v2;
los assets anteriores y respaldos permanecen intactos. Restablecer vuelve a la
receta predeterminada del estilo; Cat Eye conserva Restaurar original.

Perfiles: Natural y Doll Eye con centro largo, Cat Classic/Kitten con alargamiento
exterior moderado, Foxy con barrido exterior, Squirrel con pico antes del extremo,
Wispy/Kim K con picos alternados, Anime con grupos espaciados y picos más largos,
Wet Look con abanicos estrechos. Largo, técnica y grosor se combinan sobre cada
perfil. Los 528 pares pasan límites, finitud, espejo, índices y raíz común Y=0.
Las pruebas de caché y menús también pasan. El usuario confirmó que los estilos
y combinaciones funcionan bien; queda pendiente la presentación al cliente.

## Arranque y asistente: estado confirmado

Se eliminó la pantalla del espejo con espera fija de 1.1 s. El probador monta la
cámara y los controles detrás de una carga que se retira al primer frame real,
incluso sin rostro. Se añadió un ojo vectorial animado con parpadeo y aro dorado,
respetando reducir movimiento. Permisos y fallos de arranque permiten volver.
El usuario confirmó que la carga premium se ve bien y abre correctamente.

El asistente mantiene la vista previa sincronizada también con clienta echada;
no conmuta a una TextureView inicialmente oculta dentro del VirtualDisplay.
Los cambios de fuente invalidan imágenes pendientes del modo anterior.
Atrás cierra primero la guía y restablece el análisis normal. La salida al inicio
se difiere al final del frame, evita navegación recursiva desde PopScope y
pospone la limpieza del cliente hasta finalizar el desmontaje.

Validación final: compilación Android arm64 debug satisfactoria; 24 pruebas de
orientación, captura y carga aprobadas. El usuario confirmó imagen en vivo en
clienta echada y regreso correcto al probador. No cambió la geometría de anclaje,
los filtros de seguimiento ni la rotación de las fibras al parpadear.
