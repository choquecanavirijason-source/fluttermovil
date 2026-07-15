import 'dart:async' show Timer, unawaited;
import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:Probador/core/theme/app_colors.dart';
import 'package:Probador/work_assistant_args.dart';

/// Asistente de verificación: mitad superior foto de referencia (captura automática a los 3 s);
/// mitad inferior cámara en vivo.
class WorkAssistantScreen extends StatefulWidget {
  const WorkAssistantScreen({super.key, this.args});

  final WorkAssistantArgs? args;

  @override
  State<WorkAssistantScreen> createState() => _WorkAssistantScreenState();
}

class _WorkAssistantScreenState extends State<WorkAssistantScreen> {
  static const String _defaultRefAsset = 'assets/chica.png';

  Uint8List? _referenceBytes;
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;

  bool _analyzing = false;

  String _assistantMessage =
      'La pestaña está caída, por favor revisa la elevación…';

  bool _flashOn = false;
  int _cameraIndex = 0;
  final DateTime _sessionStart = DateTime.now();
  Timer? _tickTimer;
  int _elapsedSeconds = 0;

  /// Evita doble atrás mientras se libera la cámara (plugin camera vs CameraX nativo).
  bool _exitInProgress = false;

  /// Oculta [CameraPreview] antes de [dispose] para evitar BufferQueue abandonado (CameraX vs PlatformView).
  bool _detachingPluginCamera = false;

  /// Foto del panel superior (capturada automáticamente al iniciar la cámara).
  Uint8List? _panelPngFromCamera;

