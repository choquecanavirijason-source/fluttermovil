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
import 'package:test_face/work_assistant_args.dart';

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
  String? _resultSummary;
  int? _similarityScore;
  List<String> _tips = const [];

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

  /// Foto automática en el panel superior (mitad de pantalla).
  Uint8List? _panelPngFromCamera;
  bool _mirrorPrefetchTopPanel = false;
  String? _panelSnapshotPath;
  bool _snapshotTakenWithFrontCamera = true;
  int? _autoCaptureCountdown;
  bool _autoCaptureScheduled = false;
  bool _autoCapturing = false;
  Timer? _autoCaptureTimer;

  bool get _usingFrontCamera {
    final list = _cameras;
    if (list == null || list.isEmpty) return true;
    final i = _cameraIndex.clamp(0, list.length - 1);
    return list[i].lensDirection == CameraLensDirection.front;
  }

  @override
  void initState() {
    super.initState();
    final pref = widget.args?.panelPngBytes;
    if (pref != null && pref.isNotEmpty) {
      _panelPngFromCamera = pref;
      _referenceBytes = pref;
      _mirrorPrefetchTopPanel = widget.args?.mirrorTopPanel ?? false;
      _autoCaptureScheduled = true;
    } else {
      unawaited(_loadAsset(_defaultRefAsset));
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
      _resultSummary = null;
      _similarityScore = null;
      _tips = const [];
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
      _scheduleAutoCaptureOnce();
    } catch (e) {
      debugPrint('WorkAssistant camera: $e');
    }
  }

  void _scheduleAutoCaptureOnce() {
    if (_autoCaptureScheduled || !mounted) return;
    _autoCaptureScheduled = true;
    _autoCaptureCountdown = 3;
    if (mounted) setState(() {});

    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final left = _autoCaptureCountdown;
      if (left == null) {
        t.cancel();
        return;
      }
      if (left <= 1) {
        t.cancel();
        setState(() => _autoCaptureCountdown = null);
        unawaited(_capturePanelSnapshot());
        return;
      }
      setState(() => _autoCaptureCountdown = left - 1);
    });
  }

  Future<void> _capturePanelSnapshot() async {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized || !mounted) return;
    if (_autoCapturing) return;
    _autoCapturing = true;
    try {
      final xfile = await c.takePicture();
      if (!mounted) return;
      final path = xfile.path;
      final bytes = await File(path).readAsBytes();
      final wasFront = _usingFrontCamera;
      if (!mounted) return;
      setState(() {
        _panelSnapshotPath = path;
        _snapshotTakenWithFrontCamera = wasFront;
        _referenceBytes = bytes;
      });
    } catch (e) {
      debugPrint('WorkAssistant takePicture: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo tomar la foto: $e')),
        );
      }
    } finally {
      _autoCapturing = false;
    }
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

    setState(() {
      _analyzing = true;
      _resultSummary = null;
      _similarityScore = null;
      _tips = const [];
    });

    await Future<void>.delayed(const Duration(milliseconds: 500));

    final demo = await rootBundle.load('assets/chica2.png');
    final current = demo.buffer.asUint8List();
    final score = _computeVisualSimilarity(_referenceBytes, current);
    final tips = <String>[];
    String summary;

    if (score == null) {
      summary = 'No se pudieron decodificar las imágenes.';
    } else {
      summary = score >= 75
          ? 'Muy buena coincidencia visual con la referencia.'
          : score >= 45
              ? 'Hay similitud; revisa detalles (simetría, grosor, terminación).'
              : 'La imagen actual se aleja de la referencia. Revisa técnica.';

      if (score < 85) {
        tips.add('Compara la línea del párpado con la foto objetivo.');
        tips.add('Unifica el grosor de punta a comisura.');
      }
      if (score < 60) {
        tips.add('Revisa la elevación del arco respecto a la referencia.');
        tips.add('La iluminación puede alterar el tono percibido.');
      }
      if (tips.isEmpty) {
        tips.add('Mantén el mismo ángulo que en la referencia.');
      }

      if (score < 50) {
        _assistantMessage =
            'La pestaña está caída, por favor revisa la elevación…';
      } else if (score < 75) {
        _assistantMessage =
            'Buen avance; ajusta simetría entre ojo derecho e izquierdo.';
      } else {
        _assistantMessage =
            'Muy alineado con el mapa de referencia. Continúa así.';
      }
    }

    if (!mounted) return;
    setState(() {
      _analyzing = false;
      _similarityScore = score;
      _resultSummary = summary;
      _tips = tips;
    });
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

    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;

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
    _autoCaptureTimer?.cancel();
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
          top: seamY - 28,
          left: 14,
          right: 14,
          child: _assistantFloatingBar(),
        ),
      ],
    );
  }

  Widget _lashGuidePanel(double topInset) {
    final snapshotPath = _panelSnapshotPath;
    final prefBytes = _panelPngFromCamera;
    final hasTopImage = prefBytes != null || snapshotPath != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (prefBytes != null)
          Positioned.fill(
            child: Transform.flip(
              flipX: _mirrorPrefetchTopPanel,
              child: Image.memory(
                prefBytes,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => const ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.white54, size: 48),
                  ),
                ),
              ),
            ),
          )
        else if (snapshotPath != null)
          Positioned.fill(
            child: Transform.flip(
              flipX: _snapshotTakenWithFrontCamera,
              child: Image.file(
                File(snapshotPath),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => const ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.white54, size: 48),
                  ),
                ),
              ),
            ),
          )
        else
          const ColoredBox(color: Colors.black),
        if (_autoCaptureCountdown != null)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_autoCaptureCountdown!}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 96,
                    fontWeight: FontWeight.w200,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _autoCapturing ? 'Capturando…' : 'Foto en el panel superior',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        if (!hasTopImage &&
            _autoCaptureCountdown == null &&
            _autoCaptureScheduled &&
            !_autoCapturing &&
            (_cameraController == null || !_cameraController!.value.isInitialized))
          Center(
            child: Text(
              'Iniciando cámara…',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          ),
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
          left: 0,
          right: 0,
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
            color: const Color(0xFF0D5C41).withValues(alpha: 0.92),
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
                'drado',
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
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.only(left: 16, top: 10, bottom: 10, right: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _assistantMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 14,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _analyzing ? null : _runAnalysis,
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Color(0xFF0D5C41),
                  shape: BoxShape.circle,
                ),
                child: _analyzing
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.smart_toy_outlined,
                        color: Colors.white,
                        size: 26,
                      ),
              ),
            ),
          ],
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
        if (_similarityScore != null)
          Positioned(
            left: 8,
            right: 8,
            bottom: 88 + bottomInset,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _compactResultChip(),
                if (_tips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ..._tips.take(3).map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '· $t',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 11,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ),
                ],
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

  Widget _compactResultChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(
            _similarityScore! >= 60
                ? Icons.check_circle_outline
                : Icons.info_outline,
            color: _similarityScore! >= 60
                ? Colors.tealAccent
                : Colors.amber,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Coincidencia: $_similarityScore% · ${_resultSummary ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stopStyleButton() {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Detener sesión: enlaza tu flujo aquí.')),
        );
      },
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
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF0D5C41), width: 2),
            ),
          ),
        ),
      ),
    );
  }
}
