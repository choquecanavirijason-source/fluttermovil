import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/network/dio_client.dart';
import 'core/perf/flutter_timings_diag.dart';
import 'core/recommendation/eye_shape_analyzer.dart';
import 'core/recommendation/lash_consultation.dart';
import 'screens/widgets/eye_consultation_sheet.dart';
import 'core/theme/app_colors.dart';
import 'features/catalogo/domain/entities/catalog_item.dart';
import 'features/catalogo/presentation/providers/catalogo_provider.dart';
import 'features/clientes/domain/entities/client.dart';
import 'features/clientes/presentation/providers/clientes_provider.dart';
import 'features/tracking/data/tracking_repository_impl.dart';
import 'eye_tracking_alignment.dart';
import 'eye_tracking_customization_options.dart';
import 'lid_landmark_debug_painter.dart';
import 'lashes/cat_eye_recipe.dart';
import 'lashes/cat_eye_recipe_cache.dart';
import 'lashes/tryon_catalog.dart';
import 'lashes/lash_options.dart';
import 'lashes/lash_style_recommender.dart';
import 'eye_tracking_model.dart';
import 'eye_tracking_photo_pipeline.dart';
import 'native_eye_tracking_service.dart';
import 'screens/widgets/bottom_carousel.dart';
import 'screens/widgets/preview_startup_cover.dart';
import 'screens/widgets/design_thumbnail_image.dart';
import 'screens/widgets/client_picker_sheet.dart';
import 'screens/widgets/eye_position_guide_painter.dart';
import 'screens/widgets/eye_tracking_bottom_actions.dart';
import 'screens/widgets/eye_tracking_design_menu_bar.dart';
import 'screens/widgets/eye_tracking_filter_row.dart';
import 'screens/widgets/eye_tracking_lash_modal.dart';
import 'screens/widgets/eye_tracking_overlay.dart';
import 'screens/widgets/eye_tracking_work_assistant_button.dart';
import 'screens/widgets/hybrid_camera_preview.dart';
import 'screens/widgets/save_options_sheet.dart';
import 'recommendation_args.dart';
import 'lashes/lash_mapping.dart';
import 'work_assistant_args.dart';
import 'features/tracking/domain/entities/saved_tryon_design.dart';
import 'features/tracking/presentation/providers/pending_design_provider.dart';

/// Diseño de pestañas empaquetado en la app (bundle), con modelos .glb
/// reales por ojo (no espejados como los que suben desde el admin, que solo
/// guardan un archivo). Viven en `assets/modelos/` — ver pubspec.yaml.
class _LocalLashPreset {
  final String name;
  final String thumbnailAsset;
  final String leftModelAsset;
  final String rightModelAsset;
  final TryOnStyle? catalogStyle;
  String get stableKey => catalogStyle?.key ?? _lashStyleIdFor(name);
  int get engineStyle =>
      catalogStyle?.engineStyle ?? CatEyeRecipe.styleIds.indexOf(stableKey);
  TryOnStyle get definition =>
      catalogStyle ??
      TryOnStyle(key: stableKey, name: name, builtinStyle: stableKey);
  bool get originalCatEye => definition.originalCatEye;

  const _LocalLashPreset({
    required this.name,
    required this.thumbnailAsset,
    required this.leftModelAsset,
    required this.rightModelAsset,
    this.catalogStyle,
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
    thumbnailAsset: 'assets/modelos/cateye/preview.png',
    leftModelAsset: defaultLeftEyeModelAsset,
    rightModelAsset: defaultRightEyeModelAsset,
  ),
  _LocalLashPreset(
    name: 'Wispy',
    thumbnailAsset: 'assets/modelos/wispy/preview.png',
    leftModelAsset: 'assets/modelos/wispy/wispy_left.glb',
    rightModelAsset: 'assets/modelos/wispy/wispy_right.glb',
  ),
  _LocalLashPreset(
    name: 'Cat Classic',
    thumbnailAsset: 'assets/modelos/catclassic/preview.png',
    leftModelAsset: 'assets/modelos/catclassic/cat_classic_left.glb',
    rightModelAsset: 'assets/modelos/catclassic/cat_classic_right.glb',
  ),
  _LocalLashPreset(
    name: 'Foxy Eye',
    thumbnailAsset: 'assets/modelos/foxyeyex/preview.png',
    leftModelAsset: 'assets/modelos/foxyeyex/foxy_intense_left.glb',
    rightModelAsset: 'assets/modelos/foxyeyex/foxy_intense_right.glb',
  ),
  _LocalLashPreset(
    name: 'Natural',
    thumbnailAsset: 'assets/modelos/natural/preview.png',
    leftModelAsset: 'assets/modelos/natural/natural_left.glb',
    rightModelAsset: 'assets/modelos/natural/natural_right.glb',
  ),
  _LocalLashPreset(
    name: 'Doll Eye',
    thumbnailAsset: 'assets/modelos/dolleye/preview.png',
    leftModelAsset: 'assets/modelos/dolleye/doll_eye_left.glb',
    rightModelAsset: 'assets/modelos/dolleye/doll_eye_right.glb',
  ),
  _LocalLashPreset(
    name: 'Squirrel',
    thumbnailAsset: 'assets/modelos/squirrel/preview.png',
    leftModelAsset: 'assets/modelos/squirrel/squirrel_left.glb',
    rightModelAsset: 'assets/modelos/squirrel/squirrel_right.glb',
  ),
  _LocalLashPreset(
    name: 'Kitten',
    thumbnailAsset: 'assets/modelos/kitten/preview.png',
    leftModelAsset: 'assets/modelos/kitten/kitten_left.glb',
    rightModelAsset: 'assets/modelos/kitten/kitten_right.glb',
  ),
  _LocalLashPreset(
    name: 'Wet Look',
    thumbnailAsset: 'assets/modelos/wetlook/preview.png',
    leftModelAsset: 'assets/modelos/wetlook/wet_look_left.glb',
    rightModelAsset: 'assets/modelos/wetlook/wet_look_right.glb',
  ),
  _LocalLashPreset(
    name: 'Anime',
    thumbnailAsset: 'assets/modelos/anime/preview.png',
    leftModelAsset: 'assets/modelos/anime/anime_left.glb',
    rightModelAsset: 'assets/modelos/anime/anime_right.glb',
  ),
  _LocalLashPreset(
    name: 'Kim K',
    thumbnailAsset: 'assets/modelos/kimk/preview.png',
    leftModelAsset: 'assets/modelos/kimk/kim_k_left.glb',
    rightModelAsset: 'assets/modelos/kimk/kim_k_right.glb',
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
  late final StateController<Client?> _sessionController;

  /// `true` desde el inicio de [dispose]. Las tareas asíncronas (arranque,
  /// re-enlace del preview, regreso del asistente) lo revisan después de
  /// cada `await` para no volver a encender la cámara tras salir.
  bool _disposed = false;
  bool get _alive => mounted && !_disposed;
  final SessionEyeAnalysis _sessionEyeAnalysis = SessionEyeAnalysis();
  final _analysisView =
      ValueNotifier<({EyeAnalysis? analysis, bool needsAdjustment})>((
        analysis: null,
        needsAdjustment: false,
      ));
  EyeAnalysis? get _stableEyeAnalysis => _analysisView.value.analysis;
  LashConsultation _consultation = const LashConsultation();
  List<int>? _rankedStyleIndices;
  List<TryOnEyeCategory> _eyeRecommendationCategories = const [];
  String? _manualEyeRecommendation;

  Widget? get _eyeRecommendationSelector {
    if (!_eyeRecommendationCategories.any(
          (c) => c.detection == 'manual' && c.styleKeys.isNotEmpty,
        ) ||
        _selectedFilter != 0) {
      return null;
    }
    final selected = _eyeRecommendationCategories
        .where((c) => c.key == _manualEyeRecommendation)
        .firstOrNull;
    return PopupMenuButton<String>(
      tooltip: 'Elegir característica del ojo',
      initialValue: _manualEyeRecommendation ?? 'auto',
      onSelected: (key) => setState(() {
        _manualEyeRecommendation = key == 'auto' ? null : key;
      }),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'auto', child: Text('Detección automática')),
        ..._eyeRecommendationCategories
            .where((c) => c.detection == 'manual')
            .map(
              (category) => PopupMenuItem(
                value: category.key,
                enabled: category.styleKeys.isNotEmpty,
                child: Text(
                  '${category.name}${category.detection == 'manual' ? ' · manual' : ''}${category.styleKeys.isEmpty ? ' · sin estilos' : ''}',
                ),
              ),
            ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                selected?.name ?? 'Detección automática',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
            const Icon(Icons.expand_more, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }

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

  /// Ventana de cuadros que se promedian para el mapeo (ver
  /// [EyeTrackingPhotoPipeline.averageFrames]): ~6-9 cuadros a 25-30 fps.
  static const Duration _mappingAverageWindow = Duration(milliseconds: 300);
  final List<({DateTime at, TrackingFrame frame})> _recentMappable = [];

  String _status = 'Inicializando...';
  String? _startupFailure;
  Timer? _startupWatchdog;
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

  /// `false` = Cat Eye se genera con el motor (receta del estilo 0), igual
  /// que los demás estilos. El `.glb` empaquetado (`cateyeleft/right.glb`)
  /// no tiene la base de punta a punta, así que con el pegado a la línea de
  /// pestañas quedaba corto en las comisuras. `true` vuelve a usarlo.
  static const bool _useBundledCatEyeModel = false;

  /// DIAGNÓSTICO: `flutter_overlays` de `perf_flags.properties`. `false`
  /// saca los painters que van encima de la cámara (guía de ojos y puntos de
  /// landmarks) para medir su costo; la lógica de la guía sigue igual.
  /// Default `true`: se pintan como siempre.
  bool _perfFlutterOverlays = true;

  /// Ver [FlutterTimingsDiag] — no hace nada con `PERF_DIAG = false`.
  final FlutterTimingsDiag _timingsDiag = FlutterTimingsDiag();

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
      debugPrint(
        '[EyeTracking] no se pudo ${hide ? 'ocultar' : 'restaurar'} '
        'el modelo para el flujo de guardado: $e',
      );
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

  bool _catalogViewReady = false;
  bool _catalogLoadStarted = false;
  bool _catalogUserInteracted = false;

  void _maybeLoadPublishedCatalog() {
    if (!mounted ||
        !_catalogViewReady ||
        _frame == null ||
        _catalogLoadStarted) {
      return;
    }
    _catalogLoadStarted = true;
    unawaited(_loadPublishedCatalog().whenComplete(_applyPendingDesign));
  }

  int _pendingDesignAttempts = 0;

  /// Aplica el diseño elegido en la ficha de la clienta ("Aplicar diseño").
  /// Usa la copia de parámetros guardada, así se ve igual aunque el estilo
  /// haya cambiado después en el administrador.
  void _applyPendingDesign() {
    if (!mounted) return;
    final design = ref.read(pendingTryOnDesignProvider);
    if (design == null) return;
    // El primer modelo todavía se está cargando: reintenta en un momento.
    if (_switchingDesignModel || _buildingRecipe) {
      if (++_pendingDesignAttempts <= 25) {
        Timer(const Duration(milliseconds: 400), _applyPendingDesign);
      }
      return;
    }
    final index = _availableLashPresets.indexWhere(
      (p) => p.stableKey == design.styleKey,
    );
    if (index < 0 && _publishedPresets == null && _pendingDesignAttempts < 25) {
      // El catálogo publicado no llegó a cargarse: se pide otra vez.
      _pendingDesignAttempts++;
      unawaited(_loadPublishedCatalog().whenComplete(_applyPendingDesign));
      return;
    }
    ref.read(pendingTryOnDesignProvider.notifier).state = null;
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'El estilo "${design.styleName}" ya no está disponible en el probador.',
          ),
        ),
      );
      return;
    }
    _loadSavedDesign(index, design);
  }