  /// Indica que se está tomando la foto automática.
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    final pref = widget.args?.panelPngBytes;
    if (pref != null && pref.isNotEmpty) {
      _panelPngFromCamera = pref;
      _referenceBytes = pref;
    }
    unawaited(_initCamera());
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds = DateTime.now().difference(_sessionStart).inSeconds;
      });
    });
  }

  Future<void> _loadAsset(String path) async {
    final data = await rootBundle.load(path);
    if (!mounted) return;
    setState(() {
      _referenceBytes = data.buffer.asUint8List();
    });
  }

  /// Android: [bgra8888] + [ResolutionPreset.medium] reduce avisos del allocador (qdgralloc) en Qualcomm/Xiaomi.
  /// Si falla, se reintenta con [yuv420].
  Future<CameraController> _createAssistantCamera(CameraDescription camera) async {
    Future<CameraController> openWith(ImageFormatGroup format) async {
      final c = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: format,
      );
      try {
        await c.initialize();
        return c;
      } catch (e) {
        await c.dispose();
        rethrow;
      }
    }

    if (Platform.isAndroid) {
      try {
        return await openWith(ImageFormatGroup.bgra8888);
      } catch (e) {
        debugPrint('WorkAssistant camera bgra8888→yuv420: $e');
        return await openWith(ImageFormatGroup.yuv420);
      }
    }
    return await openWith(ImageFormatGroup.bgra8888);
  }

  Future<void> _initCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted || !mounted) return;

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) return;

      final front = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );
      _cameraIndex = _cameras!.indexOf(front);

      final ctrl = await _createAssistantCamera(front);
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _cameraController = ctrl);
      // Solo auto-captura si no se recibió foto desde el probador.
      if (_panelPngFromCamera == null) unawaited(_captureForTopPanel());
    } catch (e) {
      debugPrint('WorkAssistant camera: $e');
    }
  }

  /// Toma una foto con la cámara y la muestra en el panel superior (región de ojos).
  Future<void> _captureForTopPanel() async {
    if (_isCapturing) return;
    if (mounted) setState(() => _isCapturing = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      final c = _cameraController;
      if (c == null || !c.value.isInitialized) return;
      final xfile = await c.takePicture();
      if (!mounted) return;
      final raw = await File(xfile.path).readAsBytes();
      final cropped = _cropEyeRegion(raw);
      if (!mounted) return;
      setState(() {
        _panelPngFromCamera = cropped;
        _referenceBytes = cropped;
      });
    } catch (e) {
      debugPrint('captureForTopPanel: $e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// Recorta la región de los ojos: franja central-superior de la imagen.
  static Uint8List _cropEyeRegion(Uint8List raw) {
    final src = img.decodeImage(raw);
    if (src == null) return raw;
    final y = (src.height * 0.22).round();
    final h = (src.height * 0.42).round();
    final cropped = img.copyCrop(src, x: 0, y: y, width: src.width, height: h);
    return Uint8List.fromList(img.encodePng(cropped));
  }

  Future<void> _captureAndAnalyze() async {
    await _captureForTopPanel();
    if (!mounted || _referenceBytes == null) return;
    await _runAnalysis();
  }

  Future<void> _switchCamera() async {
    if (_detachingPluginCamera || _exitInProgress) return;
    if (_cameras == null || _cameras!.length < 2) return;
    final ctrl = _cameraController;
    if (ctrl == null) return;
    try {
      await ctrl.dispose();
    } catch (_) {}
    _cameraIndex = (_cameraIndex + 1) % _cameras!.length;
    CameraController? next;
    try {
      next = await _createAssistantCamera(_cameras![_cameraIndex]);
    } catch (e) {
      debugPrint('WorkAssistant switch camera: $e');
      return;
    }
    if (!mounted) {
      await next.dispose();
      return;
    }
    setState(() => _cameraController = next);
  }

  Future<void> _toggleFlash() async {
    if (_detachingPluginCamera) return;
    final c = _cameraController;
    if (c == null) return;
    try {
      _flashOn = !_flashOn;
      await c.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('flash: $e');
    }
  }

  Future<void> _pickReferenceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.auto_awesome, color: Colors.amberAccent),
              title: const Text(
                'Referencia de ejemplo',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_loadAsset(_defaultRefAsset));
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white54),
              title: const Text(
                'Próx.: elegir desde galería (image_picker).',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  static int? _computeVisualSimilarity(Uint8List? a, Uint8List? b) {
    if (a == null || b == null) return null;
    final img.Image? ia = img.decodeImage(a);
    final img.Image? ib = img.decodeImage(b);
    if (ia == null || ib == null) return null;

    const int side = 64;
    final ra = img.copyResize(ia, width: side, height: side);
    final rb = img.copyResize(ib, width: side, height: side);

    double sumSq = 0;
    final int n = side * side;
    for (int y = 0; y < side; y++) {
      for (int x = 0; x < side; x++) {
        final pa = ra.getPixel(x, y);
        final pb = rb.getPixel(x, y);
        final dr = pa.r - pb.r;
        final dg = pa.g - pb.g;
        final db = pa.b - pb.b;
        sumSq += dr * dr + dg * dg + db * db;
      }
    }
    final mse = sumSq / (n * 3.0);
    const double maxMse = 8000.0;
    final sim =
        (100 * (1.0 - (mse / maxMse).clamp(0.0, 1.0))).round().clamp(0, 100);
    return sim;
  }

  /// Usa frame de referencia vs captura estática de demo si no hay snapshot de cámara.
  Future<void> _runAnalysis() async {
    if (_referenceBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay imagen de referencia.')),
      );
      return;
    }

    setState(() => _analyzing = true);

    await Future<void>.delayed(const Duration(milliseconds: 500));

    final demo = await rootBundle.load('assets/chica2.png');
    final current = demo.buffer.asUint8List();
    final score = _computeVisualSimilarity(_referenceBytes, current);

    if (score != null) {
      if (score < 50) {
        _assistantMessage = 'La pestaña está caída, por favor revisa la elevación…';
      } else if (score < 75) {
        _assistantMessage = 'Buen avance; ajusta simetría entre ojo derecho e izquierdo.';
      } else {
        _assistantMessage = 'Muy alineado con el mapa de referencia. Continúa así.';
      }
    }

    if (!mounted) return;
    setState(() => _analyzing = false);
  }

  String _formatElapsed() {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Quita el preview del árbol primero, luego [dispose], para no cerrar la cámara con superficie aún enlazada.
  Future<void> _releasePluginCameraAsync() async {
    final c = _cameraController;
    if (c == null) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return;
    }

    if (!mounted) return;
    setState(() => _detachingPluginCamera = true);

    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 220));

    try {
      if (c.value.isInitialized && _flashOn) {
        await c.setFlashMode(FlashMode.off);
      }
      _flashOn = false;
    } catch (e) {
      debugPrint('WorkAssistant flash off: $e');
    }

    await Future<void>.delayed(const Duration(milliseconds: 220));

    try {
      await c.dispose();
    } catch (e) {
      debugPrint('WorkAssistant camera dispose: $e');
    }

    _cameraController = null;
    if (mounted) {
      setState(() => _detachingPluginCamera = false);
    } else {
      _detachingPluginCamera = false;
    }

    await Future<void>.delayed(const Duration(milliseconds: 780));
  }

  Future<void> _exitAssistant() async {
    if (_exitInProgress) return;
    _exitInProgress = true;
    try {
      await _releasePluginCameraAsync();
      if (!mounted) return;
      context.pop();
    } finally {
      _exitInProgress = false;
    }
  }

  Future<void> _disposeControllerFireAndForget(CameraController c) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      if (c.value.isInitialized) {
        await c.setFlashMode(FlashMode.off);
      }
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 120));
    try {
      await c.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    final c = _cameraController;
    _cameraController = null;
    if (c != null) {
      unawaited(_disposeControllerFireAndForget(c));
    }
    super.dispose();
  }

  /// Tablet según guía Material (shortestSide ≥ 600).
  static bool _isTabletLayout(BuildContext context) {
    return MediaQuery.sizeOf(context).shortestSide >= 600;
  }

  static bool _isLandscapeLayout(BoxConstraints c) {
    return c.maxWidth > c.maxHeight;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        unawaited(_exitAssistant());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final tablet = _isTabletLayout(context);
            final landscape = _isLandscapeLayout(constraints);

            if (tablet && landscape) {
              return _buildTabletLandscapeBody(topInset, bottomInset);
            }

            return _buildPortraitSplitBody(
              constraints,
              topInset,
              bottomInset,
            );
          },
        ),
      ),
    );
  }

  /// Tablet apaisado: mitad referencia | mitad cámara; barra en la junta.
  static const int _landscapeRefFlex = 1;
  static const int _landscapeCamFlex = 1;

  Widget _buildTabletLandscapeBody(double topInset, double bottomInset) {
    const barGutter = 10.0;
    final totalFlex = _landscapeRefFlex + _landscapeCamFlex;
    final leftRatio = _landscapeRefFlex / totalFlex;
    return LayoutBuilder(
      builder: (context, c) {
        final barTargetWidth = (c.maxWidth * 0.52).clamp(280.0, 520.0);
        final alignX = 2 * leftRatio - 1;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: _landscapeRefFlex,
                  child: _lashGuidePanel(topInset),
                ),
                Expanded(
                  flex: _landscapeCamFlex,
                  child: _cameraRegion(bottomInset),
                ),
              ],
            ),
            Align(
              alignment: Alignment(alignX, 0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: barGutter),
                child: SizedBox(
                  width: barTargetWidth,
                  child: _assistantFloatingBar(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Retrato: mitad superior referencia, mitad inferior cámara.
  static const int _portraitRefFlex = 1;
  static const int _portraitCamFlex = 1;

  Widget _buildPortraitSplitBody(
    BoxConstraints constraints,
    double topInset,
    double bottomInset,
  ) {
    final h = constraints.maxHeight;
    final totalFlex = _portraitRefFlex + _portraitCamFlex;
    final seamY = h * (_portraitRefFlex / totalFlex);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          children: [
            Expanded(
              flex: _portraitRefFlex,
              child: _lashGuidePanel(topInset),
            ),
            Expanded(
              flex: _portraitCamFlex,
              child: _cameraRegion(bottomInset),
            ),
          ],
        ),
        Positioned(
          top: seamY,
          left: 14,
          right: 14,
          child: FractionalTranslation(
            translation: const Offset(0, -1.4),
            child: _assistantFloatingBar(),
          ),
        ),
      ],
    );
  }

  Widget _lashGuidePanel(double topInset) {
    final photo = _panelPngFromCamera;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Foto de ojos capturada (o estado de espera) ───────────────
        if (photo != null)
          Positioned.fill(
            child: Image.memory(
              photo,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          )
        else
          ColoredBox(
            color: const Color(0xFF0D0D0D),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _isCapturing
                      ? const CircularProgressIndicator(color: Colors.white54)
                      : const Icon(Icons.camera_alt_outlined,
                          color: Colors.white24, size: 64),
                  const SizedBox(height: 14),
                  Text(
                    _isCapturing ? 'Capturando…' : 'Iniciando cámara…',
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

        // ── Indicador de análisis en curso ────────────────────────────
        if (_analyzing)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white70),
              ),
            ),
          ),

        // ── Controles superiores ──────────────────────────────────────
        Positioned(
          top: topInset + 8,
          left: 10,
          child: _circleIconButton(
            icon: Icons.arrow_back,
            onTap: () {
              if (_exitInProgress) return;
              unawaited(_exitAssistant());
            },
          ),
        ),
        Positioned(
          top: topInset + 8,
          left: 0, right: 0,
          child: Center(child: _almendradoPill()),
        ),
        Positioned(
          top: topInset + 8,
          right: 10,
          child: _circleIconButton(
            icon: Icons.photo_library_outlined,
            onTap: _pickReferenceSheet,
          ),
        ),
      ],
    );
  }

  Widget _almendradoPill() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.actionGreen.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFF062A1E).withValues(alpha: 0.6),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.remove_red_eye, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Almendrado',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }

