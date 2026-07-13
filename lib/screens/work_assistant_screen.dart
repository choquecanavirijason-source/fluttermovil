import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:Probador/work_assistant_args.dart';

import '../core/recommendation/eye_shape_analyzer.dart';
import '../eye_tracking_model.dart';
import '../features/tracking/data/tracking_repository_impl.dart';
import '../native_eye_tracking_service.dart';
import 'widgets/hybrid_camera_preview.dart';

/// Asistente de trabajo ("Beauty Tech"): mitad superior foto de referencia
/// del diseño elegido; mitad inferior cámara nativa en vivo con guiado de IA
/// y grabación real. Reutiliza la misma sesión de CameraX nativa que el
/// probador (ver [NativeEyeTrackingService]) — por eso no abre ninguna
/// cámara propia: solo se suscribe a los landmarks y captura frames.
class WorkAssistantScreen extends ConsumerStatefulWidget {
  const WorkAssistantScreen({super.key, this.args});

  final WorkAssistantArgs? args;

  @override
  ConsumerState<WorkAssistantScreen> createState() =>
      _WorkAssistantScreenState();
}

class _WorkAssistantScreenState extends ConsumerState<WorkAssistantScreen> {
  static const String _defaultRefAsset = 'assets/chica.png';
  static const double _liveAsymmetryThreshold = 0.28;
  static const double _liveHoodedTiltDeg = -6.0;
  static const double _liveTiltDiffThreshold = 6.0;

  final NativeEyeTrackingService _service = NativeEyeTrackingService();
  StreamSubscription<TrackingFrame>? _trackingSub;

  Uint8List? _referenceBytes;
  bool _mirrorTopPanel = false;

  bool _analyzing = false;
  String _assistantMessage =
      'Centra tu rostro en cámara para recibir guía en vivo.';
  DateTime? _aiMessageHoldUntil;
  DateTime? _lastMessageUpdate;

  bool _isRecording = false;
  bool _recordingBusy = false;
  DateTime _sessionStart = DateTime.now();
  Timer? _tickTimer;
  int _elapsedSeconds = 0;

  /// Evita doble atrás mientras se detiene una grabación en curso.
  bool _exitInProgress = false;

  @override
  void initState() {
    super.initState();
    final pref = widget.args?.panelPngBytes;
    if (pref != null && pref.isNotEmpty) {
      _referenceBytes = pref;
      _mirrorTopPanel = widget.args?.mirrorTopPanel ?? false;
    } else {
      unawaited(_loadAsset(_defaultRefAsset));
    }
    unawaited(_service.startTracking());
    _trackingSub = _service.trackingStream.listen(_onFrame);
  }

  Future<void> _loadAsset(String path) async {
    final data = await rootBundle.load(path);
    if (!mounted) return;
    setState(() => _referenceBytes = data.buffer.asUint8List());
  }

  void _onFrame(TrackingFrame frame) {
    if (!mounted) return;
    final holdUntil = _aiMessageHoldUntil;
    if (holdUntil != null && DateTime.now().isBefore(holdUntil)) {
      return; // no pisar un consejo de IA reciente.
    }
    final analysis = EyeShapeAnalyzer.analyze(frame);
    final message = _buildGuidanceMessage(analysis);
    if (message == _assistantMessage) return;

    final now = DateTime.now();
    final last = _lastMessageUpdate;
    if (last != null && now.difference(last) < const Duration(milliseconds: 1200)) {
      return;
    }
    _lastMessageUpdate = now;
    setState(() => _assistantMessage = message);
  }

  static String _buildGuidanceMessage(EyeAnalysis a) {
    if (!a.reliable) {
      return 'Centra tu rostro en cámara para recibir guía en vivo.';
    }
    if (a.asymmetry > _liveAsymmetryThreshold) {
      return 'Hay asimetría entre ambos ojos, revisa que la aplicación sea pareja.';
    }
    final tiltDiff = (a.leftTiltDeg - a.rightTiltDeg).abs();
    if (tiltDiff > _liveTiltDiffThreshold) {
      return 'Un ojo quedó más elevado que el otro, iguala la inclinación.';
    }
    final avgTilt = (a.leftTiltDeg + a.rightTiltDeg) / 2;
    if (avgTilt <= _liveHoodedTiltDeg) {
      return 'La mirada se ve caída, considera elevar el diseño.';
    }
    return 'Buena simetría y elevación. Continúa así.';
  }