  void _loadSavedDesign(int index, SavedTryOnDesign design) {
    final preset = _availableLashPresets[index];
    final style = preset.definition;
    _catalogUserInteracted = true;
    _recipeTimer?.cancel();
    final request = ++_recipeRequest;
    setState(() {
      _selectedLashIndex = index;
      _appliedRecipe = null;
      _appliedCatalogStyle = null;
      _selectedDesignIndex = design.length;
      _selectedTechIndex = design.technique;
      _selectedThicknessIndex = design.thickness;
      _selectedColorId = design.colorId;
      _savedColorHex = design.colorHex ?? LashOptionCatalog.approvedBlack;
      _selectedCurlId = design.curlId;
      _activeCategory = null;
      _showTransparentMenu = true;
    });
    if (_useBundledCatEyeModel && design.original && preset.originalCatEye) {
      unawaited(_switchLocalPreset(preset));
    } else {
      setState(() => _buildingRecipe = true);
      ResolvedLashOptions? options = design.options;
      try {
        options ??= style.options.resolve(
          design.length,
          design.technique,
          design.thickness,
        );
      } catch (_) {
        options = null;
      }
      unawaited(
        _applyRecipe(
          options == null
              ? style.recipe()
              : CatEyeRecipe(
                  style: style.engineStyle,
                  options: options,
                  profile: design.profile ?? style.profile,
                  catalogStyleKey: style.key,
                  catalogRevision: design.revision,
                  length: design.length,
                  technique: design.technique,
                  thickness: design.thickness,
                  curlShape: design.curl,
                  curlId: design.curlId,
                ),
          request,
        ),
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Diseño guardado aplicado: ${design.styleName}'),
        backgroundColor: AppColors.actionGreen,
      ),
    );
  }

  List<_LocalLashPreset>? _publishedPresets;
  List<_LocalLashPreset> get _availableLashPresets =>
      _publishedPresets ?? _localLashPresets;
  _LocalLashPreset? get _selectedPreset =>
      _selectedLashIndex >= 0 &&
          _selectedLashIndex < _availableLashPresets.length
      ? _availableLashPresets[_selectedLashIndex]
      : null;
  TryOnStyle? _appliedCatalogStyle;

  Future<void> _loadPublishedCatalog() async {
    final catalog = await TryOnCatalogRepository(ref.read(dioProvider)).load();
    if (!mounted ||
        catalog == null ||
        _catalogUserInteracted ||
        _buildingRecipe ||
        _switchingDesignModel ||
        _alignmentGuideActive ||
        _capturingPhoto) {
      return;
    }
    final previousKey = _selectedPreset?.stableKey;
    final presets = catalog.styles
        .where((s) => s.active)
        .map((style) {
          final base = _localLashPresets[style.engineStyle];
          return _LocalLashPreset(
            name: style.name,
            thumbnailAsset: style.thumbnail ?? base.thumbnailAsset,
            leftModelAsset: base.leftModelAsset,
            rightModelAsset: base.rightModelAsset,
            catalogStyle: style,
          );
        })
        .toList(growable: false);
    if (presets.isEmpty) return;
    final matching = presets.indexWhere((p) => p.stableKey == previousKey);
    setState(() {
      _publishedPresets = presets;
      _rankedStyleIndices = null;
      _eyeRecommendationCategories = catalog.eyeCategories;
      _selectedLashIndex = matching < 0 ? 0 : matching;
      _currentCarouselDesigns = const [];
    });
    // Keep the approved Cat Eye original only when its published definition
    // remains original; other published defaults are applied through the cache.
    if (_useBundledCatEyeModel &&
        _appliedRecipe == null &&
        _selectedPreset!.originalCatEye &&
        previousKey == _selectedPreset!.stableKey) {
      _resetRecipeSelection();
      _appliedCatalogStyle = _selectedPreset!.definition;
    } else {
      _onLashSelect(_selectedLashIndex);
    }
  }

  final _recipeCache = CatEyeRecipeCache();
  CatEyeRecipe? _appliedRecipe;
  Timer? _recipeTimer;
  int _recipeRequest = 0;
  bool _buildingRecipe = false;

  void _resetRecipeSelection() {
    final style = _selectedPreset?.definition;
    _selectedDesignIndex = _appliedRecipe?.length ?? style?.defaultLength ?? 1;
    _selectedTechIndex =
        _appliedRecipe?.technique ?? style?.defaultTechnique ?? 0;
    _selectedThicknessIndex =
        _appliedRecipe?.thickness ?? style?.defaultThickness ?? 3;
    _selectedColorId = style?.defaultColor ?? 0;
    _savedColorHex = null;
    _selectedCurlId = _appliedRecipe?.curlId ?? style?.defaultCurl;
  }