Widget _assistantFloatingBar() {
  return ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.actionGreen.withValues(alpha: 0.85),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.remove_red_eye_outlined,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _assistantMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: (_analyzing || _isCapturing || _panelPngFromCamera == null)
                  ? null
                  : _runAnalysis,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (_analyzing || _isCapturing || _panelPngFromCamera == null)
                      ? Colors.white.withValues(alpha: 0.12)
                      : AppColors.actionGreen,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: (_analyzing || _isCapturing)
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        Icons.smart_toy_outlined,
                        color: _panelPngFromCamera == null ? Colors.white30 : Colors.white,
                        size: 22,
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}


  Widget _cameraRegion(double bottomInset) {
    final c = _cameraController;
    final showPreview =
        c != null && c.value.isInitialized && !_detachingPluginCamera;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: const Color(0xFF0D0D0D),
          child: showPreview
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: c.value.previewSize!.height,
                    height: c.value.previewSize!.width,
                    child: CameraPreview(c),
                  ),
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white54),
                      const SizedBox(height: 12),
                      Text(
                        _detachingPluginCamera
                            ? 'Cerrando cámara…'
                            : 'Iniciando cámara…',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: _recordingPill(),
        ),
        Positioned(
          right: 8,
          top: 64,
          bottom: 96,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _railIconButton(
                asset: 'assets/rotar.png',
                onTap: _switchCamera,
              ),
              _railIconButton(
                asset: 'assets/flash.png',
                onTap: _toggleFlash,
              ),
              _railIconButton(
                icon: Icons.crop_square_outlined,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Marco / galería: próxima versión.'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 16 + bottomInset,
          child: Center(child: _stopStyleButton()),
        ),
      ],
    );
  }

  Widget _recordingPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFE53935),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatElapsed(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _railIconButton({
    String? asset,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: asset != null
              ? Image.asset(asset, width: 22, height: 22)
              : Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _stopStyleButton() {
    final busy = _isCapturing || _analyzing;
    return GestureDetector(
      onTap: busy ? null : () => unawaited(_captureAndAnalyze()),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 28, height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.actionGreen,
                  ),
                )
              : Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.actionGreen,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
        ),
      ),
    );
  }
}



