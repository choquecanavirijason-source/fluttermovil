# Continuidad del proyecto E-Lashes

Actualizado el 9 de noviembre de 2026. Este documento describe el estado local para continuar en Claude Code.

## Repositorios y ramas verificadas

- App Flutter en `D:\proyectos\elashes-probador\fluttermovil`.
- Rama actual de Flutter `experiment/pestanas-estilo-tiktok`.
- Administrador y API en `D:\proyectos\elashes main\apifast`.
- Frontend en `adminElashes`, React, TypeScript y Vite.
- Backend en `elashesbackend`, FastAPI y SQLAlchemy.
- Rama actual del repositorio del administrador `main`.
- Último commit verificado del administrador `21052ef`, merge de `feat/catalogo-probador-configurable`.
- Hay cambios locales modificados y archivos nuevos en ambos repositorios. Revisar `git status` antes de operar.
- El administrador cambió de rama respecto a un punto anterior del chat. Conservar el estado actual, revisar su historial y evitar asumir que sigue en la rama de la funcionalidad.

## Restricciones importantes del usuario

- Conversación y explicaciones en español, breves y concretas.
- La posición, el anclaje, el parpadeo y el seguimiento de pestañas fueron aprobados después de muchas pruebas. Proteger ese comportamiento.
- El usuario pidió explícitamente que el seguimiento se modifique únicamente si es absolutamente necesario.
- Conservar el arreglo de la cámara trasera y el funcionamiento de la frontal.
- Los 11 estilos configurables y el Cat Eye actual funcionan y fueron aprobados.
- El usuario pidió hacer commits únicamente cuando lo indique. Los cambios recientes siguen pendientes de commit.
- El usuario suele ejecutar `flutter run` y generar sus APK. Coordinar las pruebas con esa sesión y conservar su trabajo.
- La interfaz del selector debe conservar transparencia tipo cristal. El usuario rechazó el fondo verde sólido.
- La interfaz presentada a la clienta debe usar etiquetas directas. El usuario rechazó expresiones como «probable».
- Para casos ambiguos se implementó un aviso para ajustar la posición y la posibilidad de confirmación profesional.
- Evitar prometer detección automática de características que realmente se seleccionan manualmente.

## Qué funciona en el probador

- Cat Eye, Wispy, Cat Classic, Foxy, Natural, Doll Eye, Squirrel, Kitten, Wet Look, Anime y Kim K.
- Opciones configurables de largo, técnica y grosor provenientes del catálogo publicado.
- Los IDs de opciones son estables y admiten opciones nuevas como 0.25 mm.
- Catálogo remoto versionado, caché local y respaldo con estilos empaquetados.
- El backend de prueba tiene además un estilo publicado llamado `prueba pestana`.
- La miniatura embebida de ese estilo parpadeaba porque se decodificaba Base64 en cada reconstrucción de cámara. Se convirtió `DesignThumbnailImage` a StatefulWidget y conserva el MemoryImage mientras el path sea igual.
- El selector reúne título, filtros y miniaturas en un panel transparente para evitar superposiciones.
- Los filtros ahora se llaman «Recomendados» y «Todos».
- Recomendados ordena los cinco estilos mejor puntuados. Todos conserva la colección completa.
- La selección actual de pestañas se conserva al cambiar el perfil de mirada. La profesional elige después qué estilo aplicar.

## Nueva ficha «Tu mirada»

Se abre tocando la etiqueta superior de la mirada en el probador.

### Mediciones automáticas

- Forma del contorno con tres etiquetas `Redondo`, `Almendrado`, `Rasgado`.
- Separación relativa entre esquinas internas respecto al ancho medio de los ojos, con etiquetas `Cercanos`, `Equilibrados`, `Separados`.
- Inclinación con etiquetas `Ascendente`, `Neutra`, `Descendente`.
- Diferencia relativa de apertura entre ojos, presentada como apertura equilibrada o diferencia de apertura.

### Confirmación profesional

