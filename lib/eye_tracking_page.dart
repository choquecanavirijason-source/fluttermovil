import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderRepaintBoundary, PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'features/catalogo/domain/entities/catalog_item.dart';
import 'features/catalogo/presentation/providers/catalogo_provider.dart';
import 'features/clientes/domain/entities/client.dart';
import 'features/clientes/presentation/providers/clientes_provider.dart';
import 'features/tracking/data/tracking_repository_impl.dart';
import 'eye_tracking_mapping_painter.dart';
import 'eye_tracking_model.dart';
import 'eye_tracking_painter.dart';
import 'native_eye_tracking_service.dart';
import 'screens/widgets/bottom_carousel.dart';
import 'screens/widgets/eye_tracking_bottom_actions.dart';
import 'screens/widgets/eye_tracking_design_menu_bar.dart';
import 'screens/widgets/eye_tracking_filter_row.dart';
import 'screens/widgets/eye_tracking_lash_modal.dart';
import 'screens/widgets/eye_tracking_overlay.dart';
import 'screens/widgets/eye_tracking_work_assistant_button.dart';
import 'work_assistant_args.dart';

class EyeTrackingPage extends ConsumerStatefulWidget {
  const EyeTrackingPage({super.key});

  @override
  ConsumerState<EyeTrackingPage> createState() => _EyeTrackingPageState();
}