  Future<void> _applyRecipe(CatEyeRecipe recipe, int request) async {
    try {
      final paths = await _recipeCache.resolve(recipe);
      if (!mounted ||
          request != _recipeRequest ||
          _selectedPreset?.stableKey !=
              (recipe.catalogStyleKey ?? recipe.styleId)) {
        return;
      }
      setState(() => _switchingDesignModel = true);
      await _service.setLashColor(_selectedColorHex);
      await _service.loadEyeModels(
        leftPath: paths.left,
        rightPath: paths.right,
      );
      await _service.setLashStyle(recipe.styleId);
      if (!mounted) return;
      setState(() {
        _leftModelPath = paths.left;
        _rightModelPath = paths.right;
        _appliedRecipe = recipe;
        _appliedCatalogStyle = _selectedPreset?.definition;
      });
    } catch (e) {
      if (mounted && request == _recipeRequest) {
        setState(_resetRecipeSelection);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudieron aplicar los ajustes. Inténtalo de nuevo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted && request == _recipeRequest) {
        setState(() {
          _buildingRecipe = false;
          _switchingDesignModel = false;
        });
      }
    }
  }

  void _restoreCurrentStyle() {
    if (_switchingDesignModel) return;
    _onLashSelect(_selectedLashIndex);
  }

  int _selectedFilter = 0;
  int _selectedLashIndex = 0;
  int _selectedDesignIndex = 1;
  int _selectedTechIndex = 0;
  int _selectedThicknessIndex = 3;

  /// Curvatura elegida (`null` = curva propia del estilo).
  int? _selectedCurlId;

  /// Color de pestaña elegido (id del catálogo; 0 = negro aprobado).
  int _selectedColorId = 0;

  /// `#RRGGBB` del color elegido, o `null` para el negro aprobado.
  /// Color de un diseño guardado: se respeta aunque el catálogo ya no lo
  /// ofrezca. Se descarta al elegir otro color o estilo.
  String? _savedColorHex;

  String? get _selectedColorHex {
    final saved = _savedColorHex;
    if (saved != null) {
      return saved == LashOptionCatalog.approvedBlack ? null : saved;
    }
    final hex =
        _selectedPreset?.definition.options
                .color(_selectedColorId)
                .parameters['color']
            as String?;
    return hex == null || hex == LashOptionCatalog.approvedBlack ? null : hex;
  }