- Párpado con opciones pliegue visible, encapotado, monólido.
- Profundidad con opciones equilibrada, hundidos, prominentes.
- Corrección manual de la forma del contorno.

Párpado y profundidad requieren selección de la profesional en la versión actual. No se ha entrenado ni incorporado un clasificador visual automático de esas características.

### Objetivo de la clienta

- Personalizado según la mirada.
- Natural.
- Abrir la mirada.
- Alargar.
- Realzar.

Estas opciones influyen en las sugerencias geométricas. Son reglas iniciales de preferencia estética y necesitan pruebas con el salón.

### Estabilidad y calidad

- El análisis reúne muestras de ojos abiertos durante aproximadamente 3 segundos y bloquea el resultado durante la sesión.
- Se exigen al menos 12 muestras, admitiendo frecuencias de análisis bajas.
- El botón «Volver a analizar» inicia otra lectura. Usarlo al cambiar de persona o fotografía.
- Se rechazan lecturas sin rostro, aperturas extremas, diferencias grandes de ancho y separaciones extremas.
- Lecturas inestables o cercanas a los umbrales de forma piden ajustar la posición.
- La forma usa actualmente umbrales heurísticos de ancho/alto 2.6 y 3.6.
- La altura se mide perpendicular a la línea entre esquinas de cada ojo. Se corrigió el cálculo anterior que mezclaba parte de la inclinación con la altura.
- Estos valores siguen pendientes de calibración con etiquetas humanas revisadas.

### Guardado de la ficha

- `eye_assessment` se guarda dentro del JSON de la receta del probador.
- El backend valida forma, origen automático/profesional, párpado, profundidad, objetivo y medidas.
- Las recetas antiguas siguen siendo aceptadas.
- Las notas legibles tienen un máximo de 255 caracteres por el contrato existente. Se acortan cuando es necesario; la ficha completa queda en el JSON.
- El backend local fue reiniciado con este contrato actualizado.

## Archivos principales de Flutter

- `lib/core/recommendation/eye_shape_analyzer.dart` contiene las métricas, el análisis y SessionEyeAnalysis.
- `lib/core/recommendation/lash_consultation.dart` contiene elecciones profesionales, objetivos, etiquetas y serialización.
- `lib/lashes/lash_style_recommender.dart` puntúa cualquier diseño por su geometría. Usa distribución de largos, curvatura, barrido, densidad y perfil de mirada; evita depender del nombre del estilo.
- `lib/screens/widgets/eye_consultation_sheet.dart` contiene la ficha y sus controles.
- `lib/eye_tracking_page.dart` integra sesión estable, ficha, recomendaciones, etiquetas y guardado.
- `lib/lashes/tryon_catalog.dart` incluye lectura de categorías adicionales y snapshot con eye_assessment.
- `lib/screens/widgets/eye_tracking_header.dart` limita el ancho de la etiqueta para evitar choques con botones laterales.
- `lib/screens/widgets/design_thumbnail_image.dart` conserva imágenes Base64 entre reconstrucciones.
- `lib/screens/widgets/eye_tracking_design_menu_bar.dart` y `eye_tracking_filter_row.dart` contienen el selector reorganizado.

## Administrador y API

Leer primero `adminElashes/AGENTS.md` y los skills locales referenciados allí.

- Página `/eye-types` en `adminElashes/src/pages/admin/tryon/EyeRecommendations.tsx`.
- El menú superior usa `src/components/layout/navigation.config.ts`. Añadir una ruta solo en AppSidebar no basta.
- Muestra tarjetas ilustradas para las categorías del detector, incluidos Rasgado/alargado y las inclinaciones.
- El flujo principal explica las recomendaciones automáticas. Las categorías manuales adicionales se encuentran en «Mostrar opciones manuales avanzadas».
- Las categorías manuales admiten creación, edición, asignación visual de estilos y eliminación con ConfirmDialog interno.
- Las categorías automáticas están protegidas frente a eliminación porque sus códigos pertenecen al detector.
- La página explica qué características mide la app y cuáles confirma la profesional.
- El editor de estilos ya no requiere asignar tipos de ojo para participar en recomendaciones automáticas.
- Se conservaron las rutas y contratos anteriores que pudieran tener otros consumidores.

