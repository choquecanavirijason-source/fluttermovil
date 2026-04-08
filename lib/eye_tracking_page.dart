import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
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

class EyeTrackingPage extends StatefulWidget {
  const EyeTrackingPage({super.key});

  @override
  State<EyeTrackingPage> createState() => _EyeTrackingPageState();
}

class _EyeTrackingPageState extends State<EyeTrackingPage> {
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

  int _selectedFilter = 0;
  int _selectedLashIndex = 0;
  int _selectedDesignIndex = 2;
  bool _showTransparentMenu = true;
  bool _showDesignMenu = false;
  bool _showLashModal = false;

  /// Fuerza recreación del [AndroidView] al volver de otra pantalla que usa la cámara.
  int _previewSession = 0;

  ui.Image? _lashTexture;
  String? _lashTextureAssetRequested;

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
    _start();
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
  }

  @override
  void dispose() {
    _assistantFlowTimer?.cancel();
    _sub?.cancel();
    _service.stopTracking();
    _lashTexture?.dispose();
    super.dispose();
  }

  void _goHome(BuildContext context) {
    if (!context.mounted) return;
    context.go('/home');
  }

  void _onFilterSelect(int index) {
    setState(() {
      _selectedFilter = index;
      _showTransparentMenu = true;
      _showDesignMenu = false;
      if (_selectedLashIndex >= _carouselImages.length) {
        _selectedLashIndex = 0;
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
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    setState(() => _previewSession++);

    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 650));
          if (!mounted) return;
          await _service.startTracking();
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          await _service.refreshPreviewBind();
          await Future<void>.delayed(const Duration(milliseconds: 220));
          if (!mounted) return;
          setState(() {});
        });
      });
    });
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

    setState(() => _assistantCountdown = 3);
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
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
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
                        child: AndroidView(
                          key: ValueKey<String>('eye_preview_$_previewSession'),
                          viewType: 'eye_tracking/camera_preview',
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
                  ],
                ),
              ),
            ),
            ...EyeTrackingOverlay.buildSiblings(
              onBack: () => _goHome(context),
              status: _status,
              onSwitchCamera: () => _service.switchCamera(),
              onFlashTap: () {},
              onDesignTap: () => setState(() {
                _showDesignMenu = true;
                _showTransparentMenu = false;
              }),
              onTechniqueTap: () {},
              onEffectTap: () {},
              onThicknessTap: () {},
            ),
            EyeTrackingWorkAssistantButton(
              onTap: _beginWorkAssistantFlow,
            ),
            EyeTrackingFilterRow(
              selectedFilter: _selectedFilter,
              onSelect: _onFilterSelect,
            ),
            if (_showTransparentMenu && !_showDesignMenu)
              Positioned(
                left: 0,
                right: 0,
                bottom: 90,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: BottomCarousel(
                    selectedLash: safeLash,
                    onSelect: (i) => setState(() => _selectedLashIndex = i),
                    imagePaths: carousel,
                  ),
                ),
              ),
            if (_showDesignMenu)
              EyeTrackingDesignMenuBar(
                designImages: _designImages,
                designOptions: _designOptions,
                selectedDesign: _selectedDesignIndex,
                onSelectDesign: (i) =>
                    setState(() => _selectedDesignIndex = i),
                onOpenGrid: () => setState(() => _showLashModal = true),
              ),
            if (_showLashModal)
              EyeTrackingLashModal(
                designImages: _designImages,
                designOptions: _designOptions,
                onClose: () => setState(() => _showLashModal = false),
              ),
            if (!_showLashModal)
              EyeTrackingPremiumOjoButton(onTap: () {}),
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