  Future<void> _toggleRecording() async {
    if (_recordingBusy) return;
    _recordingBusy = true;
    try {
      if (_isRecording) {
        final path = await _service.stopRecording();
        _tickTimer?.cancel();
        _tickTimer = null;
        if (!mounted) return;
        setState(() => _isRecording = false);
        if (path != null && mounted) {
          final name = path.split(Platform.pathSeparator).last;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Grabación guardada: $name')),
          );
        }
      } else {
        try {
          await _service.startRecording();
        } on PlatformException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'No se pudo iniciar la grabación: ${e.message ?? e.code}',
                ),
              ),
            );
          }
          return;
        }
        _sessionStart = DateTime.now();
        _tickTimer?.cancel();
        _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() {
            _elapsedSeconds =
                DateTime.now().difference(_sessionStart).inSeconds;
          });
        });
        if (!mounted) return;
        setState(() {
          _isRecording = true;
          _elapsedSeconds = 0;
        });
      }
    } finally {
      _recordingBusy = false;
    }
  }

  Future<void> _runAiReview() async {
    if (_analyzing) return;
    setState(() => _analyzing = true);
    try {
      final jpeg = await _service.captureLastCameraFrame();
      if (jpeg == null || jpeg.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo capturar la cámara. Reintenta.'),
            ),
          );
        }
        return;
      }
      final feedback = await ref.read(trackingRepositoryProvider).aiReview(jpeg);
      if (!mounted) return;
      setState(() {
        _assistantMessage = feedback.isNotEmpty
            ? feedback
            : 'La IA no devolvió un consejo esta vez.';
        _aiMessageHoldUntil = DateTime.now().add(const Duration(seconds: 10));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo obtener el consejo de IA: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
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

  String _formatElapsed() {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _exitAssistant() async {
    if (_exitInProgress) return;
    _exitInProgress = true;
    try {
      if (_isRecording) {
        await _service.stopRecording();
        _tickTimer?.cancel();
        _tickTimer = null;
        _isRecording = false;
      }
      if (!mounted) return;
      context.pop();
    } finally {
      _exitInProgress = false;
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _trackingSub?.cancel();
    if (_isRecording) {
      unawaited(_service.stopRecording());
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
    final prefBytes = _referenceBytes;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (prefBytes != null)
          Positioned.fill(
            child: Transform.flip(
              flipX: _mirrorTopPanel,
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
        else
          const ColoredBox(color: Colors.black),
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
                color: const Color(0xFF0D5C41).withValues(alpha: 0.85),
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
              onTap: _analyzing ? null : () => unawaited(_runAiReview()),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _analyzing
                      ? Colors.white.withValues(alpha: 0.15)
                      : const Color(0xFF0D5C41),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: _analyzing
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.smart_toy_outlined,
                        color: Colors.white,
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
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(
          color: Color(0xFF0D0D0D),
          child: HybridCameraPreview(),
        ),
        if (_isRecording)
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
                onTap: () => unawaited(_service.switchCamera()),
              ),
              _railIconButton(
                asset: 'assets/flash.png',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Flash: próxima versión.'),
                    ),
                  );
                },
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
          child: Center(child: _recordButton()),
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

  /// Botón real de grabar/detener: círculo rojo en reposo, cuadrado (stop)
  /// mientras graba.
  Widget _recordButton() {
    return GestureDetector(
      onTap: () => unawaited(_toggleRecording()),
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isRecording ? 28 : 56,
            height: _isRecording ? 28 : 56,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(_isRecording ? 6 : 28),
            ),
          ),
        ),
      ),
    );
  }
}