Backend relevante

- `app/application/services/tryon_eye_service.py`.
- `app/domain/entities/tryon_style.py` contiene la tabla `tryon_eye_categories`.
- `app/infrastructure/database/migrations/add_tryon_catalog.py` crea y prepara las categorías de forma idempotente.
- `app/application/services/tryon_service.py` añade eye_categories al manifiesto y a su revisión.
- `app/presentation/controllers/tryon_controller.py` contiene endpoints de categorías con permisos catalog:view/catalog:manage.
- `app/presentation/schemas/tryon.py` incorpora EyeAssessment opcional en TryOnSelection.
- `tests/test_tryon_catalog.py` valida contratos, versiones, permisos, borradores, eliminación y ficha profesional.

## Entorno local frente a servidor remoto

Por defecto la app apunta a `http://37.60.247.213/api`.
El administrador usado para las pruebas está en localhost y el backend Docker local escucha en el puerto 8000.
Un grosor creado en la base local no aparecerá en una APK conectada al VPS.

Para usar el backend local desde el teléfono por ADB

```powershell
adb devices -l
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=API_HOST=http://127.0.0.1:8000 --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=API_PREFIX=
```

- El enlace `adb reverse` se pierde al reconectar ADB.
- IP y puerto inalámbricos pueden cambiar. Consultar `adb devices`.
- El contenedor `elashes-backend` monta el código, pero no recarga automáticamente. Reiniciar después de cambios del backend.
- `elashes-postgres` es la base local.
- Conservar la sesión y el Vite del usuario en localhost:5173.
- Los despliegues al VPS son un paso aparte.

Herramientas disponibles

- Flutter en `C:\dev\flutter\bin\flutter.bat`.
- Dart en `C:\dev\flutter\bin\dart.bat`.
- ADB en `C:\Users\usser\AppData\Local\Android\Sdk\platform-tools\adb.exe`.
- Java en `C:\Program Files\Android\Android Studio\jbr`.
- Node/npm en `C:\Program Files\nodejs`.

## Referencias fotográficas del usuario

- Originales e índice en `D:\proyectos\referencias_ojos`.
- 25 retratos, índice `indice.csv` y resumen `resumen_grupos.jpg`.
- Grupos provisionales de origen con 5 redondos, 6 almendrados, 4 alargados, 5 encapotados y 5 monólidos.
- 11 imágenes están marcadas DUDOSO por la IA que buscó las fotos.
- El usuario informó que provienen de Unsplash y entregó las URLs y licencias. Esa comprobación de cada licencia fue informada por el usuario/otra IA.
- Las etiquetas de los grupos son provisionales; no constituyen ground truth revisado por el salón.
- Se detectó un rostro en las 25 fotos mediante el archivo `android/app/src/main/assets/face_landmarker.task`.
- La medición se ejecutó en PC con MediaPipe Python 1.2.2, CPU y modo IMAGE. Android usa MediaPipe 0.10.29. El modelo tiene los mismos pesos empaquetados, pero el runtime, modo, resolución y seguimiento pueden cambiar resultados respecto al teléfono.
- SHA256 del modelo `64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff`.

Hallazgos

- Las referencias de alargados se solapan mucho con las almendradas en ancho/alto.
- `alargados_03.jpg`, marcada segura por la búsqueda, midió cerca de 2.71 y cae en la forma intermedia del criterio actual.
- `almendrados_03.jpg` tiene apertura reducida y midió cerca de 3.94.
- Algunas imágenes marcadas seguras tienen delineado, gesto o postura que deben revisarse.
- Bajar un umbral para acertar una única imagen no valida una clasificación general.
- Encapotado y monólido son atributos de párpado que deben revisarse por separado de la forma.

Herramientas y resultados de revisión