  /// El estilo elegido ofrece más de un color (si no, no hay selector).
  bool get _hasColorChoices =>
      (_selectedPreset?.definition.colors.length ?? 0) > 1;
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
    _onCameraFacingChanged(isFront);
  }

  Future<void> _onSwitchCamera() async {
    final isFront = await _service.switchCamera();
    if (!mounted || isFront == null) return;
    _onCameraFacingChanged(isFront);
  }

  /// Modo "clienta echada" (botón de la guía de captura, con la frontal o la
  /// trasera): cambia la FORMA DE DETECTAR el rostro, no la cámara. El
  /// análisis de MediaPipe se rota 180° en nativo (ver
  /// `CameraXManager.analysisRotated180`) para que vea la cara derecha, y
  /// los landmarks y la pose vuelven desrotados al espacio del preview
  /// (`FaceLandmarkerHelper.derotated180`). La vista de cámara y la foto
  /// NO se giran; lo único que cambia de sentido en pantalla es la guía de
  /// encuadre (ver [EyePositionGuidePainter.inverted]).
  ///
  /// Dura mientras dura la sesión de cámara de esta pantalla (incluido el
  /// ida y vuelta al asistente) y se apaga al CAMBIAR DE CÁMARA: con la
  /// cámara nueva el rostro llega en otra posición. Funciona con las dos
  /// cámaras: en nativo el giro se aplica DESPUÉS del espejo de la frontal y
  /// se deshace igual (ver `CameraXManager.analysisRotated180`), así que el
  /// celular puede quedar del lado que le resulte cómodo a la operaria.
  bool _cameraInverted180 = false;

  /// Aplica [_cameraInverted180] en nativo. `photoMode` sigue a la guía de
  /// captura, igual que antes (ver [_toggleAlignmentGuide]).
  Future<void> _applyInvertedFaceMode() => _service.setInvertedFaceMode(
    _cameraInverted180,
    photoMode: _alignmentGuideActive,
  );

  void _onCameraFacingChanged(bool isFront) {
    final resetInverted = _cameraInverted180;
    setState(() {
      _usingFrontCamera = isFront;
      if (resetInverted) _cameraInverted180 = false;
    });
    if (resetInverted) unawaited(_applyInvertedFaceMode());
  }

  void _toggleInvertedFaceMode() {
    if (_workAssistantOpening) return;
    setState(() {
      _cameraInverted180 = !_cameraInverted180;
      // El rostro cambia de lugar en la vista: el encuadre se reevalúa.
      _eyesAligned = false;
      _faceFramed = false;
      _eyesClosedOk = false;
      _eyesOnGuideLine = false;
    });
    unawaited(_applyInvertedFaceMode());
  }

  CatalogItem? _selectedEyeType;
  List<CatalogItem>? _eyeTypes;

  /// true una vez que el usuario elige el tipo de ojo manualmente desde la
  /// hoja de selección; a partir de ahí deja de sobreescribirse con el
  /// resultado del escaneo automático.

  /// true mientras se muestra la guía de alineación (esperando que el usuario
  /// ubique sus ojos en el marco antes de capturar).
  bool _alignmentGuideActive = false;

  /// true cuando se cumplen LAS DOS condiciones (rostro encuadrado + ojos
  /// cerrados) — dispara la captura tras `_alignmentHoldDuration`.
  bool _eyesAligned = false;

  /// Ojos sobre la línea horizontal de la guía (pinta la línea en verde).
  /// Requisito para capturar — ver [_beginWorkAssistantFlow] y
  /// `AlignmentStatus.eyesOnLine`.
  bool _eyesOnGuideLine = false;

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
      await _service.setLashColor(null);
      await _service.loadEyeModels(leftPath: path, rightPath: path);
      final styleId = _lashStyleIdFor(design.name);
      await _service.setLashStyle(styleId);
    } catch (e) {
      debugPrint('No se pudo cargar el modelo del diseño ${design.id}: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo cargar el diseño "${design.name}"'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingDesignModel = false);
    }
  }

  /// Igual que [_switchDesignModel] pero para un diseño empaquetado en la
  /// app (ver [_availableLashPresets]): cada lado usa su propio asset real, sin
  /// necesidad de descargar nada.
  Future<void> _switchLocalPreset(_LocalLashPreset preset) async {
    if (_switchingDesignModel) return;
    setState(() => _switchingDesignModel = true);
    try {
      final leftPath = await extractEyeModelAssetToFile(preset.leftModelAsset);
      final rightPath = await extractEyeModelAssetToFile(
        preset.rightModelAsset,
      );
      if (!mounted) return;
      _leftModelPath = leftPath;
      _rightModelPath = rightPath;
      await _service.setLashColor(_selectedColorHex);
      await _service.loadEyeModels(leftPath: leftPath, rightPath: rightPath);
      final styleId = CatEyeRecipe.styleIds[preset.engineStyle];
      await _service.setLashStyle(styleId);
      _appliedCatalogStyle = preset.definition;
    } catch (e) {
      debugPrint('No se pudo cargar el preset local ${preset.name}: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo cargar el diseño "${preset.name}"'),
          ),
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
      if (mounted) {
        setState(() => _startupFailure = 'No se pudieron cargar los diseños.');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _enterImmersive();
    // Se lee acá y no en `dispose`: Riverpod no deja usar `ref` mientras el
    // widget se desmonta, y ese error cortaba `dispose` a la mitad (la
    // pantalla quedaba "viva" y sus tareas pendientes volvían a encender la
    // cámara después de salir).
    _sessionController = ref.read(sessionClientProvider.notifier);
    _photoPipeline = EyeTrackingPhotoPipeline(
      previewCaptureKey: _previewCaptureKey,
    );
    WidgetsBinding.instance.addObserver(this);
    // Paint the loading view before creating native camera/Filament surfaces.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startupWatchdog = Timer(const Duration(seconds: 20), () {
        if (mounted && _frame == null) {
          setState(
            () => _startupFailure ??=
                'No se pudo iniciar la cámara. Vuelve a intentarlo.',
          );
        }
      });
      unawaited(_resolveEyeModelPaths());
      unawaited(
        _start().catchError((Object error, StackTrace stack) {
          if (mounted) {
            setState(() => _startupFailure = 'No se pudo iniciar la cámara.');
          }
        }),
      );
    });
    _timingsDiag.start();
    unawaited(_loadPerfFlags());

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
      // Android puede volver a mostrar las barras al regresar a la app.
      _enterImmersive();
      unawaited(_restartCameraFromLifecycle());
    }
  }

  /// Pantalla completa en la cámara: oculta la barra de navegación (atrás,
  /// inicio, multitarea) y la de estado. Con `immersiveSticky` deslizar
  /// desde el borde las muestra un momento y se vuelven a ocultar solas.
  void _enterImmersive() {
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  /// Restaura las barras del sistema como en el resto de la app.
  void _exitImmersive() {
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      ),
    );
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
    if (!_alive) return;
    // El badge "Rostro detectado"/"Sin rostro" se quitó: era redundante con
    // la guía de encuadre (ver `EyePositionGuidePainter`) y quedaba
    // desactualizado/engañoso fuera del flujo del asistente. `_status` ahora
    // solo lo tocan los mensajes de ciclo de vida (permiso, error, "iniciando
    // cámara…") — la llegada del primer frame oculta el badge (ver
    // `_frame == null` en el `build`).
    final isFirstFrame = _frame == null;
    if (isFirstFrame) {
      _startupWatchdog?.cancel();
      _startupFailure = null;
    }
    _frame = frame;
    // El primer frame tiene que redibujar SIEMPRE: quita la portada de
    // carga (`PreviewStartupCover`, `ready: _frame != null`). Antes solo se
    // redibujaba si ese frame traía rostro, y la portada quedaba hasta que
    // otro cambio cualquiera redibujara (aparecía/desaparecía al azar).
    if (isFirstFrame && mounted) setState(() {});
    _maybeLoadPublishedCatalog();
    // Repintado de los overlays: independiente del throttle de `setState`
    // (ver [_frameNotifier]) — aquí no hay límite, cada frame que llega se
    // dibuja, que es lo que hace que los puntos sigan la cabeza sin saltos.
    _frameNotifier.value = frame;
    if (frame.faceDetected &&
        frame.leftEye.length >= 4 &&
        frame.rightEye.length >= 4) {
      final now = DateTime.now();
      _lastMappableFrame = frame;
      _lastMappableAt = now;
      _recentMappable.add((at: now, frame: frame));
      _recentMappable.removeWhere(
        (e) => now.difference(e.at) > _mappingAverageWindow,
      );
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
    if (!_alive) return;
    _sub = _service.trackingStream.listen(
      _handleTrackingFrame,
      onError: (Object e, StackTrace st) {
        if (!mounted) return;
        setState(() {
          _status = 'Error: $e';
          if (_frame == null) _startupFailure = 'No se pudo iniciar la cámara.';
        });
      },
    );
    await _service.startTracking();
    if (_disposed) {
      await _sub?.cancel();
      _sub = null;
      _service.stopTracking();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await _service.refreshPreviewBind();
  }

  Future<void> _start() async {
    // Primera apertura tras instalar: la vista de cámara se crea antes de que
    // la usuaria conceda el permiso y queda en negro. Si el permiso se acaba
    // de conceder, se reenlaza el preview al final.
    final hadPermission = await Permission.camera.isGranted;
    final camera = await Permission.camera.request();
    if (!mounted) return;
    if (!camera.isGranted) {
      setState(() {
        _status = 'Permiso de cámara denegado';
        _startupFailure =
            'Se necesita permiso de cámara para abrir el probador.';
      });
      return;
    }

    setState(() => _status = 'Iniciando cámara…');

    if (!_alive) return;
    _sub = _service.trackingStream.listen(
      _handleTrackingFrame,
      onError: (Object e, StackTrace st) {
        if (!mounted) return;
        setState(() {
          _status = 'Error: $e';
          if (_frame == null) _startupFailure = 'No se pudo iniciar la cámara.';
        });
      },
    );

    await _service.startTracking();
    if (_disposed) {
      await _sub?.cancel();
      _sub = null;
      _service.stopTracking();
      return;
    }
    if (!mounted) return;
    // La cámara activa vive en Kotlin y puede haber quedado en la trasera
    // desde otra pantalla: el botón "Invertir" sólo se muestra con ella.
    unawaited(_syncCameraFacing());
    setState(() {
      if (_status == 'Iniciando cámara…') {
        _status = 'Esperando detección…';
      }
    });
    if (!hadPermission) await _rebindPreview();

    // La carga del GLB ya no depende de un retry-loop temporizado: viaja
    // como creationParams del PlatformView (ver HybridCameraPreview), así
    // que Kotlin la ejecuta de forma síncrona en el mismo create() que
    // adjunta el SceneView nuevo.
  }

  /// Ver [_perfFlutterOverlays].
  Future<void> _loadPerfFlags() async {
    final overlays = await _service.perfFlutterOverlaysEnabled();
    _timingsDiag.label = 'overlays=${overlays ? 'on' : 'off'}';
    if (!mounted || overlays == _perfFlutterOverlays) return;
    setState(() => _perfFlutterOverlays = overlays);
  }

  @override
  void dispose() {
    _disposed = true;
    _exitImmersive();
    _startupWatchdog?.cancel();
    _analysisView.dispose();
    _recipeTimer?.cancel();
    _recipeRequest++;
    _timingsDiag.stop();
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _sub = null;
    // Fin de la sesión de cámara de esta pantalla: [_cameraInverted180]
    // muere con el State, así que el nativo vuelve al modo normal en vez de
    // heredarle el análisis rotado a la próxima pantalla que use la cámara.
    unawaited(_service.setInvertedFaceMode(false));
    _service.stopTracking();
    _frameNotifier.dispose();
    // Route disposal may run during build: notify other consumers only after
    // their current frame has finished, never from this element's teardown.
    final sessionController = _sessionController;
    final departingClient = sessionController.state;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(sessionController.state, departingClient)) {
        sessionController.state = null;
      }
    });
    super.dispose();
  }

  bool _leavingPreview = false;

  void _goHome(BuildContext context) {
    if (!mounted || _leavingPreview) return;
    if (_alignmentGuideActive && !_capturingPhoto && !_workAssistantOpening) {
      _toggleAlignmentGuide();
      return;
    }
    _leavingPreview = true;
    // Do not navigate recursively while Router is disposing a popped route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/');
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _onFilterSelect(int index) {
    if (_switchingDesignModel) return;
    final resetRemote = _selectedLashIndex >= _availableLashPresets.length;
    if (resetRemote) _onLashSelect(0);
    setState(() {
      _selectedFilter = index;
      _showTransparentMenu = true;
      _activeCategory = null;
      // Local presets have identical indices in both catalogue filters.
    });
  }

  void _onCategoryTap(String category) {
    setState(() {
      _activeCategory = category;
      _showTransparentMenu = false;
    });
  }

  List<int> get _activeOptionValues {
    final style = _selectedPreset?.definition;
    return switch (_activeCategory) {
      'design' => style?.lengths ?? const [0, 1, 2],
      'tech' => style?.techniques ?? const [0, 1, 2, 3],
      'thickness' => style?.thicknesses ?? const [0, 1, 2, 3],
      'color' => style?.colorOptions.map((o) => o.id).toList() ?? const [0],
      'curl' => style?.curlOptions.map((o) => o.id).toList() ?? const [],
      _ => const [],
    };
  }

  String _optionKind(String? category) => switch (category) {
    'design' => 'length',
    'tech' => 'technique',
    'color' => 'color',
    'curl' => 'curl',
    _ => 'thickness',
  };
  String _optionLabel(String kind, int id) => kind == 'color'
      ? _selectedPreset!.definition.options.color(id).name
      : _selectedPreset!.definition.options.get(kind, id).name;
  List<int> get _recommendedPresetIndices {
    var presetIndices = List.generate(_availableLashPresets.length, (i) => i);
    if (_selectedFilter == 0 && _manualEyeRecommendation != null) {
      final selectedCategory = _eyeRecommendationCategories
          .where((c) => c.key == _manualEyeRecommendation)
          .firstOrNull;
      if (selectedCategory != null) {
        final recommended = presetIndices
            .where(
              (i) => selectedCategory.styleKeys.contains(
                _availableLashPresets[i].stableKey,
              ),
            )
            .toList();
        if (recommended.isNotEmpty) presetIndices = recommended;
      }
    } else if (_selectedFilter == 0 &&
        (_stableEyeAnalysis != null || _consultation.shapeOverride != null)) {
      _rankedStyleIndices ??= LashStyleRecommender.rank(
        _availableLashPresets.map((p) => p.definition).toList(),
        _stableEyeAnalysis ?? EyeAnalysis.none,
        consultation: _consultation,
      );
      presetIndices = _rankedStyleIndices!.take(5).toList();
    }
    return presetIndices;
  }

  List<String> get _activeCategoryImages => _activeCategory == 'effect'
      ? _recommendedPresetIndices
            .map((i) => _availableLashPresets[i].thumbnailAsset)
            .toList()
      : _activeCategory == 'color'
      ? _activeOptionValues
            .map(
              (id) =>
                  'swatch:${_selectedPreset!.definition.options.color(id).parameters['color']}',
            )
            .toList()
      : _activeCategory == 'curl'
      ? _activeOptionValues.map((id) {
          final c = _selectedPreset!.definition.options.curlShape(id);
          return c == null
              ? ''
              : '${DesignThumbnailImage.curlPrefix}${c.degrees},${c.position},${c.sharpness}';
        }).toList()
      : _activeOptionValues.map((id) {
          final images = LashCustomizationCatalog.imagesFor(_activeCategory);
          final option = _selectedPreset!.definition.options.get(
            _optionKind(_activeCategory),
            id,
          );
          final index = _activeCategory == 'tech'
              ? option.parameters['base_technique'] as int
              : id;
          return images[index.clamp(0, images.length - 1)];
        }).toList();
  List<String> get _activeCategoryOptions => _activeCategory == 'effect'
      ? _recommendedPresetIndices
            .map((i) => _availableLashPresets[i].name)
            .toList()
      : _activeOptionValues
            .map((id) => _optionLabel(_optionKind(_activeCategory), id))
            .toList();
  int get _activeCategorySelectedIndex {
    final value = switch (_activeCategory) {
      'design' => _selectedDesignIndex,
      'tech' => _selectedTechIndex,
      'thickness' => _selectedThicknessIndex,
      'color' => _selectedColorId,
      'curl' => _selectedCurlId ?? -1,
      _ => -1,
    };
    return _activeCategory == 'effect'
        ? _recommendedPresetIndices.indexOf(_selectedLashIndex)
        : _activeOptionValues.indexOf(value);
  }

  void _onActiveCategorySelect(int index) {
    if (_switchingDesignModel || _hidingLashesForAlignmentGuide) return;
    _catalogUserInteracted = true;
    if (_activeCategory == 'effect') {
      _onLashSelect(_recommendedPresetIndices[index]);
      return;
    }
    if (_activeCategory == 'color') {
      unawaited(_onColorSelect(_activeOptionValues[index]));
      return;
    }
    if (_selectedLashIndex >= _availableLashPresets.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecciona un estilo del probador para ajustar largo, técnica y grosor.',
          ),
        ),
      );
      return;
    }
    setState(() {
      switch (_activeCategory) {
        case 'design':
          _selectedDesignIndex = _activeOptionValues[index];
          break;
        case 'tech':
          _selectedTechIndex = _activeOptionValues[index];
          break;
        case 'thickness':
          _selectedThicknessIndex = _activeOptionValues[index];
          break;
        case 'curl':
          _selectedCurlId = _activeOptionValues[index];
          break;
      }
      _buildingRecipe = true;
    });
    final recipe = _selectedPreset!.definition.recipe(
      length: _selectedDesignIndex,
      technique: _selectedTechIndex,
      thickness: _selectedThicknessIndex,
      curl: _selectedCurlId,
    );
    final request = ++_recipeRequest;
    _recipeTimer?.cancel();
    _recipeTimer = Timer(
      const Duration(milliseconds: 120),
      () => unawaited(_applyRecipe(recipe, request)),
    );
  }

  /// Cambia solo el color de las fibras: mismo modelo y misma geometría,
  /// recargados con el color nuevo (como al cambiar de estilo).
  Future<void> _onColorSelect(int colorId) async {
    if ((colorId == _selectedColorId && _savedColorHex == null) ||
        _leftModelPath == null) {
      return;
    }
    setState(() {
      _selectedColorId = colorId;
      _savedColorHex = null;
      _switchingDesignModel = true;
    });
    try {
      await _service.setLashColor(_selectedColorHex);
      await _service.loadEyeModels(
        leftPath: _leftModelPath,
        rightPath: _rightModelPath,
      );
    } catch (e) {
      debugPrint('[EyeTracking] no se pudo aplicar el color: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo aplicar el color')),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingDesignModel = false);
    }
  }

  /// La última captura usó el respaldo con el plugin `camera` (segunda
  /// sesión de cámara) en vez de la foto nativa.
  bool _lastCaptureUsedPluginFallback = false;

  Future<void> _resumeEyePreviewAfterAssistant() async {
    // Espera para que el plugin `camera` libere el hardware: solo hace
    // falta si la foto usó ese respaldo. Con la foto nativa (lo normal) la
    // espera fija de 800 ms era lo que hacía lento el cierre del robot.
    await Future<void>.delayed(
      Duration(milliseconds: _lastCaptureUsedPluginFallback ? 800 : 150),
    );
    if (!mounted) return;
    // El asistente puede haber cambiado de cámara: si cambió, se apaga
    // "Invertir" (ver [_cameraInverted180]) antes de reaplicarlo.
    await _syncCameraFacing();
    if (!mounted) return;

    // Descarta los landmarks del último frame para que el diagnóstico no
    // quede congelado sobre el preview hasta la siguiente detección.
    _frameNotifier.value = null;
    _lastMappableFrame = null;
    _lastMappableAt = null;
    _recentMappable.clear();
    setState(() {
      _previewSession++;
      _frame = null;
      _eyesAligned = false;
      _faceFramed = false;
      _eyesClosedOk = false;
      _eyesOnGuideLine = false;
    });

    // Tiempo para que el nuevo AndroidView llame a attachPreview().
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    // La suscripción al stream puede haberse cortado mientras el asistente
    // estaba encima (p. ej. el ciclo de vida pasó por `paused` y puso `_sub`
    // en null). Se re-suscribe siempre: el stream es broadcast y compartido,
    // así que cancelar y volver a escuchar es seguro.
    await _sub?.cancel();
    if (!_alive) return;
    _sub = _service.trackingStream.listen(
      _handleTrackingFrame,
      onError: (Object e, StackTrace st) {
        if (!mounted) return;
        setState(() {
          _status = 'Error: $e';
          if (_frame == null) _startupFailure = 'No se pudo iniciar la cámara.';
        });
      },
    );
    await _service.startTracking();
    if (_disposed) {
      await _sub?.cancel();
      _sub = null;
      _service.stopTracking();
      return;
    }

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

  /// `true` si el overlay que captura [EyeTrackingPhotoPipeline.captureOverlay]
  /// saldría TRANSPARENTE: dentro del RepaintBoundary sólo está la vista
  /// nativa (cámara + pestañas 3D, que salen transparentes en la captura) y
  /// el painter de debug, apagado. La grilla NO va horneada: la dibuja el
  /// asistente en vivo. Si alguna de estas condiciones cambia (debug
  /// encendido, o el recuadro negro sin modelos), se vuelve a capturar como
  /// antes.
  /// TEMPORAL — por qué camino se compuso la última foto ('nativo' o
  /// 'Dart'), para el log `CaptureTiming`.
  String _lastComposeVia = '';

  bool get _captureOverlayIsEmpty =>
      Platform.isAndroid &&
      _leftModelPath != null &&
      _rightModelPath != null &&
      !_showLidLandmarkDebug;

  Future<void> _finishWorkAssistantOpen() async {
    if (_workAssistantOpening) return;
    _workAssistantOpening = true;
    _lastCaptureUsedPluginFallback = false;
    try {
      // Con "Clienta echada" la cámara NO se gira: foto, overlay y landmarks
      // (ya desrotados en nativo) quedan en la orientación en que la
      // operaria ve a la clienta, por el mismo camino que el modo normal.
      final inverted = _cameraInverted180;
      final timing = Stopwatch()..start(); // TEMPORAL — ver CaptureTiming.
      // Si el overlay saldría transparente (ver [_captureOverlayIsEmpty]) no
      // se captura: de él sólo se usaban sus medidas, y capturarlo,
      // codificarlo en PNG, decodificarlo y mezclarlo era buena parte de la
      // demora. La foto final sale idéntica (ver
      // `EyeTrackingPhotoPipeline.compositeAndCrop`, `overlaySize`).
      final skipOverlay = _captureOverlayIsEmpty;
      final overlayBytes = skipOverlay
          ? null
          : await _photoPipeline.captureOverlay(context);
      final previewSize = _photoPipeline.previewSize;
      final overlaySize = skipOverlay && previewSize != null
          ? EyeTrackingPhotoPipeline.overlayPixelSize(previewSize)
          : null;
      final overlayMs = timing.elapsedMilliseconds;

      // Qué cámara está usando el tracking AHORA, preguntándoselo a Kotlin
      // (ver [_syncCameraFacing]). Se consulta acá, sobre el final, para que
      // la foto salga con la misma cámara aunque el estado se haya cambiado
      // desde otra pantalla o esta se haya recreado en el medio.
      await _syncCameraFacing();
      if (!mounted) return;
      // El mapeo se congela JUSTO antes de la foto (y no al tocar el botón):
      // mientras se capturaba el overlay la mano o la cabeza pueden haberse
      // movido, y el mapeo quedaba corrido respecto del ojo de la foto.
      final assistantFrame =
          (overlayBytes == null && overlaySize == null) || previewSize == null
          ? null
          : EyeTrackingPhotoPipeline.frameForCapturedBand(
              _freezeMappingFrame(),
              previewSize,
              // Con la guía girada los ojos quedan más abajo en pantalla:
              // franja de recorte reflejada (ver `_cropEyeBand`).
              flipEyeBand: inverted,
            );

      // 3. Foto por la MISMA sesión de cámara, sin detener el tracking: sale
      // a los ~200 ms del overlay en vez de 1-2 s, que es lo que hacía que
      // con el pulso de la mano el mapeo quedara corrido respecto del ojo.
      final nativeShot = await _service.takePhoto();
      if (!mounted) return;
      final photoMs = timing.elapsedMilliseconds;

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
        // Con el overlay omitido, el recorte se hace en NATIVO (mucho más
        // rápido que Dart puro, ver `PhotoBandCropper`), con el mismo
        // encuadre y medidas. Si falla, el camino en Dart de siempre.
        Future<Uint8List> compose() async {
          final size = overlaySize;
          if (size != null) {
            final band = EyeTrackingPhotoPipeline.eyeBandRatios(
              flipEyeBand: inverted,
            );
            final native = await _service.cropPhotoBand(
              nativeShot,
              mirror: mirror,
              rotate180: false,
              bandStart: band.start,
              bandHeight: band.height,
              overlayWidth: size.width,
              overlayHeight: size.height,
            );
            if (native != null) {
              _lastComposeVia = 'nativo';
              return native;
            }
          }
          _lastComposeVia = 'Dart';
          return EyeTrackingPhotoPipeline.compositeAndCropInBackground(
            nativeShot,
            overlayBytes,
            mirror: mirror,
            flipEyeBand: inverted,
            overlaySize: overlaySize,
          );
        }

        pendingPhoto = compose().then<Uint8List?>(
          (bytes) {
            debugPrint(
              'CaptureTiming probador: overlay=${overlayMs}ms '
              '(${skipOverlay ? 'omitido' : 'capturado'}) '
              'foto=${photoMs - overlayMs}ms '
              'composicion=${timing.elapsedMilliseconds - photoMs}ms '
              '(via $_lastComposeVia) '
              'total=${timing.elapsedMilliseconds}ms',
            );
            return bytes;
          },
          onError: (Object e) {
            debugPrint('[EyeTracking] compositeAndCrop falló: $e');
            return nativeShot;
          },
        );
      } else {
        // Respaldo: si el caso de uso de foto no estaba disponible, se cae
        // al camino viejo (segunda sesión de cámara), que funciona igual
        // pero con el desfase de siempre.
        debugPrint(
          '[EyeTracking] takePhoto nativo no disponible — usando el '
          'camino de respaldo con el plugin camera',
        );
        _lastCaptureUsedPluginFallback = true;
        await _service.stopTracking();
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (!mounted) return;
        finalPhoto = await _photoPipeline.captureAndComposite(
          context,
          overlayBytes,
          preferFrontCamera: _usingFrontCamera,
          flipEyeBand: inverted,
          overlaySize: overlaySize,
        );
      }
      if (!mounted) return;
      // Foto real ya tomada — ya no importa si abre los ojos, apaga el
      // aviso acá y no en el `finally` (que sigue corriendo durante la
      // navegación a `/work-assistant`).
      setState(() => _capturingPhoto = false);

      // Mapeo del estilo y largo que la operaria tiene armados ahora.
      final mapStyle = _selectedPreset?.definition;
      var mapOptions = _appliedRecipe?.options;
      if (mapOptions == null && mapStyle != null) {
        try {
          mapOptions = mapStyle.options.resolve(
            _selectedDesignIndex,
            _selectedTechIndex,
            _selectedThicknessIndex,
          );
        } catch (_) {
          mapOptions = null;
        }
      }
      final lashMap = resolveLashMap(
        style: mapStyle,
        applied: _appliedRecipe,
        length: mapOptions?.length,
      );
      if (!mounted) return;
      await context.push(
        '/work-assistant',
        extra: WorkAssistantArgs(
          panelPngBytes: finalPhoto,
          panelBytesFuture: pendingPhoto,
          mappingFrame: assistantFrame,
          mappingStyleId: mapStyle?.builtinStyle ?? 'cateye',
          mappingLabels: lashMap?.labels,
          mappingFromSalon: lashMap?.source == LashMapSource.salon,
          mappingStyleName: _selectedPreset?.name,
          mappingSummary: mapOptions == null
              ? null
              : '${mapOptions.length.name} · ${mapOptions.technique.name} · '
                    '${mapOptions.thickness.name}',
          cropOverlayBytes: overlayBytes,
          cropOverlaySize: overlaySize,
          mappingPreviewSize: previewSize,
          mirrorPhoto: _usingFrontCamera,
          cameraInverted180: inverted,
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
      // Se reaplica el modo de ESTA pantalla (el asistente puede haberlo
      // cambiado) y se suelta la foto rápida, que era de la guía. El 3D ya
      // soporta el análisis rotado, así que no hace falta forzar `false`.
      unawaited(_applyInvertedFaceMode());
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
  /// Cuenta las entradas al asistente de encuadre; 0 = todavía ninguna.
  /// Cada entrada muestra el loader (ver `PreviewStartupCover` en build()).
  int _guideLoaderSession = 0;

  void _toggleAlignmentGuide() {
    if (_workAssistantOpening || _buildingRecipe || _switchingDesignModel) {
      return;
    }
    final activating = !_alignmentGuideActive;
    setState(() {
      _alignmentGuideActive = activating;
      // Nueva sesión del loader del asistente (key nueva = su tiempo mínimo
      // vuelve a contar desde cero en cada entrada).
      if (activating) _guideLoaderSession++;
      // Lying-client analysis belongs to the guide. Restore the regular
      // preview mode when returning to the lash try-on screen.
      if (!activating) _cameraInverted180 = false;
      _eyesAligned = false;
      _faceFramed = false;
      _eyesClosedOk = false;
      _eyesOnGuideLine = false;
    });
    // La pestaña virtual taparía el borde natural durante el encuadre; el
    // mapeo numérico queda reservado para la captura.
    unawaited(_setHidingLashesForAlignmentGuide(activating));
    // La rotación del análisis sigue al botón "Invertir"; además se enlaza
    // la foto rápida por la misma sesión mientras la guía está abierta.
    unawaited(_applyInvertedFaceMode());
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
      _eyesOnGuideLine = false;
    });
    await _onSwitchCamera();
  }

  /// Selecciona el frame que recibe el asistente: el promedio de los
  /// cuadros de los últimos [_mappingAverageWindow] (quita el temblor de los
  /// puntos del párpado). Si no hay cuadros tan recientes, el último válido
  /// de hasta [_mappableFrameMaxAge]; si tampoco, el actual.
  TrackingFrame? _freezeMappingFrame() {
    final now = DateTime.now();
    final window = [
      for (final e in _recentMappable)
        if (now.difference(e.at) <= _mappingAverageWindow) e.frame,
    ];
    if (window.isNotEmpty)
      return EyeTrackingPhotoPipeline.averageFrames(window);
    final at = _lastMappableAt;
    final recent = at != null && now.difference(at) <= _mappableFrameMaxAge;
    return recent ? _lastMappableFrame : _frame;
  }

  void _evaluateAlignment(TrackingFrame frame) {
    if (!mounted || !_alignmentGuideActive) return;
    final size = MediaQuery.sizeOf(context);
    // Con "Clienta echada" la guía se DIBUJA girada 180°; evaluar el rostro
    // girado contra la guía sin girar es lo mismo y reusa una sola geometría.
    final status = EyeAlignmentGuide.evaluate(
      _cameraInverted180
          ? EyeTrackingPhotoPipeline.rotateFrame180(frame)!
          : frame,
      size,
    );

    if (_eyesAligned != status.ready ||
        _faceFramed != status.faceFramed ||
        _eyesClosedOk != status.eyesClosed ||
        _eyesOnGuideLine != status.eyesOnLine) {
      setState(() {
        _eyesAligned = status.ready;
        _faceFramed = status.faceFramed;
        _eyesClosedOk = status.eyesClosed;
        _eyesOnGuideLine = status.eyesOnLine;
      });
    }
  }

  // One stable geometry analysis drives the label and recommendation ranking.
  void _detectEyeTypeFromFrame(TrackingFrame frame) {
    if (_stableEyeAnalysis != null) return;
    final analysis = _sessionEyeAnalysis.add(frame, DateTime.now());
    if (analysis == null) {
      if (_analysisView.value.needsAdjustment !=
          _sessionEyeAnalysis.needsAdjustment) {
        setState(
          () => _analysisView.value = (
            analysis: null,
            needsAdjustment: _sessionEyeAnalysis.needsAdjustment,
          ),
        );
      }
      return;
    }
    final match = _eyeTypes
        ?.where(
          (item) =>
              item.name.trim().toLowerCase() ==
              (_consultation.shapeOverride ?? analysis.shape).catalogName
                  .toLowerCase(),
        )
        .firstOrNull;
    setState(() {
      _analysisView.value = (analysis: analysis, needsAdjustment: false);
      _rankedStyleIndices = null;
      _selectedEyeType = match;
    });
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
    // Los ojos tienen que estar sobre la línea horizontal de la guía (la que
    // se pinta en verde): si no, la foto sale con los ojos fuera de la
    // franja que se recorta. El aviso se va solo a los 2 s.
    if (!_eyesOnGuideLine) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Encuadre bien la posición de los ojos'),
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

  /// Botón redondo de la barra superior de la guía.
  Widget _guideRoundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  /// Acción secundaria de la guía (ícono + texto), a los lados de la captura.
  /// Verde = activa (p. ej. "Clienta echada").
  Widget _guideAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.actionGreen.withValues(alpha: 0.9)
                    : Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? Colors.white70 : Colors.white24,
                ),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Disparo manual. Atenuado hasta que los ojos están cerrados Y sobre la
  /// línea de la guía: antes de eso [_beginWorkAssistantFlow] no deja
  /// capturar.
  Widget _guideCaptureButton() {
    return GestureDetector(
      onTap: _beginWorkAssistantFlow,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _eyesClosedOk && _eyesOnGuideLine ? 1 : 0.4,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _eyesAligned ? const Color(0xFF2ECC71) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
          ),
          child: Icon(
            Icons.camera_alt_rounded,
            color: _eyesAligned ? Colors.white : AppColors.brandPrimary,
            size: 30,
          ),
        ),
      ),
    );
  }

  /// Mensaje de estado de la guía (qué falta para poder capturar).
  Widget _guideStatusPill() {
    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: _eyesAligned
              ? const Color(0xDD1FA24A)
              : const Color(0xDD0D5C41),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _eyesAligned
                  ? Icons.check_circle
                  : (!_faceFramed
                        ? Icons.crop_free
                        : !_eyesOnGuideLine
                        ? Icons.horizontal_rule
                        : Icons.remove_red_eye_outlined),
              color: Colors.white,
              size: 15,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _eyesAligned
                    ? 'Listo para capturar'
                    : (!_faceFramed
                          ? 'Encuadra el rostro dentro de la guía'
                          : !_eyesOnGuideLine
                          ? 'Encuadre bien la posición de los ojos'
                          : 'Ojos cerrados para ver la línea de pestañas'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
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
      showDragHandle: true,
      builder: (sheetContext) => ValueListenableBuilder(
        valueListenable: _analysisView,
        builder: (context, view, _) => EyeConsultationSheet(
          analysis: view.analysis,
          needsAdjustment: view.needsAdjustment,
          initial: _consultation,
          onApply: (selection) {
            final shape = selection.shapeOverride ?? _stableEyeAnalysis?.shape;
            final match = _eyeTypes
                ?.where(
                  (item) =>
                      item.name.trim().toLowerCase() ==
                      shape?.catalogName.toLowerCase(),
                )
                .firstOrNull;
            setState(() {
              _catalogUserInteracted = true;
              _consultation = selection;
              _selectedEyeType = match;
              _manualEyeRecommendation = null;
              _rankedStyleIndices = null;
              _selectedFilter = 0;
            });
            Navigator.of(sheetContext).pop();
          },
          onReanalyze: () {
            Navigator.of(sheetContext).pop();
            setState(() {
              _sessionEyeAnalysis.reset();
              _analysisView.value = (analysis: null, needsAdjustment: false);
              _consultation = LashConsultation(goal: _consultation.goal);
              _rankedStyleIndices = null;
              _manualEyeRecommendation = null;
              _selectedEyeType = null;
            });
          },
        ),
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
    if (_buildingRecipe || _switchingDesignModel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Espera a que se aplique el diseño.')),
      );
      return;
    }
    final effect = _selectedLashIndex < _availableLashPresets.length
        ? _availableLashPresets[_selectedLashIndex].name
        : _currentCarouselDesigns[_selectedLashIndex -
                  _availableLashPresets.length]
              .name;
    final recipe = _appliedRecipe;
    final notes = [
      'Efecto: $effect',
      _consultation.notes(_stableEyeAnalysis),
      if (recipe == null) 'Modelo: original',
      if (recipe != null) ...[
        'Largo: ${recipe.options?.length.name ?? LashCustomizationCatalog.designOptionAt(recipe.length)}',
        'Técnica: ${recipe.options?.technique.name ?? LashCustomizationCatalog.techOptionAt(recipe.technique)}',
        'Grosor: ${recipe.options?.thickness.name ?? LashCustomizationCatalog.thicknessOptionAt(recipe.thickness)}',
      ],
      if (recipe?.curlId != null && _selectedPreset != null)
        'Curvatura: ${_selectedPreset!.definition.curlOptions.where((o) => o.id == recipe!.curlId).firstOrNull?.name ?? recipe!.curlId}',
      if (_selectedColorId != 0 && _selectedPreset != null)
        'Color: ${_selectedPreset!.definition.options.color(_selectedColorId).name}',
    ].join(' | ');

    try {
      await ref
          .read(trackingRepositoryProvider)
          .create(
            clientId: client.id,
            eyeTypeId: _selectedEyeType?.id,
            designNotes: notes.runes.length > 255
                ? '${String.fromCharCodes(notes.runes.take(252))}…'
                : notes,
            tryOnRecipe: (_appliedCatalogStyle ?? _selectedPreset?.definition)
                ?.snapshot(
                  applied: recipe,
                  eyeAssessment: _consultation.toMap(_stableEyeAnalysis),
                  color: _selectedColorId,
                ),
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
    if (_switchingDesignModel) return;
    _catalogUserInteracted = true;
    _recipeTimer?.cancel();
    _recipeRequest++;
    setState(() {
      _selectedLashIndex = index;
      _appliedRecipe = null;
      _appliedCatalogStyle = null;
      _buildingRecipe = false;
      _resetRecipeSelection();
    });
    // Los presets locales van primero en el carrusel (ver build()), así que
    // los primeros _availableLashPresets.length índices son locales y el resto
    // corresponde a _currentCarouselDesigns (catálogo remoto).
    if (_useBundledCatEyeModel &&
        index < _availableLashPresets.length &&
        _availableLashPresets[index].originalCatEye) {
      // Keep the original Cat Eye entry and its current configurable behavior.
      unawaited(_switchLocalPreset(_availableLashPresets[index]));
      return;
    }
    if (index < _availableLashPresets.length) {
      setState(() => _buildingRecipe = true);
      unawaited(
        _applyRecipe(
          _availableLashPresets[index].definition.recipe(),
          _recipeRequest,
        ),
      );
      return;
    }
    final remoteIndex = index - _availableLashPresets.length;
    if (remoteIndex >= 0 && remoteIndex < _currentCarouselDesigns.length) {
      unawaited(_switchDesignModel(_currentCarouselDesigns[remoteIndex]));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Recommendations use the stable shape locked for this page session.
    // Explore always offers the complete catalog.
    final allAsync = ref.watch(designCatalogListProvider);
    final activeAsyncError = allAsync.error;
    if (activeAsyncError != null) {
      debugPrint('[lash-designs] error cargando catálogo: $activeAsyncError');
    }
    final allDesigns = allAsync.valueOrNull ?? const <CatalogItem>[];
    final compatibleDesigns = allDesigns.where((item) {
      final compatible = item.tipoOjoCompatible?.toUpperCase();
      return compatible == null ||
          compatible ==
              switch (_stableEyeAnalysis?.shape) {
                EyeShape.redondo => 'ROUND',
                EyeShape.rasgado => 'ELONGATED',
                EyeShape.almendrado => 'ALMOND',
                _ => '',
              };
    }).toList();
    final rawDesigns =
        _selectedFilter == 0 &&
            _stableEyeAnalysis != null &&
            compatibleDesigns.isNotEmpty
        ? compatibleDesigns
        : allDesigns;
    // Solo diseños con imagen entran al carrusel — se mantiene esta MISMA
    // lista (filtrada) en _currentCarouselDesigns para que el índice tocado
    // en el carrusel siga correspondiendo al diseño correcto en _onLashSelect.
    _currentCarouselDesigns =
        (_publishedPresets == null ? rawDesigns : <CatalogItem>[])
            .where((d) => d.hasImage)
            .toList(growable: false);
    final carousel = _currentCarouselDesigns;
    // Presets locales primero (siempre disponibles, no dependen del
    // catálogo remoto), después los del admin — ver _onLashSelect para el
    // mapeo de índice a diseño.
    final presetIndices = _recommendedPresetIndices;
    final carouselImagePaths = [
      ...presetIndices.map((i) => _availableLashPresets[i].thumbnailAsset),
      ...carousel.map((d) => d.imageUrl!),
    ];
    final carouselLabels = [
      ...presetIndices.map((i) => _availableLashPresets[i].name),
      ...carousel.map((d) => d.name),
    ];
    final safeLash = _selectedPreset != null
        ? presetIndices.indexOf(_selectedLashIndex)
        : presetIndices.length +
              _selectedLashIndex -
              _availableLashPresets.length;
    final selectedLabel =
        _selectedPreset?.name ??
        (safeLash >= 0 && safeLash < carouselLabels.length
            ? carouselLabels[safeLash]
            : 'Diseño');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_alignmentGuideActive) {
          if (!_capturingPhoto) _toggleAlignmentGuide();
          return;
        }
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
                          onCreated: () {
                            _catalogViewReady = true;
                            _maybeLoadPublishedCatalog();
                          },
                        ),
                      )
                    else
                      const ColoredBox(color: Colors.black),
                    // DEBUG: puntos de landmarks del párpado (verde =
                    // superior, la línea que el motor usa como pestaña; cruz
                    // amarilla = ancla; naranja = pestaña real detectada).
                    // Apagado con [_showLidLandmarkDebug] para poder juzgar
                    // el render de las pestañas sin nada encima.
                    if (_showLidLandmarkDebug && _perfFlutterOverlays)
                      Positioned.fill(
                        child: CustomPaint(
                          isComplex: true,
                          painter: LidLandmarkDebugPainter(
                            frames: _frameNotifier,
                            compact: true,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (!_alignmentGuideActive)
              ...EyeTrackingOverlay.buildSiblings(
                onBack: () => _goHome(context),
                status: _frame == null ? _status : null,
                title:
                    _analysisView.value.needsAdjustment &&
                        _consultation.shapeOverride == null &&
                        _stableEyeAnalysis == null
                    ? 'Ajusta la posición'
                    : _consultation.title(_stableEyeAnalysis),
                onEyeTypeTap: _showEyeTypeSheet,
                onSwitchCamera: () => unawaited(_onSwitchCamera()),
                onFlashTap: () {},
                onDesignTap: () => _onCategoryTap('design'),
                onTechniqueTap: () => _onCategoryTap('tech'),
                onEffectTap: () => _onCategoryTap('effect'),
                onThicknessTap: () => _onCategoryTap('thickness'),
                onCurlTap:
                    (_selectedPreset?.definition.curlOptions.isNotEmpty ??
                        false)
                    ? () => _onCategoryTap('curl')
                    : null,
                onColorTap: _hasColorChoices
                    ? () => _onCategoryTap('color')
                    : null,
                currentColor: Color(
                  0xFF000000 |
                      int.parse(
                        (_selectedColorHex ?? LashOptionCatalog.approvedBlack)
                            .substring(1),
                        radix: 16,
                      ),
                ),
                activeCategory: _activeCategory,
              ),
            if (!_alignmentGuideActive)
              EyeTrackingWorkAssistantButton(onTap: _toggleAlignmentGuide),

            // Chips y carrusel se ocultan con la guía de captura activa: ocupan
            // la misma franja inferior que el botón de disparo y el mensaje de
            // la guía, y durante la captura no se usan.
            if (!_alignmentGuideActive && _activeCategory == null)
              EyeTrackingFilterRow(
                recommendation: _eyeRecommendationSelector,
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
                          onSelect: (index) => _onLashSelect(
                            index < presetIndices.length
                                ? presetIndices[index]
                                : _availableLashPresets.length +
                                      index -
                                      presetIndices.length,
                          ),
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                ),
              ),
            if (_activeCategory != null && !_alignmentGuideActive)
              EyeTrackingDesignMenuBar(
                filters: EyeTrackingFilterRow(
                  recommendation: _eyeRecommendationSelector,
                  selectedFilter: _selectedFilter,
                  onSelect: _onFilterSelect,
                  embedded: true,
                ),
                designImages: _activeCategoryImages,
                designOptions: _activeCategoryOptions,
                selectedDesign:
                    _activeCategory == 'effect' ||
                        (_selectedLashIndex < _availableLashPresets.length &&
                            _appliedRecipe != null) ||
                        _buildingRecipe
                    ? _activeCategorySelectedIndex
                    : -1,
                helperText: _buildingRecipe
                    ? 'Aplicando…'
                    : _selectedLashIndex < _availableLashPresets.length
                    ? (_appliedRecipe == null ? 'Original' : 'Personalizado')
                    : 'Elige un estilo del probador',
                resetLabel: _selectedPreset?.originalCatEye == true
                    ? 'Restaurar original'
                    : 'Restablecer',
                onReset: _selectedLashIndex < _availableLashPresets.length
                    ? _restoreCurrentStyle
                    : null,
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
                onSelect: (index) {
                  setState(() => _showLashModal = false);
                  _onActiveCategorySelect(index);
                },
                onClose: () => setState(() => _showLashModal = false),
              ),
            if (!_showLashModal && !_alignmentGuideActive)
              EyeTrackingPremiumOjoButton(
                // Nombre del diseño de pestaña seleccionado en el carrusel
                // — antes se mostraba debajo de cada miniatura, ahora vive
                // acá (ver BottomCarousel más abajo, sin `labels`).
                label: selectedLabel,
              ),
            if (!_showLashModal && !_alignmentGuideActive)
              Positioned(
                top: 35,
                // A la izquierda del robot (esquina, right 12): 46 de ancho
                // del robot + 10 de separación.
                right: 68,
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
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.actionGreen.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(80),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(
                      Icons.bookmark_add_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),

            // ── Guía de posición de ojos: espera alineación antes de capturar ──
            if (_alignmentGuideActive && _perfFlutterOverlays)
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: EyePositionGuidePainter(
                          eyesClosed: _eyesClosedOk,
                          inverted: _cameraInverted180,
                          eyesOnLine: _eyesOnGuideLine,
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
            if (_alignmentGuideActive && !_capturingPhoto)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Row(
                      children: [
                        _guideRoundButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Salir del asistente',
                          onTap: _toggleAlignmentGuide,
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.smart_toy_outlined,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Asistente · Encuadre',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        // Mismo ancho que el botón de cerrar: título centrado.
                        const SizedBox(width: 44),
                      ],
                    ),
                  ),
                ),
              ),

            // Mensaje de la guía arriba de una sola fila de controles:
            // Voltear · Capturar · Clienta echada. Fuera del `IgnorePointer`
            // de la guía para que los botones reciban toques. La captura es
            // manual a propósito — ver [_toggleAlignmentGuide].
            if (_alignmentGuideActive && !_capturingPhoto)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _guideStatusPill(),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _guideAction(
                              icon: Icons.flip_camera_android,
                              label: 'Voltear',
                              onTap: () => unawaited(_switchCameraFromGuide()),
                            ),
                            _guideCaptureButton(),
                            // Con cualquiera de las dos cámaras — ver
                            // [_cameraInverted180].
                            _guideAction(
                              icon: Icons.airline_seat_flat,
                              label: 'Echada',
                              active: _cameraInverted180,
                              onTap: _toggleInvertedFaceMode,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
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
            // Loader al entrar al asistente (botón del robot): el mismo de la
            // cámara, con mínimo 2 s; "volver" cierra el asistente.
            if (_alignmentGuideActive && _guideLoaderSession > 0)
              PreviewStartupCover(
                key: ValueKey('guide-loader-$_guideLoaderSession'),
                ready: _frame != null,
                minVisible: const Duration(seconds: 2),
                message: 'Preparando el asistente…',
                onBack: _toggleAlignmentGuide,
              ),
            PreviewStartupCover(
              ready: _frame != null,
              error: _startupFailure,
              onBack: () => _goHome(context),
            ),
          ],
        ),
      ),
    );
  }
}
