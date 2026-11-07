# Catálogo administrable del probador

## Alcance

El administrador gestiona los estilos que consume el probador mediante `GET /catalogs/tryon/manifest`. Los once estilos originales conservan su geometría y Cat Eye conserva su modelo original en su configuración predeterminada. No se modificaron el seguimiento nativo, el anclaje al párpado ni las cámaras.

El editor permite crear estilos nuevos con un perfil numérico: curva de largos desde el lagrimal al extremo, curvatura, apertura, inclinación, grupos por técnica, picos y grosor visual. No está limitado a los nombres de los once estilos iniciales. Los estilos nuevos compatibles con el motor v1 no requieren otra APK después de instalar esta integración. Una capacidad nueva del motor sí necesita actualizar la app.

## Uso del administrador

- `/designs`: estilos del probador. Crear o duplicar, editar información, forma y opciones del salón; guardar borrador y publicar cuando esté listo.
- `/designs/legacy`: catálogo anterior, conservado. Los demás catálogos comerciales y el recomendador de IA anterior no se migraron a este contrato.
- Los cambios de borrador no llegan al teléfono. Publicar crea una versión inmutable. Restaurar una versión histórica crea un borrador que requiere publicación.
- La clave del estilo permanece estable aunque cambien nombre u orden. Los estilos publicados se desactivan; solo los borradores nunca publicados se pueden eliminar.
- Las opciones disponibles de largo, técnica y grosor y sus valores iniciales se configuran por estilo.

La vista previa del editor es una simulación de diseño; el encaje real se verifica en el teléfono. El generador limita cada ojo a 240 fibras para proteger el rendimiento.

## Sincronización y continuidad

La app consulta el catálogo después del primer fotograma, para no bloquear la apertura. Si la persona ya empezó a interactuar, el catálogo actualizado queda disponible para la siguiente entrada. Un fallo de red o un manifiesto incompatible conserva la última copia válida. Sin copia previa se usan los once estilos incluidos.

Cada aplicación guardada para una clienta incluye la selección y una copia de su perfil y versión. Editar el catálogo posteriormente no cambia ese registro.

## Activación pendiente en el entorno del cliente

1. Respaldar la base de datos y desplegar el backend junto con `app/core/tryon_defaults.json`. La migración `add_tryon_catalog` registrada en el arranque crea las tablas nuevas y la columna JSON de seguimiento; la carga inicial es idempotente y no sobrescribe estilos editados.
2. Construir y publicar el administrador con la URL de API del entorno. Si se distribuye el backend empaquetado como ejecutable, incluir también el JSON anterior como recurso del paquete.
3. Instalar la APK actualizada una vez. Comprobar permisos `catalog:view` y `catalog:manage` de quienes administrarán el catálogo.
4. Publicar un estilo de prueba, volver a entrar al probador y verificar ambos ojos abiertos/cerrados y ambas cámaras. Comprobar también el funcionamiento sin red.

La implementación está preparada localmente; esta tarea no desplegó servicios ni creó un commit.

## Verificación

- Backend: 10 pruebas sobre borradores/publicación, revisiones, permisos, límites, migración y conservación de recetas de clientas, con SQLite aislado.
- Flutter: 12 pruebas, incluyendo las 528 combinaciones originales, perfiles nuevos, caché y compatibilidad del manifiesto.
- Navegador: creación, edición, publicación e historial contra una API local aislada (`adminElashes/tests/tryon-editor-smoke.cjs`).
- Compilación del administrador y APK debug Android arm64 completadas.
- El chequeo TypeScript global conserva errores previos ajenos a este módulo. La compilación Vite pasó; para el chequeo con la versión instalada de TypeScript se usó `--ignoreDeprecations 5.0` porque el proyecto declara `6.0`.

El servidor `tests/tryon_preview_server.py` es exclusivamente una herramienta local de pruebas con autenticación simulada; no debe desplegarse.

## Catálogos configurables (motor v2)

Las secciones del menú ahora son **Estilos y efectos**, **Largos**, **Técnicas**, **Grosores** y Tipos de ojo. `/effects` usa la misma colección que `/designs`; `/lash-designs` y `/volumen` abren las técnicas del probador. Las pantallas anteriores se conservan en sus rutas `/legacy` para consultar registros, sin convertir ni borrar datos comerciales.

- Largos: nombre y escala relativa de 0.4 a 1.8; los iniciales siguen siendo 0.78, 1 y 1.23.
- Grosores: nombre y diámetro nominal de 0.03 a 0.25 mm; los iniciales siguen siendo 0.05, 0.07, 0.10 y 0.15.
- Técnicas: distribución base, 1–8 fibras por grupo, mezcla con pelos individuales, densidad relativa y apertura. Las técnicas iniciales conservan la distribución particular de cada estilo. El generador limita la geometría a 240 fibras por ojo.
- Efectos: se crean y editan en el mismo editor de estilos, evitando otra lista desconectada.

Cada categoría admite hasta 64 opciones con identificadores estables y publicación explícita. Crear una opción no la asigna automáticamente a todos los estilos: **crear → guardar borrador → publicar → Estilos y efectos → editar estilo → Opciones del salón → habilitar y elegir selección inicial → guardar y publicar**. Desactivar una opción no puede dejar sin combinaciones a un estilo publicado activo. Al editar un estilo se retiran las opciones que ya están desactivadas.