- `tools/eyes/extract_reference_frames.py` extrae landmarks locales compatibles con el mapper Android.
- `offline_analysis/eye_reference_checks/classify_references_test.dart` evalúa los puntos con el analizador real de Flutter.
- `tools/eyes/build_reference_review.py` construye la galería y las notas.
- Galería real en `pruebas/ojos-reales/revision.html`.
- CSV en `pruebas/ojos-reales/indice_revisado.csv`.
- Resumen visual en `pruebas/ojos-reales/contacto_ojos.jpg`.
- Resultados en `pruebas/ojos-reales/resultados.json`.
- La galería carga los originales desde su carpeta y permite revisar forma/párpado por separado y exportar la revisión del salón.
- También existen tres retratos sintéticos anteriores en `pruebas/ojos`, con prompts y galería. Son referencias aproximadas, no etiquetas validadas.
- El entorno Python aislado está en `build/eye_reference_analysis/venv`; las dependencias de análisis no se agregaron a la app.
- El selector de fotografías directamente dentro de la app todavía no está implementado. El análisis directo de estas 25 fotos se hizo con herramientas locales de PC.

## Validaciones recientes

- 31 pruebas Flutter seleccionadas pasaron, incluyendo ficha profesional, objetivos, catálogo dinámico y geometría de pestañas.
- 18 pruebas del backend pasaron después de incorporar EyeAssessment.
- Compilación Vite del administrador completada.
- Pruebas Playwright locales completadas para tarjetas, modo avanzado, creación/eliminación simulada, exportación de revisión y diseño responsive.
- La ficha se revisó visualmente con tipografía legible. Captura en `build/eye_consultation_sheet.png`.
- Flutter analyze mantiene una advertencia anterior de `_openRecommendation` sin uso.
- TypeScript global del administrador tiene errores previos en otros módulos; distinguirlos de los archivos nuevos.

Comando de regresión Flutter

```powershell
C:\dev\flutter\bin\flutter.bat test --no-pub test/eye_consultation_sheet_test.dart test/lash_consultation_test.dart test/eye_auto_recommendations_test.dart test/lash_options_test.dart test/tryon_catalog_test.dart test/cat_eye_recipe_test.dart test/cat_eye_recipe_cache_test.dart test/cat_eye_menu_test.dart test/design_menu_layout_test.dart test/design_thumbnail_image_test.dart
```

Comando de pruebas backend

```powershell
docker exec elashes-backend python -m unittest discover -s tests -p test_tryon_catalog.py -v
```

Al compilar el administrador, elegir un outDir dentro de build del workspace. Su configuración por defecto genera archivos rastreados dentro de `server/public/app`.

## Trabajo pendiente y próximo paso

1. El usuario está probando la clasificación mostrando fotos en el PC a la cámara trasera.
2. Debe usar «Volver a analizar» al cambiar de rostro porque el análisis se bloquea durante la sesión.
3. Pedir sus resultados concretos de la nueva ficha y corregir los defectos observados.
4. Continuar revisando las etiquetas reales antes de calibrar los límites de forma.
5. Si se pide detección automática de párpado/profundidad, requiere una implementación visual real y validación. La versión actual los registra mediante confirmación profesional.
6. El usuario quiere ampliar la cobertura para un salón, acepta precisión orientativa y exige etiquetas limpias para la clienta. Conservar la separación entre resultados medidos y confirmados en el código y los datos.
7. Para cargar fotografías en el teléfono, implementar explícitamente un modo de imagen usando MediaPipe IMAGE y el mismo analizador. Evitar reutilizar filtros temporales del seguimiento entre fotografías independientes.

## Archivos ajenos a estas mejoras

- `android/build/reports/problems/problems-report.html` es un reporte generado y ya estaba modificado.
- `offline_analysis/sync_presenter_checks/` contiene experimentos anteriores que referencian archivos nativos inexistentes. Revisarlos como trabajo ajeno antes de incluirlos en cualquier commit.
- Este documento de continuidad es nuevo y queda como archivo local.

