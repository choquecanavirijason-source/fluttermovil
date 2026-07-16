import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/recommendation/eye_shape_analyzer.dart';
import 'core/theme/app_colors.dart';
import 'features/catalogo/domain/entities/catalog_item.dart';
import 'features/catalogo/presentation/providers/catalogo_provider.dart';
import 'features/clientes/domain/entities/client.dart';
import 'features/clientes/presentation/providers/clientes_provider.dart';
import 'features/tracking/data/tracking_repository_impl.dart';
import 'eye_tracking_mapping_painter.dart';
import 'eye_tracking_model.dart';
import 'native_eye_tracking_service.dart';
import 'screens/widgets/bottom_carousel.dart';
import 'screens/widgets/eye_tracking_bottom_actions.dart';
import 'screens/widgets/eye_tracking_design_menu_bar.dart';
import 'screens/widgets/eye_tracking_filter_row.dart';
import 'screens/widgets/eye_tracking_lash_modal.dart';
import 'screens/widgets/eye_tracking_overlay.dart';
import 'screens/widgets/eye_tracking_work_assistant_button.dart';
import 'recommendation_args.dart';
import 'work_assistant_args.dart';
// import 'core/storage/model_cache_service.dart'; // TODO: reactivar con Kotlin 3D

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

  bool _workAssistantOpening = false;
  bool _openingRecommendation = false;

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

  /// Rutas locales (archivo) de los .glb de pestañas, resueltas una única vez
  /// por ciclo de vida de este State (ver [_resolveEyeModelPaths]). Viajan
  /// como `creationParams` del PlatformView (ver [_HybridCameraPreview]) para
  /// que Kotlin cargue el modelo de forma síncrona en la misma llamada nativa
  /// que crea el SceneView — nunca por un MethodChannel disparado con delays.
  String? _leftModelPath;
  String? _rightModelPath;

  CatalogItem? _selectedEyeType;
  List<CatalogItem>? _eyeTypes;

  /// true una vez que el usuario elige el tipo de ojo manualmente desde la
  /// hoja de selección; a partir de ahí deja de sobreescribirse con el
  /// resultado del escaneo automático.
  bool _eyeTypeSetManually = false;

  /// Path local del .glb descargado para el item seleccionado (null = sin modelo).
  String? _selectedModel3dPath;

  /// true mientras ModelCacheService resuelve la descarga del .glb.
  bool _isModel3dLoading = false;

  /// true mientras se muestra la guía de alineación (esperando que el usuario
  /// ubique sus ojos en el marco antes de capturar).
  bool _alignmentGuideActive = false;

  /// true cuando ambos ojos están dentro de la zona objetivo (marcadores en verde).
  bool _eyesAligned = false;

  /// Momento en que se detectó alineación continua (para exigir estabilidad breve).
  DateTime? _alignedSince;

  /// Duración mínima que los ojos deben permanecer alineados antes de disparar la captura.
  static const Duration _alignmentHoldDuration = Duration(milliseconds: 900);

  /// Modelos 3D (.glb) anclados nativamente por Kotlin/SceneView a cada ojo.
  static const String _cateyeLeftModelAsset =
      'assets/modelos/cateye/cateyeleft.glb';
  static const String _cateyeRightModelAsset =
      'assets/modelos/cateye/cateyeright.glb';

  List<String> get _carouselImages =>
      _selectedFilter == 0 ? _compatibleImages : _explorarImages;

  /// Copia un asset de Flutter (bundle) a un archivo local, ya que el lado
  /// nativo (SceneView) carga los .glb desde una ruta de archivo real.
  Future<String> _extractAssetToFile(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${assetPath.split('/').last}');
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
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
      final leftPath = await _extractAssetToFile(_cateyeLeftModelAsset);
      final rightPath = await _extractAssetToFile(_cateyeRightModelAsset);
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
    WidgetsBinding.instance.addObserver(this);
    unawaited(_resolveEyeModelPaths());
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
        if (_alignmentGuideActive) _evaluateAlignment(frame);
        _detectEyeTypeFromFrame(frame);
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
    // El GLB ya no requiere recarga aquí: _leftModelPath/_rightModelPath
    // siguen resueltos en el State, y el nuevo AndroidView (creado con la
    // key `eye_preview_$_previewSession`) los recibe como creationParams al
    // crearse — Kotlin los carga en el mismo create(), sin timers.
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
        if (_alignmentGuideActive) _evaluateAlignment(frame);
        _detectEyeTypeFromFrame(frame);
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

    // La carga del GLB ya no depende de un retry-loop temporizado: viaja
    // como creationParams del PlatformView (ver _HybridCameraPreview), así
    // que Kotlin la ejecuta de forma síncrona en el mismo create() que
    // adjunta el SceneView nuevo.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _service.stopTracking();
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

  Future<void> _resumeEyePreviewAfterAssistant() async {
    // Espera extra para que el plugin `camera` libere el hardware completamente.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    setState(() {
      _previewSession++;
      _showMapping = false;
    });

    // Tiempo para que el nuevo AndroidView llame a attachPreview().
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

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
      // 1. Activa las líneas de medición y espera un frame para que se pinten.
      setState(() => _showMapping = true);
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;

      // 2. Captura el overlay (pestañas + líneas de medición) ANTES de detener MediaPipe.
      final overlayBytes = await _captureLashOverlay();

      // 3. Detiene MediaPipe y espera que libere el sensor.
      await _service.stopTracking();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;

      // 4. Toma foto real con la cámara Flutter y compone con el overlay.
      final finalPhoto = await _captureAndComposite(overlayBytes);
      if (!mounted) return;

      await context.push(
        '/work-assistant',
        extra: WorkAssistantArgs(panelPngBytes: finalPhoto),
      );
      if (!mounted) return;

      await _resumeEyePreviewAfterAssistant();
    } finally {
      _workAssistantOpening = false;
      if (mounted) setState(() {});
    }
  }

  /// Abre el probador con IA: mismo pipeline de captura que el asistente de
  /// trabajo (overlay + foto real compuesta, con las líneas de medición
  /// horneadas en la imagen), pero navega a `/recomendacion` con el análisis
  /// de forma de ojo ya calculado.
  Future<void> _openRecommendation() async {
    if (_openingRecommendation || _workAssistantOpening) return;
    _openingRecommendation = true;
    try {
      setState(() => _showMapping = true);
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;

      final overlayBytes = await _captureLashOverlay();
      final analysis = EyeShapeAnalyzer.analyze(_frame);

      await _service.stopTracking();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;

      final finalPhoto = await _captureAndComposite(overlayBytes);
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

  /// Captura el overlay Flutter (pestañas PNG) mientras MediaPipe sigue activo.
  /// Las áreas de cámara nativa quedan transparentes en el PNG resultante.
  Future<Uint8List?> _captureLashOverlay() async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return null;
    final boundary = _previewCaptureKey.currentContext
        ?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.attached) return null;
    try {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final ratio = dpr < 2.0 ? 2.0 : dpr;
      final image = await boundary.toImage(pixelRatio: ratio);
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bd?.buffer.asUint8List();
    } catch (e) {
      debugPrint('captureLashOverlay: $e');
      return null;
    }
  }

  /// Abre la cámara Flutter brevemente, toma foto de la cara y la compone
  /// con el overlay de pestañas. Devuelve la región de ojos recortada.
  Future<Uint8List?> _captureAndComposite(Uint8List? overlayBytes) async {
    CameraController? ctrl;
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted || !mounted) return overlayBytes;

      final cameras = await availableCameras();
      if (cameras.isEmpty || !mounted) return overlayBytes;

      final target = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      ctrl = CameraController(target, ResolutionPreset.medium, enableAudio: false);
      await ctrl.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final xfile = await ctrl.takePicture();
      final faceBytes = await File(xfile.path).readAsBytes();

      return _compositeAndCrop(faceBytes, overlayBytes);
    } catch (e) {
      debugPrint('captureAndComposite: $e');
      return overlayBytes;
    } finally {
      await ctrl?.dispose();
    }
  }

  /// Compone la foto de cara con el overlay de pestañas (alpha blend) y recorta
  /// la zona de ojos (franja central y=22%–64%).
  static Uint8List _compositeAndCrop(Uint8List faceRaw, Uint8List? overlayRaw) {
    var faceImg = img.decodeImage(faceRaw);
    if (faceImg == null) return faceRaw;

    // Aplica la rotación EXIF (la foto suele guardarse apaisada + tag de giro).
    faceImg = img.bakeOrientation(faceImg);

    // La cámara frontal guarda la foto sin espejo; la invertimos para que
    // coincida con el overlay que se renderizó sobre el preview espejado.
    var canvas = img.flipHorizontal(faceImg);

    if (overlayRaw != null) {
      final overlayImg = img.decodeImage(overlayRaw);
      if (overlayImg != null) {
        // El preview usa BoxFit.cover: la pantalla solo muestra un recorte
        // centrado de la foto. Recortamos la foto a la proporción del overlay
        // (pantalla) ANTES de componer; si no, las pestañas quedan corridas.
        final overlayAspect = overlayImg.width / overlayImg.height;
        final faceAspect = canvas.width / canvas.height;
        int cw = canvas.width, ch = canvas.height, cx = 0, cy = 0;
        if (faceAspect > overlayAspect) {
          // Foto más ancha que la pantalla: recorta los lados.
          cw = (canvas.height * overlayAspect).round();
          cx = ((canvas.width - cw) / 2).round();
        } else if (faceAspect < overlayAspect) {
          // Foto más alta que la pantalla: recorta arriba/abajo.
          ch = (canvas.width / overlayAspect).round();
          cy = ((canvas.height - ch) / 2).round();
        }
        canvas = img.copyCrop(canvas, x: cx, y: cy, width: cw, height: ch);

        // Ahora ambas tienen la misma proporción: escala 1:1 sin deformar.
        final overlayScaled = img.copyResize(
          overlayImg,
          width: canvas.width,
          height: canvas.height,
          interpolation: img.Interpolation.linear,
        );
        img.compositeImage(canvas, overlayScaled, blend: img.BlendMode.alpha);
      }
    }

    // Recorta la zona de los ojos.
    final y = (canvas.height * 0.22).round();
    final h = (canvas.height * 0.42).round();
    final cropped =
        img.copyCrop(canvas, x: 0, y: y, width: canvas.width, height: h);
    final rotated = img.copyRotate(cropped, angle: 180);
    return Uint8List.fromList(img.encodePng(rotated));
  }

  void _startAlignmentGuide() {
    if (_workAssistantOpening || _alignmentGuideActive) return;
    setState(() {
      _alignmentGuideActive = true;
      _eyesAligned = false;
      _alignedSince = null;
    });
  }

  /// Centro de un ojo: usa el iris (más preciso) si está disponible,
  /// si no, el centroide de los puntos de contorno del ojo.
  EyePoint? _eyeAnchor(List<EyePoint> contour, EyePoint? iris) {
    if (iris != null) return iris;
    if (contour.isEmpty) return null;
    double sx = 0, sy = 0;
    for (final p in contour) {
      sx += p.x;
      sy += p.y;
    }
    return EyePoint(x: sx / contour.length, y: sy / contour.length);
  }

  /// Misma transformación imagen→pantalla que usa [LashMappingPainter]
  /// (BoxFit.cover), para comparar ojos detectados contra la posición de
  /// la guía dibujada en pantalla.
  bool _computeEyesAligned(TrackingFrame frame, Size canvasSize) {
    if (!frame.faceDetected) return false;
    final iw = frame.imageWidth.toDouble();
    final ih = frame.imageHeight.toDouble();
    if (iw <= 0 || ih <= 0) return false;

    final a = _eyeAnchor(frame.leftEye, frame.leftIris);
    final b = _eyeAnchor(frame.rightEye, frame.rightIris);
    if (a == null || b == null) return false;

    final sx = canvasSize.width / iw;
    final sy = canvasSize.height / ih;
    final scale = math.max(sx, sy);
    final dx = (canvasSize.width - iw * scale) / 2;
    final dy = (canvasSize.height - ih * scale) / 2;
    Offset toCanvas(EyePoint p) => Offset(p.x * scale + dx, p.y * scale + dy);

    final pa = toCanvas(a);
    final pb = toCanvas(b);
    // Asigna cada ojo detectado a la guía más cercana en X, sin asumir
    // a qué lado de la pantalla corresponde "leftEye"/"rightEye".
    final detectedLeft = pa.dx <= pb.dx ? pa : pb;
    final detectedRight = pa.dx <= pb.dx ? pb : pa;

    // Misma franja que _EyePositionGuidePainter y _compositeAndCrop.
    final bandTop = canvasSize.height * 0.22;
    final bandHeight = canvasSize.height * 0.42;
    final eyeY = bandTop + bandHeight / 2;
    final guideLeft = Offset(canvasSize.width * 0.32, eyeY);
    final guideRight = Offset(canvasSize.width * 0.68, eyeY);
    final tolerance = canvasSize.width * 0.11;

    return (detectedLeft - guideLeft).distance <= tolerance &&
        (detectedRight - guideRight).distance <= tolerance;
  }

  void _evaluateAlignment(TrackingFrame frame) {
    if (!mounted || !_alignmentGuideActive) return;
    final size = MediaQuery.sizeOf(context);
    final aligned = _computeEyesAligned(frame, size);
    final now = DateTime.now();

    if (aligned) {
      _alignedSince ??= now;
      if (now.difference(_alignedSince!) >= _alignmentHoldDuration) {
        setState(() {
          _alignmentGuideActive = false;
          _eyesAligned = false;
          _alignedSince = null;
        });
        _beginWorkAssistantFlow();
        return;
      }
      if (!_eyesAligned) setState(() => _eyesAligned = true);
    } else {
      _alignedSince = null;
      if (_eyesAligned) setState(() => _eyesAligned = false);
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
    unawaited(_finishWorkAssistantOpen());
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
        backgroundColor: AppColors.actionGreen,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al guardar: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  void _onLashSelect(int index, List<CatalogItem> items) {
    setState(() => _selectedLashIndex = index);

    // TODO: reactivar cuando Kotlin esté listo para el renderizado 3D nativo
    // if (index >= items.length) return;
    // final item = items[index];
    // if (!item.has3dModel) return;
    // setState(() => _isModel3dLoading = true);
    // try {
    //   final path = await ref
    //       .read(modelCacheServiceProvider)
    //       .getModelPath(item.model3dUrl!);
    //   if (path != null) {
    //     debugPrint('[ModelCache] ✅ Modelo 3D descargado: $path');
    //     await _service.set3DModelPath(path);
    //   } else {
    //     debugPrint('[ModelCache] ⚠️  getModelPath devolvió null — verifica la URL');
    //   }
    //   if (mounted) setState(() => _selectedModel3dPath = path);
    // } finally {
    //   if (mounted) setState(() => _isModel3dLoading = false);
    // }
  }

  @override
  Widget build(BuildContext context) {
    final lashItems = ref
        .watch(filteredCatalogProvider(CatalogKind.lashDesign))
        .valueOrNull ?? [];
    final carousel = _carouselImages;
    final safeLash =
        _selectedLashIndex < carousel.length ? _selectedLashIndex : 0;

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
                        child: _HybridCameraPreview(
                          key: ValueKey<String>('eye_preview_$_previewSession'),
                          leftModelPath: _leftModelPath!,
                          rightModelPath: _rightModelPath!,
                        ),
                      )
                    else
                      const ColoredBox(color: Colors.black),
                    // Las pestañas ya no se dibujan como overlay PNG en Flutter:
                    // se renderizan de forma nativa por Kotlin (CameraXManager/
                    // SceneView-Filament) como modelos 3D (.glb) anclados a cada
                    // ojo, dentro de _HybridCameraPreview.
                    // TODO: activar cuando Kotlin esté listo para renderizar el .glb
                    // if (_selectedModel3dPath != null)
                    //   Positioned.fill(
                    //     child: _Model3dAnchor(
                    //       localPath: _selectedModel3dPath!,
                    //       transform: Matrix4.identity(),
                    //     ),
                    //   ),
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
              title: _selectedEyeType?.name ?? '',
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
              onTap: _startAlignmentGuide,
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
                    onSelect: (i) => _onLashSelect(i, lashItems),
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
              EyeTrackingPremiumOjoButton(
                onTap: () => unawaited(_openRecommendation()),
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
                        painter: _EyePositionGuidePainter(aligned: _eyesAligned),
                      ),
                      Positioned(
                        bottom: 60,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 36),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: _eyesAligned
                                  ? const Color(0xDD1FA24A)
                                  : const Color(0xDD0D5C41),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _eyesAligned
                                  ? '¡Perfecto! Quédate así…'
                                  : 'Ubica tus ojos dentro del marco',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Indicador de descarga del .glb (se oculta en cuanto termina).
            if (_isModel3dLoading)
              Positioned(
                bottom: 140,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Cargando modelo 3D…',
                          style: TextStyle(color: Colors.white, fontSize: 13),
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
// Guía de posición de ojos (se muestra al abrir el asistente, antes de la foto)
// ─────────────────────────────────────────────────────────────────────────────

class _EyePositionGuidePainter extends CustomPainter {
  final bool aligned;

  const _EyePositionGuidePainter({required this.aligned});

  @override
  void paint(Canvas canvas, Size size) {
    // Misma franja que recorta _compositeAndCrop (y=22%–64% del alto).
    final bandRect = Rect.fromLTWH(
      size.width * 0.08,
      size.height * 0.22,
      size.width * 0.84,
      size.height * 0.42,
    );
    final rrect = RRect.fromRectAndRadius(bandRect, const Radius.circular(24));

    // Oscurece todo excepto la franja de ojos.
    final outerPath = Path()..addRect(Offset.zero & size);
    final innerPath = Path()..addRRect(rrect);
    final maskPath =
        Path.combine(PathOperation.difference, outerPath, innerPath);
    canvas.drawPath(maskPath, Paint()..color = const Color(0x99000000));

    // Contorno de la franja: blanco por defecto, verde cuando el usuario
    // se posiciona correctamente. Sin marcadores de ojos independientes.
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = aligned ? const Color(0xFF2ECC71) : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = aligned ? 3.5 : 2.5,
    );
  }

  @override
  bool shouldRepaint(_EyePositionGuidePainter old) => old.aligned != aligned;
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
                              errorWidget: (_, _, _) =>
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
          color: AppColors.actionGreen.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.actionGreen.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.actionGreen, size: 22),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.actionGreen,
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
                            backgroundColor: AppColors.actionGreen,
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
                            color: AppColors.actionGreen,
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

// ─────────────────────────────────────────────────────────────────────────────
// Visor 3D — anclaje y placeholder
// ─────────────────────────────────────────────────────────────────────────────

/// Ancla el modelo 3D al plano AR mediante una [Matrix4] de transformación.
///
/// Cuando se integren los landmarks del tracking ([TrackingFrame]) actualiza
/// [transform] con la traslación y escala derivadas de los puntos del iris o
/// los párpados para que el modelo siga el movimiento de la cara en tiempo real.
class _Model3dAnchor extends StatelessWidget {
  const _Model3dAnchor({
    required this.localPath,
    required this.transform,
  });

  final String localPath;
  final Matrix4 transform;

  @override
  Widget build(BuildContext context) {
    return Transform(
      transform: transform,
      alignment: Alignment.center,
      child: _Model3dViewer(localPath: localPath),
    );
  }
}

/// Placeholder del visor de modelos 3D (.glb / .gltf).
///
/// Reemplaza el [SizedBox.expand] con el widget del paquete elegido:
///
/// ── Opción A · model_viewer_plus (WebView, Android/iOS/Web) ─────────────────
///   pubspec:  model_viewer_plus: ^1.x.x
///   widget:   ModelViewer(src: 'file://$localPath', autoRotate: false)
///
/// ── Opción B · flutter_3d_controller (nativo Android/iOS) ──────────────────
///   pubspec:  flutter_3d_controller: ^1.x.x
///   widget:   Flutter3DViewer(src: localPath)
/// ────────────────────────────────────────────────────────────────────────────
class _Model3dViewer extends StatelessWidget {
  const _Model3dViewer({required this.localPath});

  final String localPath;

  @override
  Widget build(BuildContext context) {
    // TODO: inyectar visor 3D — reemplaza este SizedBox con el widget del paquete.
    //
    // model_viewer_plus:
    //   return ModelViewer(src: 'file://$localPath', autoRotate: false);
    //
    // flutter_3d_controller:
    //   return Flutter3DViewer(src: localPath);
    return const SizedBox.expand();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preview de cámara nativa
// ─────────────────────────────────────────────────────────────────────────────

/// Preview de cámara con **Hybrid Composition** (`initExpensiveAndroidView`).
/// Necesario para que el vídeo de CameraX (TextureView) se renderice; con
/// `AndroidView` simple el preview salía negro aunque el análisis sí corría.
///
/// [leftModelPath]/[rightModelPath] viajan como `creationParams`: Kotlin los
/// recibe en el mismo `create()` que instancia el SceneView y carga el GLB
/// ahí mismo, de forma síncrona — así la recreación de este PlatformView
/// (al volver a la pantalla, o al forzar `_previewSession++`) nunca depende
/// de que Flutter dispare una segunda llamada por MethodChannel a tiempo.
class _HybridCameraPreview extends StatelessWidget {
  const _HybridCameraPreview({
    super.key,
    required this.leftModelPath,
    required this.rightModelPath,
  });

  final String leftModelPath;
  final String rightModelPath;

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
          creationParams: <String, dynamic>{
            'leftModelPath': leftModelPath,
            'rightModelPath': rightModelPath,
          },
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