class _EyeTrackingPageState extends ConsumerState<EyeTrackingPage>
    with WidgetsBindingObserver {
  final NativeEyeTrackingService _service = NativeEyeTrackingService();
  final GlobalKey _previewCaptureKey = GlobalKey();

  StreamSubscription<TrackingFrame>? _sub;
  TrackingFrame? _frame;
  String _status = 'Inicializando...';

  Timer? _assistantFlowTimer;
  int? _assistantCountdown;
  bool _workAssistantOpening = false;

  static const List<String> _compatibleImages = [
    'assets/p1.png',
    'assets/p2.png',
    'assets/p3.png',
    'assets/p4.png',
    'assets/p5.png',
  ];

  /// Solo assets declarados en pubspec (p6 existe; p7/p8 no).
  static const List<String> _explorarImages = [
    'assets/p4.png',
    'assets/p5.png',
    'assets/p6.png',
  ];

  static const List<String> _designImages = [
    'assets/p1.png',
    'assets/p2.png',
    'assets/p3.png',
    'assets/p4.png',
  ];

  static const List<String> _designOptions = ['Medio', 'Ligero', 'Alto', 'Medio'];

  static const List<String> _techImages = [
    'assets/p1.png',
    'assets/p2.png',
    'assets/p3.png',
    'assets/p4.png',
  ];

  static const List<String> _techOptions = ['Clásica', 'Volumen', 'Mega Vol.', 'Híbrido'];

  static const List<String> _effectImages = [
    'assets/p1.png',
    'assets/p2.png',
    'assets/p3.png',
    'assets/p4.png',
  ];

  static const List<String> _effectOptions = ['Natural', 'Cat Eye', 'Muñeca', 'Abierto'];

  static const List<String> _thicknessImages = [
    'assets/p1.png',
    'assets/p2.png',
    'assets/p3.png',
    'assets/p4.png',
  ];

  static const List<String> _thicknessOptions = ['0.05mm', '0.07mm', '0.10mm', '0.15mm'];

  bool _showMapping = false;

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

  ui.Image? _lashTexture;
  String? _lashTextureAssetRequested;
  CatalogItem? _selectedEyeType;
  List<CatalogItem>? _eyeTypes;

  List<String> get _carouselImages =>
      _selectedFilter == 0 ? _compatibleImages : _explorarImages;

  Future<void> _loadLashTexture(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _lashTexture?.dispose();
        _lashTexture = frame.image;
      });
    } catch (e, st) {
      debugPrint('No se pudo cargar textura de pestañas ($assetPath): $e\n$st');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
    
    // Pre-carga tipos de ojo en segundo plano 
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final items = await ref.read(catalogListProvider(CatalogKind.eyeType).future);
        if (mounted) setState(() => _eyeTypes = items);
      } catch (_) {}
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

  Future<void> _restartCameraFromLifecycle() async {
    if (!mounted) return;
    setState(() => _previewSession++);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _sub = _service.trackingStream.listen(
      (frame) {
        if (!mounted) return;
        setState(() {
          _frame = frame;
          _status = frame.faceDetected ? 'Rostro detectado' : 'Sin rostro';
        });
      },
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
      (frame) {
        if (!mounted) return;
        setState(() {
          _frame = frame;
          _status = frame.faceDetected ? 'Rostro detectado' : 'Sin rostro';
        });
      },
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

    // Preview negro en frío: el PreviewView puede no tener superficie lista
    // cuando CameraX hace el primer bind. Re-enlazamos un par de veces ya
    // medido el AndroidView para forzar que el vídeo aparezca.
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      /*for (final ms in const [500, 700, 900]) {
        await Future<void>.delayed(Duration(milliseconds: ms));
        if (!mounted) return;
        await _service.refreshPreviewBind();
      }*/
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _assistantFlowTimer?.cancel();
    _sub?.cancel();
    _service.stopTracking();
    _lashTexture?.dispose();
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
      if (_selectedLashIndex >= _carouselImages.length) {
        _selectedLashIndex = 0;
      }
    });
  }

  void _onCategoryTap(String category) {
    setState(() {
      _activeCategory = category;
      _showTransparentMenu = false;
    });
  }

  List<String> get _activeCategoryImages {
    switch (_activeCategory) {
      case 'design':
        return _designImages;
      case 'tech':
        return _techImages;
      case 'effect':
        return _effectImages;
      case 'thickness':
        return _thicknessImages;
      default:
        return _designImages;
    }
  }

  List<String> get _activeCategoryOptions {
    switch (_activeCategory) {
      case 'design':
        return _designOptions;
      case 'tech':
        return _techOptions;
      case 'effect':
        return _effectOptions;
      case 'thickness':
        return _thicknessOptions;
      default:
        return _designOptions;
    }
  }

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

  /// Captura PNG del [RepaintBoundary]: vídeo nativo + [EyeTrackingPainter] (pestañas).
  Future<Uint8List?> _capturePreviewPng() async {
    if (!Platform.isAndroid) return null;
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return null;

    final boundary =
        _previewCaptureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.attached) return null;

    try {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      // Mínimo 2.0: en algunos dispositivos el DPR lógico es bajo y la captura sale borrosa.
      final captureRatio = dpr < 2.0 ? 2.0 : dpr;
      final image = await boundary.toImage(pixelRatio: captureRatio);
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bd?.buffer.asUint8List();
    } catch (e, st) {
      debugPrint('Captura preview ojos: $e\n$st');
      return null;
    }
  }

  Future<void> _resumeEyePreviewAfterAssistant() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    setState(() {
      _previewSession++;
      _showMapping = false;
    });

    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    await _service.startTracking();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    await _service.refreshPreviewBind();
    if (mounted) setState(() {});
  }

  Future<void> _finishWorkAssistantOpen() async {
    if (_workAssistantOpening) return;
    _workAssistantOpening = true;
    try {
      final png = await _capturePreviewPng();
      if (!mounted) return;
      if (png == null || png.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo capturar la vista con pestañas. Reintenta.',
              ),
            ),
          );
        }
        return;
      }

      await _service.stopTracking();
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted) return;

      await context.push(
        '/work-assistant',
        extra: WorkAssistantArgs(
          panelPngBytes: png,
          mirrorTopPanel: true,
        ),
      );
      if (!mounted) return;

      await _resumeEyePreviewAfterAssistant();
    } finally {
      _workAssistantOpening = false;
      if (mounted) setState(() {});
    }
  }

  
  void _beginWorkAssistantFlow() {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El asistente con captura solo está disponible en Android.'),
        ),
      );
      return;
    }
    if (_workAssistantOpening || _assistantCountdown != null) return;

    setState(() {
      _assistantCountdown = 3;
      _showMapping = true;
    });
    _assistantFlowTimer?.cancel();
    _assistantFlowTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final left = _assistantCountdown;
      if (left == null) {
        t.cancel();
        return;
      }
      if (left <= 1) {
        t.cancel();
        setState(() => _assistantCountdown = null);
        unawaited(_finishWorkAssistantOpen());
        return;
      }
      setState(() => _assistantCountdown = left - 1);
    });
  }

  String _categoryTitle(String? category) => switch (category) {
    'design'    => 'Diseño',
    'tech'      => 'Tecnología',
    'effect'    => 'Efecto',
    'thickness' => 'Grosor',
    _           => '',
  };

  void _showEyeTypeSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EyeTypePickerSheet(
        selected: _selectedEyeType,
        preloadedItems: _eyeTypes,
        onSelect: (item) {
          setState(() => _selectedEyeType = item);
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
              backgroundColor: const Color(0xFF0D5C41),
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SaveOptionsSheet(
        onListaTap: () {
          Navigator.of(context).pop();
          _showClientPickerSheet();
        },
      ),
    );
  }

  void _showClientPickerSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ClientPickerForSave(
        onSelect: (client) {
          Navigator.of(context).pop();
          _saveToClient(client);
        },
      ),
    );
  }

  Future<void> _saveToClient(Client client) async {
    final notes = [
      'Diseño: ${_designOptions[_selectedDesignIndex]}',
      'Tecnología: ${_techOptions[_selectedTechIndex]}',
      'Efecto: ${_effectOptions[_selectedEffectIndex]}',
      'Grosor: ${_thicknessOptions[_selectedThicknessIndex]}',
    ].join(' | ');

    try {
      await ref.read(trackingRepositoryProvider).create(
            clientId: client.id,
            eyeTypeId: _selectedEyeType?.id,
            designNotes: notes,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Diseño guardado para ${client.displayName}'),
        backgroundColor: const Color(0xFF0D5C41),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al guardar: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final carousel = _carouselImages;
    final safeLash =
        _selectedLashIndex < carousel.length ? _selectedLashIndex : 0;
    final lashAssetPath = carousel[safeLash];
    if (_lashTextureAssetRequested != lashAssetPath) {
      _lashTextureAssetRequested = lashAssetPath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _lashTextureAssetRequested == lashAssetPath) {
          unawaited(_loadLashTexture(lashAssetPath));
        }
      });
    }

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
                    if (Platform.isAndroid)
                      Positioned.fill(
                        child: _HybridCameraPreview(
                          key: ValueKey<String>('eye_preview_$_previewSession'),
                        ),
                      )
                    else
                      const ColoredBox(color: Colors.black),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          isComplex: true,
                          painter: EyeTrackingPainter(
                            frame: _frame,
                            filterIndex: _selectedFilter,
                            lashVariantIndex: safeLash,
                            lashTexture: _lashTexture,
                          ),
                        ),
                      ),
                    ),
                    if (_showMapping)
                      Positioned.fill(
                        child: CustomPaint(
                          isComplex: true,
                          painter: LashMappingPainter(frame: _frame),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ...EyeTrackingOverlay.buildSiblings(
              onBack: () => _goHome(context),
              status: _status,
              title: _selectedEyeType?.name ?? 'Almendrado',
              onEyeTypeTap: _showEyeTypeSheet,
              onSwitchCamera: () => _service.switchCamera(),
              onFlashTap: () {},
              onDesignTap: () => _onCategoryTap('design'),
              onTechniqueTap: () => _onCategoryTap('tech'),
              onEffectTap: () => _onCategoryTap('effect'),
              onThicknessTap: () => _onCategoryTap('thickness'),
              activeCategory: _activeCategory,
            ),
            EyeTrackingWorkAssistantButton(
              onTap: _beginWorkAssistantFlow,
            ),
          
            EyeTrackingFilterRow(
              selectedFilter: _selectedFilter,
              onSelect: _onFilterSelect,
            ),
            if (_showTransparentMenu && _activeCategory == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 70,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: BottomCarousel(
                    selectedLash: safeLash,
                    onSelect: (i) => setState(() => _selectedLashIndex = i),
                    imagePaths: carousel,
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
                categoryTitle: _categoryTitle(_activeCategory),
              ),
            if (_showLashModal)
              EyeTrackingLashModal(
                designImages: _activeCategoryImages,
                designOptions: _activeCategoryOptions,
                onClose: () => setState(() => _showLashModal = false),
              ),
            if (!_showLashModal)
              EyeTrackingPremiumOjoButton(onTap: () {}),
            if (!_showLashModal)
              Positioned(
                right: 16,
                bottom: 28,
                child: SafeArea(
                  top: false,
                  child: GestureDetector(
                    onTap: () {
                      final sessionClient =
                          ref.read(sessionClientProvider);
                      if (sessionClient != null) {
                        _confirmSaveForClient(sessionClient);
                      } else {
                        _showSaveDesignSheet();
                      }
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0D5C41),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.save_alt_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            if (_assistantCountdown != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_assistantCountdown',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 88,
                            fontWeight: FontWeight.w200,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Captura con filtro de pestañas',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet — selector de tipo de ojo
// ─────────────────────────────────────────────────────────────────────────────

class _EyeTypePickerSheet extends ConsumerWidget {
  final CatalogItem? selected;
  final ValueChanged<CatalogItem> onSelect;
  final List<CatalogItem>? preloadedItems;

  const _EyeTypePickerSheet({
    required this.selected,
    required this.onSelect,
    this.preloadedItems,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncItems = preloadedItems != null
    ? AsyncValue.data(preloadedItems!)
    : ref.watch(catalogListProvider(CatalogKind.eyeType));

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.75,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tipo de ojo',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: asyncItems.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error al cargar: $e')),
              data: (items) => ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final isSelected = selected?.id == item.id;
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    leading: item.hasImage
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: item.imageUrl!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, _) =>
                                  const _EyeTypeIcon(),
                            ),
                          )
                        : const _EyeTypeIcon(),
                    title: Text(
                      item.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: item.description != null
                        ? Text(
                            item.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                    trailing: isSelected
                        ? const Icon(Icons.check_circle,
                            color: Color(0xFF094732))
                        : null,
                    onTap: () => onSelect(item),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Guardar diseño — opciones
// ─────────────────────────────────────────────────────────────────────────────

class _SaveOptionsSheet extends StatelessWidget {
  final VoidCallback onListaTap;

  const _SaveOptionsSheet({required this.onListaTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Guardar diseño',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          _OptionTile(
            icon: Icons.people_outline,
            label: 'Lista de clientes',
            onTap: onListaTap,
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D5C41).withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF0D5C41).withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF0D5C41), size: 22),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF0D5C41),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Guardar diseño — selector de cliente
// ─────────────────────────────────────────────────────────────────────────────

class _ClientPickerForSave extends ConsumerStatefulWidget {
  final ValueChanged<Client> onSelect;

  const _ClientPickerForSave({required this.onSelect});

  @override
  ConsumerState<_ClientPickerForSave> createState() =>
      _ClientPickerForSaveState();
}

class _ClientPickerForSaveState extends ConsumerState<_ClientPickerForSave> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(clientSearchProvider.notifier).state = value;
    });
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final s = parts.first;
    return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final asyncClients = ref.watch(clientsListProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Seleccionar cliente',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Buscar cliente…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: asyncClients.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (clients) => clients.isEmpty
                  ? const Center(child: Text('Sin clientes encontrados'))
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: clients.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final c = clients[i];
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF0D5C41),
                            child: Text(
                              _initials(c.displayName),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          title: Text(
                            c.displayName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: c.phone.isNotEmpty
                              ? Text(c.phone)
                              : null,
                          trailing: const Icon(
                            Icons.check_circle_outline,
                            color: Color(0xFF0D5C41),
                          ),
                          onTap: () => widget.onSelect(c),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EyeTypeIcon extends StatelessWidget {
  const _EyeTypeIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF094732).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.remove_red_eye_outlined,
        color: Color(0xFF094732),
        size: 22,
      ),
    );
  }
}

/// Preview de cámara con **Hybrid Composition** (`initExpensiveAndroidView`).
/// Necesario para que el vídeo de CameraX (TextureView) se renderice; con
/// `AndroidView` simple el preview salía negro aunque el análisis sí corría.
class _HybridCameraPreview extends StatelessWidget {
  const _HybridCameraPreview({super.key});

  static const String _viewType = 'eye_tracking/camera_preview';

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        controller
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create();
        return controller;
      },
    );
  }
}