El contrato `/catalogs/tryon/manifest` ahora publica `schema_version: 2`, `engine_version: 2` y `options` por categoría. La app nueva acepta también manifiestos v1. Las APK anteriores conservan su catálogo válido/local ante v2; necesitan actualizarse para consumir opciones nuevas. La caché de geometría incluye los parámetros y versiones de las opciones. Las recetas guardadas incluyen `resolved_options` para conservar exactamente los valores usados aunque después cambien los catálogos.

Los endpoints administrativos son `GET/POST /catalogs/tryon/options/{kind}`, `PUT /catalogs/tryon/options/{kind}/{id}` y `POST /catalogs/tryon/options/{kind}/{id}/publish`; requieren los mismos permisos de consulta/gestión de catálogo. Las tablas de opciones y su historial se crean idempotentemente desde la migración de catálogo existente.

Verificación adicional: 14 pruebas backend, 17 pruebas Flutter entre regresión y opciones, comparación exacta de los buffers de geometría de las 528 combinaciones originales, flujo de navegador creando largo/técnica 5D/grosor y asignándolos a un estilo; compilaciones Vite y APK debug arm64 completadas. El análisis Flutter solo mantiene el aviso previo de `_openRecommendation` sin uso; TypeScript global mantiene sus errores anteriores fuera del módulo.

Se actualizó el backend **local de Docker** después de respaldar su base. No se desplegó al VPS ni se instaló esta APK en un teléfono. La configuración actual de la app sigue apuntando al VPS: para probar cambios del administrador local en un dispositivo hay que apuntar una compilación de desarrollo al backend local accesible por LAN, o desplegar esta API al entorno que usa la app. Los datos de pruebas del navegador están en una API aislada; no se insertaron estilos de demostración en la base local del salón.

## Vista previa 3D del administrador

El editor de estilos incluye una malla de fibras 3D generada con las dimensiones, curvatura, apertura y opciones del perfil. Se puede girar arrastrando, acercar con la rueda o un gesto de dos dedos, usar los botones Frente / Perfil / Desde arriba y restablecer la vista. Las flechas y +/− ofrecen control por teclado. Abierto/Cerrado muestran el diseño sobre un contorno ilustrativo; el encaje real sigue dependiendo de los landmarks de la cámara.

El visor usa WebGL sin añadir dependencias y dibuja al cambiar la vista o el diseño. Si WebGL no está disponible, muestra una referencia 2D y un aviso. Se liberan los buffers y recursos al cambiar el diseño o cerrar. No se modificaron el motor ni el seguimiento del teléfono.

Verificación: `tests/tryon-preview-geometry.cjs` recorre las 528 combinaciones iniciales; `tests/tryon-preview-3d-smoke.cjs` comprueba píxeles visibles, vistas, arrastre, zoom, teclado, cambios de forma, tamaño móvil y confirmación interna con datos aislados. La compilación Vite pasó.

## Ayuda de acabado y distribución

Cada uno de los 12 ajustes de Acabado y distribución tiene un botón «?». Abre una guía interna con explicación, efecto al subir/bajar, precauciones específicas y una muestra 3D que se puede girar. Los botones de ejemplo y el control de prueba modifican únicamente una copia del perfil. Se puede recorrer la guía con Anterior/Siguiente, volver al valor actual y cerrar con Entendido o Escape.

La demostración usa largo medio y 0.15 mm; selecciona automáticamente la técnica y el ángulo adecuados para explicar el parámetro. Para explicar picos, activa una frecuencia/altura de ejemplo indicada en el texto. No aplica los valores al borrador ni publica cambios.

## Tutoriales animados y opciones con vista 3D

Las ayudas ahora usan una demostración de 24 segundos con comparación de valores desde tres ángulos. Incluyen reproducción/pausa, repetir, barra de progreso y saltos a frente/perfil/arriba. El texto ampliado queda plegado en «Más detalles». Se detienen al cerrar o al ocultar la página y respetan la preferencia de reducir movimiento. La geometría se actualiza reutilizando los buffers del visor.

Los formularios de Largos, Grosores y Técnicas incluyen vista 3D en vivo y selector de estilo de prueba, con estilos del catálogo y bases incluidas como respaldo. Las opciones numéricas y las dos opciones de distribución tienen ayuda animada; también existe «Ver demostración animada». La vista admite giro, zoom, abierto/cerrado y ampliación. Los valores provisionales de la demostración no modifican los formularios ni publican datos.

Se verifican las 12 demostraciones de estilos, 8 demostraciones de opciones y las 528 combinaciones iniciales con pruebas de geometría. Los recorridos de navegador comprueban cambio visible de la malla, reproducción, pausa, repetición, navegación, selección de estilo y conservación de los valores del formulario.

## Ejecutar el teléfono contra el administrador local

La app admite `API_HOST`, `API_BASE_URL` y `API_PREFIX` mediante `--dart-define`, conservando el VPS como valor predeterminado. Para una prueba local con ADB por USB o Wi-Fi:

1. Comprobar `adb devices` y crear el túnel con `adb -s DISPOSITIVO reverse tcp:8000 tcp:8000`.
2. Ejecutar `flutter run -d DISPOSITIVO --dart-define=API_HOST=http://127.0.0.1:8000 --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=API_PREFIX=`.
3. Iniciar sesión con una cuenta del backend local si la sesión anterior no es válida. El administrador local y el teléfono consultan así la misma base.

El túnel debe restablecerse si se pierde la conexión ADB. Una compilación local de prueba no debe distribuirse como APK del salón: para el entorno remoto, compilar sin estos overrides.
