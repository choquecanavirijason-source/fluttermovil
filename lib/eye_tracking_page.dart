import 'dart:async';
import 'dart:io';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/network/dio_client.dart';
import 'core/recommendation/eye_shape_analyzer.dart';
import 'core/theme/app_colors.dart';
import 'features/catalogo/domain/entities/catalog_item.dart';
import 'features/catalogo/presentation/providers/catalogo_provider.dart';
import 'features/clientes/domain/entities/client.dart';
import 'features/clientes/presentation/providers/clientes_provider.dart';
import 'features/tracking/data/tracking_repository_impl.dart';
import 'eye_tracking_alignment.dart';
import 'eye_tracking_customization_options.dart';
import 'lid_landmark_debug_painter.dart';
import 'eye_tracking_model.dart';
import 'eye_tracking_photo_pipeline.dart';
import 'native_eye_tracking_service.dart';
import 'screens/widgets/bottom_carousel.dart';
import 'screens/widgets/client_picker_sheet.dart';
import 'screens/widgets/eye_position_guide_painter.dart';
import 'screens/widgets/eye_tracking_bottom_actions.dart';
import 'screens/widgets/eye_tracking_design_menu_bar.dart';
import 'screens/widgets/eye_tracking_filter_row.dart';
import 'screens/widgets/eye_tracking_lash_modal.dart';
import 'screens/widgets/eye_tracking_overlay.dart';
import 'screens/widgets/eye_tracking_work_assistant_button.dart';
import 'screens/widgets/eye_type_picker_sheet.dart';
import 'screens/widgets/hybrid_camera_preview.dart';
import 'screens/widgets/save_options_sheet.dart';
import 'recommendation_args.dart';
import 'work_assistant_args.dart';

/// Diseño de pestañas empaquetado en la app (bundle), con modelos .glb
/// reales por ojo (no espejados como los que suben desde el admin, que solo
/// guardan un archivo). Viven en `assets/modelos/` — ver pubspec.yaml.
class _LocalLashPreset {
  final String name;
  final String thumbnailAsset;
  final String leftModelAsset;
  final String rightModelAsset;

  const _LocalLashPreset({
    required this.name,
    required this.thumbnailAsset,
    required this.leftModelAsset,
    required this.rightModelAsset,
  });
}

/// Deriva el `styleId` que espera `LashStyleConfig.forStyleId` (Kotlin) a
/// partir del nombre visible del diseño/preset — "Cat Eye" -> "cateye". Un
/// id que Kotlin no tenga registrado simplemente cae a un estilo neutro
/// (`LashStyleConfig.DEFAULT`, ver el comentario en `setLashStyle`), así
/// que esto es seguro incluso para diseños del backend cuyo nombre no
/// coincida con ninguno de los presets ajustados a mano.
String _lashStyleIdFor(String displayName) =>
    displayName.toLowerCase().replaceAll(RegExp(r'\s+'), '');

const _localLashPresets = [
  _LocalLashPreset(
    name: 'Cat Eye',
    thumbnailAsset: 'assets/p1.png',
    leftModelAsset: defaultLeftEyeModelAsset,
    rightModelAsset: defaultRightEyeModelAsset,
  ),
  _LocalLashPreset(
    name: 'Wispy',
    thumbnailAsset: 'assets/p2.png',
    leftModelAsset: 'assets/modelos/wispy/wispy_left.glb',
    rightModelAsset: 'assets/modelos/wispy/wispy_right.glb',
  ),
  _LocalLashPreset(
    name: 'Cat Classic',
    thumbnailAsset: 'assets/p3.png',
    leftModelAsset: 'assets/modelos/catclassic/cat_classic_left.glb',
    rightModelAsset: 'assets/modelos/catclassic/cat_classic_right.glb',
  ),
  _LocalLashPreset(
    name: 'Foxy Eye',
    thumbnailAsset: 'assets/p4.png',
    leftModelAsset: 'assets/modelos/foxyeyex/foxy_intense_left.glb',
    rightModelAsset: 'assets/modelos/foxyeyex/foxy_intense_right.glb',
  ),
  _LocalLashPreset(
    name: 'Natural',
    thumbnailAsset: 'assets/p5.png',
    leftModelAsset: 'assets/modelos/natural/natural_left.glb',
    rightModelAsset: 'assets/modelos/natural/natural_right.glb',
  ),
];

class EyeTrackingPage extends ConsumerStatefulWidget {
  const EyeTrackingPage({super.key});

  @override
  ConsumerState<EyeTrackingPage> createState() => _EyeTrackingPageState();
}

class _EyeTrackingPageState extends ConsumerState<EyeTrackingPage>
    with WidgetsBindingObserver {
  final NativeEyeTrackingService _service = NativeEyeTrackingService();
  final GlobalKey _previewCaptureKey = GlobalKey();
  late final EyeTrackingPhotoPipeline _photoPipeline;

  StreamSubscription<TrackingFrame>? _sub;
  TrackingFrame? _frame;

  /// Canal de repintado de los overlays de landmarks (puntos del párpado y
  /// mapping). Se actualiza en CADA frame de tracking y los painters lo
  /// reciben como `repaint:`, así que se redibujan a la cadencia real de
  /// MediaPipe sin pasar por el `setState` de más abajo — que sigue
  /// limitado a 150 ms porque sí reconstruye la pantalla entera.
  final ValueNotifier<TrackingFrame?> _frameNotifier =
      ValueNotifier<TrackingFrame?>(null);

  /// Último frame con rostro y los dos ojos, y cuándo llegó. Fuente de
  /// [_freezeMappingFrame].
  TrackingFrame? _lastMappableFrame;
  DateTime? _lastMappableAt;

  /// Cuánto puede tener el último frame válido para usarse en la captura.
  /// La operaria acaba de ver el botón habilitado (que exige rostro y ojos
  /// cerrados), así que un frame de hasta ~1,5 s atrás sigue siendo la
  /// misma pose.
  static const Duration _mappableFrameMaxAge = Duration(milliseconds: 1500);

  String _status = 'Inicializando...';
  DateTime? _lastFrameUiUpdate;

  bool _workAssistantOpening = false;
  bool _openingRecommendation = false;

  /// Overlay de diagnóstico de landmarks del párpado. `false` = la pantalla
  /// muestra solo la cámara y las pestañas 3D, sin nada dibujado encima
  /// — el estado en que hay que evaluar el render. Ponerlo en `true` para
  /// volver a ver dónde cree el motor que está la línea de pestañas (es lo
  /// único que hace falta cambiar; el painter sigue enchufado al
  /// `_frameNotifier` y se repinta a la cadencia real del tracking).
  static const bool _showLidLandmarkDebug = false;

  /// true mientras alguna de las hojas del flujo "Guardar diseño" (opciones,
  /// selector de cliente) está abierta. Solo se usa para que
  /// [_setHidingCameraForSaveSheet] sea idempotente (no repetir la llamada
  /// nativa si ya está en el estado pedido) — no maneja ningún widget
  /// directamente: la cámara en vivo queda visible todo el tiempo, lo único
  /// que se oculta es el modelo 3D de la pestaña (ver más abajo).
  bool _hidingCameraForSaveSheet = false;

  /// Descarga (o restaura) el modelo 3D de pestaña en el SceneView nativo
  /// mientras dura el flujo de guardado — la cámara en vivo sigue
  /// mostrándose normal, solo desaparece la pestaña superpuesta, para no
  /// distraer/tapar mientras se busca una clienta en la hoja de abajo.
  /// Idempotente: si ya está en el estado pedido, no hace nada.
  Future<void> _setHidingCameraForSaveSheet(bool hide) async {
    if (!mounted || _hidingCameraForSaveSheet == hide) return;
    setState(() => _hidingCameraForSaveSheet = hide);
    try {
      if (hide) {
        await _service.loadEyeModels(leftPath: null, rightPath: null);
      } else {
        await _service.loadEyeModels(
          leftPath: _leftModelPath,
          rightPath: _rightModelPath,
        );
      }
    } catch (e) {
      debugPrint('[EyeTracking] no se pudo ${hide ? 'ocultar' : 'restaurar'} '
          'el modelo para el flujo de guardado: $e');
      // El scrim negro sigue tapando la cámara visualmente aunque esto
      // falle, así que no hace falta propagar el error a la usuaria.
    }
  }

  /// true mientras dura el asistente de encuadre (guía del botón robot):
  /// el modelo 3D de pestaña se oculta para no tapar el párpado justo
  /// cuando hace falta ver si el ojo ya está cerrado.
  bool _hidingLashesForAlignmentGuide = false;

  /// Igual mecanismo que [_setHidingCameraForSaveSheet] pero para el flujo
  /// de encuadre del asistente IA. Idempotente: si ya está en el estado
  /// pedido, no hace nada.
  Future<void> _setHidingLashesForAlignmentGuide(bool hide) async {
    if (!mounted || _hidingLashesForAlignmentGuide == hide) return;
    _hidingLashesForAlignmentGuide = hide;
    try {
      if (hide) {
        await _service.loadEyeModels(leftPath: null, rightPath: null);
      } else {
        await _service.loadEyeModels(
          leftPath: _leftModelPath,
          rightPath: _rightModelPath,
        );
      }
    } catch (e) {
      debugPrint(
        '[EyeTracking] no se pudo ${hide ? 'ocultar' : 'restaurar'} '
        'el modelo 3D para el asistente de encuadre: $e',
      );
    }
  }

  int _selectedFilter = 0;
  int _selectedLashIndex = 0;
  int _selectedDesignIndex = 2;
  int _selectedTechIndex = 0;
  int _selectedEffectIndex = 0;
  int _selectedThicknessIndex = 0;
  bool _showTransparentMenu = true;

  /// Categoría activa del menú inferior: 'design', 'tech', 'effect', 'thickness', o null.
  String? _activeCategory;
  bool _showLashModal = false;

  /// Fuerza recreación del [AndroidView] al volver de otra pantalla que usa la cámara.
  int _previewSession = 0;

  /// Rutas locales (archivo) de los .glb de pestañas, resueltas una única vez
  /// por ciclo de vida de este State (ver [_resolveEyeModelPaths]). Viajan
  /// como `creationParams` del PlatformView (ver [HybridCameraPreview]) para
  /// que Kotlin cargue el modelo de forma síncrona en la misma llamada nativa
  /// que crea el SceneView — nunca por un MethodChannel disparado con delays.
  String? _leftModelPath;
  String? _rightModelPath;

  /// Espejo local de la cámara activa en el tracking — la fuente de verdad
  /// es Kotlin (`CameraXManager.lensFacing`), que sobrevive a la recreación
  /// de esta pantalla y también lo cambia el botón del asistente de trabajo.
  /// Por eso se CONSULTA (ver [_syncCameraFacing]) en vez de llevar una
  /// copia propia: alternarlo a ciegas se desincronizaba y la foto final
  /// salía con la cámara equivocada (la operaria apunta a la clienta, no es
  /// una selfie — ver [_finishWorkAssistantOpen]).
  bool _usingFrontCamera = true;

  Future<void> _syncCameraFacing() async {
    final isFront = await _service.isUsingFrontCamera();
    if (!mounted || isFront == null || isFront == _usingFrontCamera) return;
    setState(() => _usingFrontCamera = isFront);
  }

  Future<void> _onSwitchCamera() async {
    final isFront = await _service.switchCamera();
    if (!mounted || isFront == null) return;
    setState(() => _usingFrontCamera = isFront);
  }

  CatalogItem? _selectedEyeType;
  List<CatalogItem>? _eyeTypes;

  /// true una vez que el usuario elige el tipo de ojo manualmente desde la
  /// hoja de selección; a partir de ahí deja de sobreescribirse con el
  /// resultado del escaneo automático.
  bool _eyeTypeSetManually = false;

  /// true mientras se muestra la guía de alineación (esperando que el usuario
  /// ubique sus ojos en el marco antes de capturar).
  bool _alignmentGuideActive = false;

  /// true cuando se cumplen LAS DOS condiciones (rostro encuadrado + ojos
  /// cerrados) — dispara la captura tras `_alignmentHoldDuration`.
  bool _eyesAligned = false;

  /// true cuando el óvalo de `faceContour` está centrado y del tamaño
  /// esperado dentro de la guía fija (independiente de si los ojos ya están
  /// cerrados).
  bool _faceFramed = false;

  /// true cuando ambos ojos están cerrados (necesario para mapear la línea
  /// de pestañas — con el ojo abierto el párpado tapa la base real).
  bool _eyesClosedOk = false;

  /// true desde el instante en que se cierra la guía de alineación hasta que
  /// termina TODO el pipeline de captura (restaurar pestaña 3D, capturar
  /// overlay, detener tracking, abrir cámara nueva y tomar la foto real —
  /// 1-2s en total). Antes de esto la pantalla quedaba "normal" en ese
  /// tramo sin ningún aviso, así que quien prueba sola sin nadie que le
  /// sostenga el gesto abría los ojos pensando que ya había terminado,
  /// justo antes de que la cámara real disparase. Ver overlay condicionado
  /// a esta bandera en el `build`.
  bool _capturingPhoto = false;

  /// Diseños del catálogo mostrados actualmente en el carrusel inferior
  /// ("Compatible" = filtrados en vivo por forma de ojo, "Explorar" = todo
  /// el catálogo). Se actualiza en cada build (ver [build]) y lo usa
  /// [_onLashSelect] para saber a qué diseño corresponde el índice tocado.
  List<CatalogItem> _currentCarouselDesigns = [];

  bool _switchingDesignModel = false;

  Future<void> _switchDesignModel(CatalogItem design) async {
    final url = design.model3dAbsoluteUrl;
    if (url == null || _switchingDesignModel) return;
    setState(() => _switchingDesignModel = true);
    try {
      final dio = ref.read(dioProvider);
      // La clave de caché es el nombre de archivo de la URL (backend genera
      // uno nuevo al azar cada vez que se sube un modelo), no el id del
      // diseño: si se cacheara por id, reemplazar el .glb desde el admin
      // nunca invalidaría la copia local vieja.
      final cacheKey = Uri.parse(url).pathSegments.isNotEmpty
          ? Uri.parse(url).pathSegments.last
          : design.id.toString();
      final path = await downloadEyeModelToFile(dio, url, cacheKey);
      if (!mounted) return;
      // El backend solo guarda un .glb por diseño (no hay modelo separado
      // por ojo izq/der como en el set por defecto cateyeleft/cateyeright),
      // así que se carga el mismo archivo en ambos lados.
      _leftModelPath = path;
      _rightModelPath = path;
      // A diferencia de _rebindPreview (recrea el AndroidView completo —
      // SceneView + motor Filament nuevos, dejando el anterior sin liberar
      // del todo: detachSceneView solo destruye los nodos del modelo, no el
      // SceneView/Engine en sí), esto actualiza los modelos sobre el mismo
      // SceneView que ya está vivo. Usar _rebindPreview aquí (como se hacía
      // antes) filtraba un motor gráfico por cada diseño tocado — con el
      // tiempo/varios cambios de diseño terminaba tronando la app.
      await _service.loadEyeModels(leftPath: path, rightPath: path);
      final styleId = _lashStyleIdFor(design.name);
      await _service.setLashStyle(styleId);
    } catch (e) {
      debugPrint('No se pudo cargar el modelo del diseño ${design.id}: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cargar el diseño "${design.name}"')),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingDesignModel = false);
    }
  }

  /// Igual que [_switchDesignModel] pero para un diseño empaquetado en la
  /// app (ver [_localLashPresets]): cada lado usa su propio asset real, sin
  /// necesidad de descargar nada.
  Future<void> _switchLocalPreset(_LocalLashPreset preset) async {
    if (_switchingDesignModel) return;
    setState(() => _switchingDesignModel = true);
    try {
      final leftPath = await extractEyeModelAssetToFile(preset.leftModelAsset);
      final rightPath = await extractEyeModelAssetToFile(preset.rightModelAsset);
      if (!mounted) return;
      _leftModelPath = leftPath;
      _rightModelPath = rightPath;
      await _service.loadEyeModels(leftPath: leftPath, rightPath: rightPath);
      final styleId = _lashStyleIdFor(preset.name);
      await _service.setLashStyle(styleId);
    } catch (e) {
      debugPrint('No se pudo cargar el preset local ${preset.name}: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cargar el diseño "${preset.name}"')),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingDesignModel = false);
    }
  }

  /// Resuelve, una única vez, las rutas de archivo de los .glb de pestañas
  /// (cateyeleft/cateyeright). No dispara ninguna carga en Kotlin: las rutas
  /// se pasan como `creationParams` al crear el PlatformView, así que cada
  /// vez que Flutter recrea el AndroidView (primera entrada, o cualquier
  /// re-entrada a esta pantalla) el nativo carga el modelo de forma
  /// determinista, sin depender de un segundo viaje Dart→Kotlin con timers.
  Future<void> _resolveEyeModelPaths() async {
    if (!Platform.isAndroid) return;
    try {
      final leftPath = await extractEyeModelAssetToFile(
        defaultLeftEyeModelAsset,
      );
      final rightPath = await extractEyeModelAssetToFile(
        defaultRightEyeModelAsset,
      );
      if (!mounted) return;
      setState(() {
        _leftModelPath = leftPath;
        _rightModelPath = rightPath;
      });
    } catch (e) {
      debugPrint('No se pudieron resolver los .glb de pestañas: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _photoPipeline = EyeTrackingPhotoPipeline(
      previewCaptureKey: _previewCaptureKey,
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_resolveEyeModelPaths());
    _start();

    // Pre-carga tipos de ojo en segundo plano
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final items = await ref.read(
          catalogListProvider(CatalogKind.eyeType).future,
        );
        if (mounted) setState(() => _eyeTypes = items);
      } catch (_) {}
    });

    // Fuerza recarga del catálogo de "Diseños" al entrar: autoDispose
    // debería refrescarlo solo, pero invalidar explícitamente garantiza que
    // un diseño/modelo nuevo creado en el admin aparezca sin depender de esa
    // limpieza implícita. Se hace en addPostFrameCallback (no directo en
    // initState) porque ref.invalidate toca el árbol de widgets y eso
    // requiere que el build inicial ya haya terminado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(designCatalogListProvider);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _sub?.cancel();
      _sub = null;
      _service.stopTracking();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_restartCameraFromLifecycle());
    }
  }

  Future<void> _restartCameraFromLifecycle() => _rebindPreview();

  /// Fuerza recreación del `AndroidView` (nueva `key`) y re-suscribe el
  /// stream de tracking. Se usa tanto al volver de background (lifecycle)
  /// como al cambiar de diseño desde el carrusel: en ambos casos el nuevo
  /// `.glb` ya está resuelto en `_leftModelPath`/`_rightModelPath` *antes*
  /// de llamar esto, y viaja como `creationParams` al crearse la vista.
  /// Handler compartido del stream de tracking (usado por [_start] y
  /// [_rebindPreview]). El overlay 3D de pestañas se dibuja nativamente
  /// (Filament/Choreographer, fuera de Flutter) y no depende de este
  /// `setState` — pero sin throttle, cada frame de MediaPipe (hasta ~30/s)
  /// disparaba un rebuild completo de esta pantalla entera (carrusel,
  /// filtros, barras...), lo que se sentía como "cámara lenta" aunque el
  /// preview nativo en sí no lo fuera. `_frame` se actualiza siempre (lo
  /// necesitan `_evaluateAlignment`/`_detectEyeTypeFromFrame` con el dato
  /// más fresco posible); solo el `setState` que dispara el rebuild se
  /// limita, salvo que el estado de detección de rostro recién cambie.
  void _handleTrackingFrame(TrackingFrame frame) {
    if (!mounted) return;
    // El badge "Rostro detectado"/"Sin rostro" se quitó: era redundante con
    // la guía de encuadre (ver `EyePositionGuidePainter`) y quedaba
    // desactualizado/engañoso fuera del flujo del asistente. `_status` ahora
    // solo lo tocan los mensajes de ciclo de vida (permiso, error, "iniciando
    // cámara…") — la llegada del primer frame oculta el badge (ver
    // `_frame == null` en el `build`).
    final isFirstFrame = _frame == null;
    _frame = frame;
    // Repintado de los overlays: independiente del throttle de `setState`
    // (ver [_frameNotifier]) — aquí no hay límite, cada frame que llega se
    // dibuja, que es lo que hace que los puntos sigan la cabeza sin saltos.
    _frameNotifier.value = frame;
    if (frame.faceDetected &&
        frame.leftEye.length >= 4 &&
        frame.rightEye.length >= 4) {
      _lastMappableFrame = frame;
      _lastMappableAt = DateTime.now();
    }
    if (_alignmentGuideActive) _evaluateAlignment(frame);
    _detectEyeTypeFromFrame(frame);

    final now = DateTime.now();
    final last = _lastFrameUiUpdate;
    if (!isFirstFrame &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 150)) {
      return;
    }
    _lastFrameUiUpdate = now;
    setState(() {});
  }

  Future<void> _rebindPreview() async {
    if (!mounted) return;
    setState(() => _previewSession++);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _sub?.cancel();
    _sub = _service.trackingStream.listen(
      _handleTrackingFrame,
      onError: (Object e, StackTrace st) {
        if (!mounted) return;
        setState(() => _status = 'Error: $e');
      },
    );
    await _service.startTracking();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await _service.refreshPreviewBind();
  }

  Future<void> _start() async {
    final camera = await Permission.camera.request();
    if (!mounted) return;
    if (!camera.isGranted) {
      setState(() => _status = 'Permiso de cámara denegado');
      return;
    }

    setState(() => _status = 'Iniciando cámara…');

    _sub = _service.trackingStream.listen(
      _handleTrackingFrame,
      onError: (Object e, StackTrace st) {
        if (!mounted) return;
        setState(() => _status = 'Error: $e');
      },
    );

    await _service.startTracking();
    if (!mounted) return;
    setState(() {
      if (_status == 'Iniciando cámara…') {
        _status = 'Esperando detección…';
      }
    });

    // La carga del GLB ya no depende de un retry-loop temporizado: viaja
    // como creationParams del PlatformView (ver HybridCameraPreview), así
    // que Kotlin la ejecuta de forma síncrona en el mismo create() que
    // adjunta el SceneView nuevo.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    unawaited(_service.setInvertedFaceMode(false));
    _service.stopTracking();
    _frameNotifier.dispose();
    ref.read(sessionClientProvider.notifier).state = null;
    super.dispose();
  }

  void _goHome(BuildContext context) {
    if (!context.mounted) return;
    context.go('/');
  }

  void _onFilterSelect(int index) {
    setState(() {
      _selectedFilter = index;
      _showTransparentMenu = true;
      _activeCategory = null;
      // La lista de diseños del nuevo filtro recién se resuelve en el
      // próximo build (viene de un provider); reiniciar el índice evita
      // referenciar una posición fuera de rango del filtro anterior.
      _selectedLashIndex = 0;
    });
  }

  void _onCategoryTap(String category) {
    setState(() {
      _activeCategory = category;
      _showTransparentMenu = false;
    });
  }

  List<String> get _activeCategoryImages =>
      LashCustomizationCatalog.imagesFor(_activeCategory);

  List<String> get _activeCategoryOptions =>
      LashCustomizationCatalog.optionsFor(_activeCategory);

  int get _activeCategorySelectedIndex {
    switch (_activeCategory) {
      case 'design':
        return _selectedDesignIndex;
      case 'tech':
        return _selectedTechIndex;
      case 'effect':
        return _selectedEffectIndex;
      case 'thickness':
        return _selectedThicknessIndex;
      default:
        return 0;
    }
  }

  void _onActiveCategorySelect(int index) {
    setState(() {
      switch (_activeCategory) {
        case 'design':
          _selectedDesignIndex = index;
          break;
        case 'tech':
          _selectedTechIndex = index;
          break;
        case 'effect':
          _selectedEffectIndex = index;
          break;
        case 'thickness':
          _selectedThicknessIndex = index;
          break;
      }
    });
  }

  Future<void> _resumeEyePreviewAfterAssistant() async {
    // Espera extra para que el plugin `camera` libere el hardware completamente.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    // Descarta los landmarks del último frame para que el diagnóstico no
    // quede congelado sobre el preview hasta la siguiente detección.
    _frameNotifier.value = null;
    _lastMappableFrame = null;
    _lastMappableAt = null;
    setState(() {
      _previewSession++;
      _frame = null;
      _eyesAligned = false;
      _faceFramed = false;
      _eyesClosedOk = false;
    });

    // Tiempo para que el nuevo AndroidView llame a attachPreview().
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    // La suscripción al stream puede haberse cortado mientras el asistente
    // estaba encima (p. ej. el ciclo de vida pasó por `paused` y puso `_sub`
    // en null). Se re-suscribe siempre: el stream es broadcast y compartido,
    // así que cancelar y volver a escuchar es seguro.
    await _sub?.cancel();
    _sub = _service.trackingStream.listen(
      _handleTrackingFrame,
      onError: (Object e, StackTrace st) {
        if (!mounted) return;
        setState(() => _status = 'Error: $e');
      },
    );
    await _service.startTracking();

    // refreshPreviewBind() es no-op si previewView==null.
    // Múltiples intentos cubren la variación de tiempo del AndroidView.
    for (final ms in [700, 600, 500, 400]) {
      await Future<void>.delayed(Duration(milliseconds: ms));
      if (!mounted) return;
      await _service.refreshPreviewBind();
    }
    // El nuevo AndroidView trae un SceneView nuevo (el anterior se destruyó),
    // pero ya no hace falta recargar el GLB desde aquí: se creó con la misma
    // key `eye_preview_$_previewSession` y las creationParams
    // (_leftModelPath/_rightModelPath) siguen resueltas en el State — Kotlin
    // ya cargó el modelo de forma síncrona dentro de su propio create().
    if (mounted) setState(() {});
  }

  Future<void> _finishWorkAssistantOpen() async {
    if (_workAssistantOpening) return;
    _workAssistantOpening = true;
    try {
      final mappingFrame = _freezeMappingFrame();
      final overlayBytes = await _photoPipeline.captureOverlay(context);
      final previewSize = _photoPipeline.previewSize;
      final assistantFrame = overlayBytes == null || previewSize == null
          ? null
          : EyeTrackingPhotoPipeline.frameForCapturedBand(
              mappingFrame,
              previewSize,
            );

      // Qué cámara está usando el tracking AHORA, preguntándoselo a Kotlin
      // (ver [_syncCameraFacing]). Se consulta acá, sobre el final, para que
      // la foto salga con la misma cámara aunque el estado se haya cambiado
      // desde otra pantalla o esta se haya recreado en el medio.
      await _syncCameraFacing();
      if (!mounted) return;

      // 3. Foto por la MISMA sesión de cámara, sin detener el tracking: sale
      // a los ~200 ms del overlay en vez de 1-2 s, que es lo que hacía que
      // con el pulso de la mano el mapeo quedara corrido respecto del ojo.
      final nativeShot = await _service.takePhoto();
      if (!mounted) return;

      Uint8List? finalPhoto;
      Future<Uint8List?>? pendingPhoto;
      if (nativeShot != null) {
        // Se navega YA y la composición (decodificar, recortar, componer,
        // codificar: la parte más lenta) sigue en un isolate; el asistente
        // muestra un cargando en el panel hasta que llega.
        //
        // Tampoco se detiene el tracking acá: el asistente usa la MISMA
        // cámara y MediaPipe, y detenerlo para que él lo vuelva a arrancar
        // costaba el desenlace diferido del stop más recargar el modelo en
        // frío (~1 s). Durante la foto el análisis ya quedó pausado en
        // nativo (`CameraXManager.analysisPausedForCapture`).
        final mirror = _usingFrontCamera;
        pendingPhoto = EyeTrackingPhotoPipeline.compositeAndCropInBackground(
          nativeShot,
          overlayBytes,
          mirror: mirror,
        ).then<Uint8List?>(
          (bytes) => bytes,
          onError: (Object e) {
            debugPrint('[EyeTracking] compositeAndCrop falló: $e');
            return nativeShot;
          },
        );
      } else {
        // Respaldo: si el caso de uso de foto no estaba disponible, se cae
        // al camino viejo (segunda sesión de cámara), que funciona igual
        // pero con el desfase de siempre.
        debugPrint('[EyeTracking] takePhoto nativo no disponible — usando el '
            'camino de respaldo con el plugin camera');
        await _service.stopTracking();
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (!mounted) return;
        finalPhoto = await _photoPipeline.captureAndComposite(
          context,
          overlayBytes,
          preferFrontCamera: _usingFrontCamera,
        );
      }
      if (!mounted) return;
      // Foto real ya tomada — ya no importa si abre los ojos, apaga el
      // aviso acá y no en el `finally` (que sigue corriendo durante la
      // navegación a `/work-assistant`).
      setState(() => _capturingPhoto = false);

      await context.push(
        '/work-assistant',
        extra: WorkAssistantArgs(
          panelPngBytes: finalPhoto,
          panelBytesFuture: pendingPhoto,
          mappingFrame: assistantFrame,
          mappingStyleId: 'cateye',
          cropOverlayBytes: overlayBytes,
          mappingPreviewSize: previewSize,
          mirrorPhoto: _usingFrontCamera,
        ),
      );
      if (!mounted) return;

      await _resumeEyePreviewAfterAssistant();
    } finally {
      // Red de seguridad: si algo falló ANTES del paso 4 (foto real), el
      // aviso quedaría colgado en pantalla para siempre sin esto.
      _capturingPhoto = false;
      _workAssistantOpening = false;
      // Recién acá vuelve la pestaña virtual después de la captura.
      unawaited(_setHidingLashesForAlignmentGuide(false));
      // Y se apaga el modo clienta acostada, que fuera del asistente
      // descoloca el modelo 3D.
      unawaited(_service.setInvertedFaceMode(false));
      if (mounted) setState(() {});
    }
  }

  /// Abre el probador con IA con la foto capturada sin la grilla del
  /// asistente, junto con el análisis de forma de ojo.
  Future<void> _openRecommendation() async {
    if (_openingRecommendation || _workAssistantOpening) return;
    _openingRecommendation = true;
    try {
      final overlayBytes = await _photoPipeline.captureOverlay(context);
      if (!mounted) return;
      final analysis = EyeShapeAnalyzer.analyze(_frame);

      await _syncCameraFacing();
      if (!mounted) return;

      await _service.stopTracking();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;

      final finalPhoto = await _photoPipeline.captureAndComposite(
        context,
        overlayBytes,
        preferFrontCamera: _usingFrontCamera,
      );
      if (!mounted) return;

      await context.push(
        '/recomendacion',
        extra: RecommendationArgs(
          analysis: analysis,
          photoPngBytes: finalPhoto,
        ),
      );
      if (!mounted) return;

      await _resumeEyePreviewAfterAssistant();
    } finally {
      _openingRecommendation = false;
      if (mounted) setState(() {});
    }
  }

  /// Enciende o apaga el asistente de encuadre (botón del robot).
  ///
  /// NO dispara la captura solo: el óvalo queda en pantalla como referencia
  /// (el mapeo numérico se pinta recién al capturar) y la foto la saca la
  /// operaria con el botón de captura (ver
  /// [_beginWorkAssistantFlow]). Auto-disparar obligaba a sostener los ojos
  /// cerrados durante todo el procesamiento posterior, y además la foto
  /// salía de un instante distinto al que se estaba viendo.
  void _toggleAlignmentGuide() {
    if (_workAssistantOpening) return;
    final activating = !_alignmentGuideActive;
    setState(() {
      _alignmentGuideActive = activating;
      _eyesAligned = false;
      _faceFramed = false;
      _eyesClosedOk = false;
    });
    // La pestaña virtual taparía el borde natural durante el encuadre; el
    // mapeo numérico queda reservado para la captura.
    unawaited(_setHidingLashesForAlignmentGuide(activating));
    // Clienta DE FRENTE: el análisis no se rota (el modo acostada, con el
    // análisis girado 180°, quedó fuera por ahora — ver
    // `CameraXManager.analysisRotated180`). Solo se enlaza la foto rápida
    // por la misma sesión mientras la guía está abierta.
    unawaited(_service.setInvertedFaceMode(false, photoMode: activating));
  }

  /// Voltear cámara desde la guía: cambia frontal ↔ trasera según hacia
  /// dónde está la persona (selfie o la operaria filmando a la clienta). Se
  /// resetea el encuadre porque el rostro cambia de lugar en el cuadro. La
  /// foto rápida sigue enlazada: el rebind nativo conserva `photoMode`, y el
  /// espejado de la foto sigue a [_usingFrontCamera].
  Future<void> _switchCameraFromGuide() async {
    setState(() {
      _eyesAligned = false;
      _faceFramed = false;
      _eyesClosedOk = false;
    });
    await _onSwitchCamera();
  }

  /// Selecciona el frame que recibe el asistente, usando el último frame
  /// válido reciente si el actual perdió el rostro.
  TrackingFrame? _freezeMappingFrame() {
    final at = _lastMappableAt;
    final recent = at != null &&
        DateTime.now().difference(at) <= _mappableFrameMaxAge;
    return recent ? _lastMappableFrame : _frame;
  }

  void _evaluateAlignment(TrackingFrame frame) {
    if (!mounted || !_alignmentGuideActive) return;
    final size = MediaQuery.sizeOf(context);
    final status = EyeAlignmentGuide.evaluate(frame, size);

    if (_eyesAligned != status.ready ||
        _faceFramed != status.faceFramed ||
        _eyesClosedOk != status.eyesClosed) {
      setState(() {
        _eyesAligned = status.ready;
        _faceFramed = status.faceFramed;
        _eyesClosedOk = status.eyesClosed;
      });
    }
  }

  /// Detecta la forma del ojo en vivo con [EyeShapeAnalyzer] y actualiza el
  /// pill "tipo de ojo" con el item del catálogo correspondiente, mientras
  /// el usuario no haya elegido uno manualmente.
  void _detectEyeTypeFromFrame(TrackingFrame frame) {
    if (_eyeTypeSetManually) return;
    final types = _eyeTypes;
    if (types == null || types.isEmpty) return;

    final analysis = EyeShapeAnalyzer.analyze(frame);
    if (!analysis.reliable) return;

    final catalogName = analysis.shape.catalogName;
    CatalogItem? match;
    for (final item in types) {
      if (item.name.trim().toLowerCase() == catalogName.toLowerCase()) {
        match = item;
        break;
      }
    }
    if (match == null || match.id == _selectedEyeType?.id) return;
    setState(() => _selectedEyeType = match);
  }

  /// Dispara la captura. Lo llama el botón de captura de la guía — no se
  /// activa solo (ver [_toggleAlignmentGuide]).
  void _beginWorkAssistantFlow() {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El asistente solo está disponible en Android.'),
        ),
      );
      return;
    }
    if (_workAssistantOpening) return;
    // La línea de pestañas solo se mapea bien con los ojos cerrados: con el
    // ojo abierto el párpado tapa la base real.
    if (!_eyesClosedOk) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Cierra los ojos para tomar la foto'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    // Cierra la guía y muestra el aviso de "tomando la foto" mientras corre
    // el pipeline (ver [_capturingPhoto]).
    setState(() {
      _alignmentGuideActive = false;
      _capturingPhoto = true;
    });
    unawaited(_finishWorkAssistantOpen());
  }

  /// Botón "Voltear cámara" de la guía — ver [_switchCameraFromGuide].
  Widget _flipCameraButton() {
    return GestureDetector(
      onTap: () => unawaited(_switchCameraFromGuide()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white24),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flip_camera_android, color: Colors.white, size: 16),
            SizedBox(width: 6),
            Text(
              'Voltear cámara',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEyeTypeSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EyeTypePickerSheet(
        selected: _selectedEyeType,
        preloadedItems: _eyeTypes,
        onSelect: (item) {
          setState(() {
            _selectedEyeType = item;
            _eyeTypeSetManually = true;
          });
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _confirmSaveForClient(Client client) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar diseño'),
        content: Text('¿Guardar para ${client.displayName}?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.actionGreen,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _saveToClient(client);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showSaveDesignSheet() {
    // Si se pasa a _showClientPickerSheet, NO hay que restaurar la cámara
    // acá — esa función se encarga de mantenerla oculta. Sin esta bandera,
    // el whenComplete de ESTA hoja (que se resuelve después del pop, ya con
    // la hoja siguiente abierta) pisaba el estado y volvía a mostrar la
    // pestaña de fondo mientras se buscaba la clienta.
    var proceedingToPicker = false;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SaveOptionsSheet(
        onListaTap: () {
          proceedingToPicker = true;
          Navigator.of(context).pop();
          _showClientPickerSheet();
        },
      ),
    ).whenComplete(() {
      if (!proceedingToPicker) unawaited(_setHidingCameraForSaveSheet(false));
    });
  }

  void _showClientPickerSheet() {
    unawaited(_setHidingCameraForSaveSheet(true));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ClientPickerSheet(
        onSelect: (client) {
          Navigator.of(context).pop();
          _saveToClient(client);
        },
      ),
    ).whenComplete(() {
      unawaited(_setHidingCameraForSaveSheet(false));
    });
  }

  Future<void> _saveToClient(Client client) async {
    final notes = [
      'Diseño: ${LashCustomizationCatalog.designOptionAt(_selectedDesignIndex)}',
      'Tecnología: ${LashCustomizationCatalog.techOptionAt(_selectedTechIndex)}',
      'Efecto: ${LashCustomizationCatalog.effectOptionAt(_selectedEffectIndex)}',
      'Grosor: ${LashCustomizationCatalog.thicknessOptionAt(_selectedThicknessIndex)}',
    ].join(' | ');

    try {
      await ref
          .read(trackingRepositoryProvider)
          .create(
            clientId: client.id,
            eyeTypeId: _selectedEyeType?.id,
            designNotes: notes,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Diseño guardado para ${client.displayName}'),
          backgroundColor: AppColors.actionGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onLashSelect(int index) {
    setState(() => _selectedLashIndex = index);
    // Los presets locales van primero en el carrusel (ver build()), así que
    // los primeros _localLashPresets.length índices son locales y el resto
    // corresponde a _currentCarouselDesigns (catálogo remoto).
    if (index < _localLashPresets.length) {
      unawaited(_switchLocalPreset(_localLashPresets[index]));
      return;
    }
    final remoteIndex = index - _localLashPresets.length;
    if (remoteIndex >= 0 && remoteIndex < _currentCarouselDesigns.length) {
      unawaited(_switchDesignModel(_currentCarouselDesigns[remoteIndex]));
    }
  }

  @override
  Widget build(BuildContext context) {
    // "Compatible": diseños del catálogo filtrados en vivo por la forma de
    // ojo detectada (universales + los que coincidan), ya resuelto por
    // filteredCatalogProvider. "Explorar": el catálogo completo sin filtrar.
    final compatibleAsync = ref.watch(filteredDesignCatalogProvider);
    final allAsync = ref.watch(designCatalogListProvider);
    final activeAsyncError =
        (_selectedFilter == 0 ? compatibleAsync : allAsync).error;
    if (activeAsyncError != null) {
      debugPrint('[lash-designs] error cargando catálogo: $activeAsyncError');
    }
    final rawDesigns =
        (_selectedFilter == 0
            ? compatibleAsync.valueOrNull
            : allAsync.valueOrNull) ??
        const [];
    // Solo diseños con imagen entran al carrusel — se mantiene esta MISMA
    // lista (filtrada) en _currentCarouselDesigns para que el índice tocado
    // en el carrusel siga correspondiendo al diseño correcto en _onLashSelect.
    _currentCarouselDesigns =
        rawDesigns.where((d) => d.hasImage).toList(growable: false);
    final carousel = _currentCarouselDesigns;
    // Presets locales primero (siempre disponibles, no dependen del
    // catálogo remoto), después los del admin — ver _onLashSelect para el
    // mapeo de índice a diseño.
    final carouselImagePaths = [
      ..._localLashPresets.map((p) => p.thumbnailAsset),
      ...carousel.map((d) => d.imageUrl!),
    ];
    final carouselLabels = [
      ..._localLashPresets.map((p) => p.name),
      ...carousel.map((d) => d.name),
    ];
    final safeLash = _selectedLashIndex < carouselImagePaths.length
        ? _selectedLashIndex
        : 0;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) return;
        _goHome(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                key: _previewCaptureKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (Platform.isAndroid &&
                        _leftModelPath != null &&
                        _rightModelPath != null)
                      Positioned.fill(
                        child: HybridCameraPreview(
                          key: ValueKey<String>('eye_preview_$_previewSession'),
                          leftModelPath: _leftModelPath!,
                          rightModelPath: _rightModelPath!,
                        ),
                      )
                    else
                      const ColoredBox(color: Colors.black),
                    // DEBUG: puntos de landmarks del párpado (verde =
                    // superior, la línea que el motor usa como pestaña; cruz
                    // amarilla = ancla; naranja = pestaña real detectada).
                    // Apagado con [_showLidLandmarkDebug] para poder juzgar
                    // el render de las pestañas sin nada encima.
                    if (_showLidLandmarkDebug)
                      Positioned.fill(
                        child: CustomPaint(
                          isComplex: true,
                          painter: LidLandmarkDebugPainter(
                            frames: _frameNotifier,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ...EyeTrackingOverlay.buildSiblings(
              onBack: () => _goHome(context),
              status: _frame == null ? _status : null,
              title: _selectedEyeType?.name ?? '',
              onEyeTypeTap: _showEyeTypeSheet,
              onSwitchCamera: () => unawaited(_onSwitchCamera()),
              onFlashTap: () {},
              onDesignTap: () => _onCategoryTap('design'),
              onTechniqueTap: () => _onCategoryTap('tech'),
              onEffectTap: () => _onCategoryTap('effect'),
              onThicknessTap: () => _onCategoryTap('thickness'),
              activeCategory: _activeCategory,
            ),
            EyeTrackingWorkAssistantButton(onTap: _toggleAlignmentGuide),

            // Chips y carrusel se ocultan con la guía de captura activa: ocupan
            // la misma franja inferior que el botón de disparo y el mensaje de
            // la guía, y durante la captura no se usan.
            if (!_alignmentGuideActive)
              EyeTrackingFilterRow(
                selectedFilter: _selectedFilter,
                onSelect: _onFilterSelect,
              ),
            if (_showTransparentMenu &&
                _activeCategory == null &&
                !_alignmentGuideActive)
              Positioned(
                left: 0,
                right: 0,
                bottom: 70,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  // Los presets locales garantizan que el carrusel nunca esté
                // vacío, incluso si el catálogo remoto falla — pero si
                // llegara a fallar la carga de los presets también (no
                // debería), se ve el estado de error en vez de nada.
                child: carouselImagePaths.isNotEmpty
                    ? BottomCarousel(
                        selectedLash: safeLash,
                        onSelect: _onLashSelect,
                        imagePaths: carouselImagePaths,
                      )
                    : Container(
                        height: 70,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          activeAsyncError != null
                              ? 'Error: $activeAsyncError'
                              : 'Sin diseños de pestañas en el catálogo',
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                ),
              ),
            if (_activeCategory != null)
              EyeTrackingDesignMenuBar(
                designImages: _activeCategoryImages,
                designOptions: _activeCategoryOptions,
                selectedDesign: _activeCategorySelectedIndex,
                onSelectDesign: _onActiveCategorySelect,
                onOpenGrid: () => setState(() => _showLashModal = true),
                categoryTitle: LashCustomizationCatalog.titleFor(
                  _activeCategory,
                ),
              ),
            if (_showLashModal)
              EyeTrackingLashModal(
                designImages: _activeCategoryImages,
                designOptions: _activeCategoryOptions,
                onClose: () => setState(() => _showLashModal = false),
              ),
            if (!_showLashModal)
              EyeTrackingPremiumOjoButton(
                onTap: () => unawaited(_openRecommendation()),
                // Nombre del diseño de pestaña seleccionado en el carrusel
                // — antes se mostraba debajo de cada miniatura, ahora vive
                // acá (ver BottomCarousel más abajo, sin `labels`).
                label: safeLash < carouselLabels.length
                    ? carouselLabels[safeLash]
                    : 'Diseño',
              ),
            if (!_showLashModal)
              Positioned(
                top: 35,
                right: 12,
                child: GestureDetector(
                  onTap: () {
                    final sessionClient = ref.read(sessionClientProvider);
                    if (sessionClient != null) {
                      _confirmSaveForClient(sessionClient);
                    } else {
                      unawaited(_setHidingCameraForSaveSheet(true));
                      _showSaveDesignSheet();
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(80),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.actionGreen.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(80),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(
                          Icons.save_alt_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ── Guía de posición de ojos: espera alineación antes de capturar ──
            if (_alignmentGuideActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: EyePositionGuidePainter(
                          eyesClosed: _eyesClosedOk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Botón de captura + mensaje de la guía, apilados en una sola
            // columna inferior para que no se pisen entre sí ni con el resto
            // de los controles (chips/carrusel se ocultan con la guía activa).
            // Queda FUERA del `IgnorePointer` de la guía para que el botón
            // reciba toques. La captura es manual a propósito — ver
            // [_toggleAlignmentGuide].
            if (_alignmentGuideActive)
              Positioned(
                bottom: 62,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_capturingPhoto) ...[
                      _flipCameraButton(),
                      const SizedBox(height: 12),
                    ],
                    if (!_capturingPhoto)
                      GestureDetector(
                        onTap: _beginWorkAssistantFlow,
                        // Atenuado hasta que se detectan los ojos cerrados:
                        // antes de eso [_beginWorkAssistantFlow] no deja
                        // capturar.
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _eyesClosedOk ? 1 : 0.4,
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: _eyesAligned
                                  ? const Color(0xFF2ECC71)
                                  : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              boxShadow: const [
                                BoxShadow(color: Colors.black45, blurRadius: 10),
                              ],
                            ),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              color: _eyesAligned
                                  ? Colors.white
                                  : AppColors.brandPrimary,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 56),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _eyesAligned
                              ? const Color(0xDD1FA24A)
                              : const Color(0xDD0D5C41),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _eyesAligned
                                  ? Icons.check_circle
                                  : (!_faceFramed
                                        ? Icons.crop_free
                                        : Icons.remove_red_eye_outlined),
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _eyesAligned
                                    ? 'Listo para capturar'
                                    : (!_faceFramed
                                          ? 'Encuadra el rostro dentro de la guía'
                                          : 'Ojos cerrados para ver la línea de pestañas'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Procesando captura: la guía de arriba ya desapareció acá,
            // pero la foto REAL todavía no se tomó — restaurar la pestaña
            // 3D, capturar el overlay, detener MediaPipe y abrir una cámara
            // nueva para la foto real toma 1-2s. Sin este aviso la pantalla
            // se ve "normal" y da la impresión de que ya terminó, así que
            // se abren los ojos antes de que dispare la foto de verdad.
            if (_capturingPhoto)
              Positioned.fill(
                child: AbsorbPointer(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xDD0D5C41),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(height: 14),
                            Text(
                              'Tomando la foto…\nMantén los ojos cerrados',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
