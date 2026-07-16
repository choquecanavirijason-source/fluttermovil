import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:Probador/core/theme/app_colors.dart';
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

class _WorkAssistantScreenState extends ConsumerState<WorkAssistantScreen>
    with WidgetsBindingObserver {
  static const String _defaultRefAsset = 'assets/chica.png';
  static const double _liveAsymmetryThreshold = 0.28;
  static const double _liveHoodedTiltDeg = -6.0;
  static const double _liveTiltDiffThreshold = 6.0;

  /// Cada cuánto se pide un consejo nuevo mientras el guiado está activo.
  /// Además del ciclo automático, el botón de cámara en la barra del
  /// asistente permite pedir un consejo inmediato en cualquier momento
  /// (p. ej. justo después de corregir algo), sin esperar este intervalo.
  static const Duration _aiCycleInterval = Duration(seconds: 15);

  final NativeEyeTrackingService _service = NativeEyeTrackingService();
  StreamSubscription<TrackingFrame>? _trackingSub;

  Uint8List? _referenceBytes;
  bool _mirrorTopPanel = false;

  bool _analyzing = false;
  final FlutterTts _tts = FlutterTts();

  /// true mientras el ciclo automático de guiado de IA está corriendo.
  bool _aiGuidanceActive = false;
  Timer? _aiCycleTimer;

  String _assistantMessage =
      'Centra tu rostro en cámara para recibir guía en vivo.';
  DateTime? _aiMessageHoldUntil;
  DateTime? _lastMessageUpdate;

  /// Última foto que la IA evaluó. Si ya hay una, la próxima evaluación
  /// compara "antes" (esta) vs "después" (la nueva) para decir si mejoró,
  /// en vez de dar un consejo genérico aislado.
  Uint8List? _lastEvaluatedPhoto;

  bool _isRecording = false;
  bool _recordingBusy = false;
  DateTime _recordingStart = DateTime.now();
  Timer? _tickTimer;
  int _elapsedSeconds = 0;

  /// Evita doble atrás mientras se detiene una grabación en curso.
  bool _exitInProgress = false;

  /// Rutas locales (archivo) del .glb de pestañas, resueltas una única vez.
  /// Mismo mecanismo y mismo modelo por defecto que usa el probador (ver
  /// [HybridCameraPreview]): viajan como `creationParams` del PlatformView,
  /// así que solo se crea la vista de cámara una vez ambas están listas.
  String? _leftModelPath;
  String? _rightModelPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final pref = widget.args?.panelPngBytes;
    if (pref != null && pref.isNotEmpty) {
      _referenceBytes = pref;
      _mirrorTopPanel = widget.args?.mirrorTopPanel ?? false;
    } else {
      unawaited(_loadAsset(_defaultRefAsset));
    }
    unawaited(_resolveEyeModelPaths());
    unawaited(_service.startTracking());
    _trackingSub = _service.trackingStream.listen(_onFrame);
    unawaited(_tts.setLanguage('es-MX'));
    unawaited(_tts.setSpeechRate(0.46));
    unawaited(_configureSpanishFemaleVoice());
  }

  Future<void> _resolveEyeModelPaths() async {
    if (!Platform.isAndroid) return;
    try {
      final leftPath = await extractEyeModelAssetToFile(defaultLeftEyeModelAsset);
      final rightPath = await extractEyeModelAssetToFile(defaultRightEyeModelAsset);
      if (!mounted) return;
      setState(() {
        _leftModelPath = leftPath;
        _rightModelPath = rightPath;
      });
    } catch (e) {
      debugPrint('WorkAssistant: no se pudieron resolver los .glb de pestañas: $e');
    }
  }

  /// Busca entre las voces instaladas en el celular una en español marcada
  /// como femenina y la fija para el TTS. La disponibilidad y el formato del
  /// nombre dependen del motor de voz de cada equipo (normalmente el de
  /// Google), así que si no se encuentra ninguna con ese indicio en el
  /// nombre, se deja la voz por defecto del idioma pero con un pitch un
  /// poco más alto para acercarse a un tono femenino.
  Future<void> _configureSpanishFemaleVoice() async {
    try {
      final voices = await _tts.getVoices;
      if (voices is List) {
        final esVoices = voices.whereType<Map>().where((v) {
          final locale = (v['locale'] ?? '').toString().toLowerCase();
          return locale.startsWith('es');
        }).toList();

        final female = esVoices.cast<Map?>().firstWhere(
          (v) {
            final name = (v?['name'] ?? '').toString().toLowerCase();
            return name.contains('female') ||
                name.contains('#female') ||
                name.contains('-f-') ||
                name.contains('_f_');
          },
          orElse: () => null,
        );

        if (female != null) {
          await _tts.setVoice({
            'name': (female['name'] ?? '').toString(),
            'locale': (female['locale'] ?? '').toString(),
          });
          await _tts.setPitch(1.0);
          return;
        }
      }
    } catch (e) {
      debugPrint('WorkAssistant TTS getVoices/setVoice error: $e');
    }
    // No se pudo identificar una voz femenina explícita entre las
    // instaladas; se sube un poco el pitch para acercarse a ese tono.
    await _tts.setPitch(1.15);
  }

  /// Detiene el ciclo de IA al pasar a segundo plano: evita seguir gastando
  /// llamadas a la IA (y capturas) mientras la app no está visible.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _aiCycleTimer?.cancel();
      _aiCycleTimer = null;
      if (_aiGuidanceActive && mounted) {
        setState(() => _aiGuidanceActive = false);
      } else {
        _aiGuidanceActive = false;
      }
    }
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

  /// Toma una foto ahora y la deja como referencia arriba, sin pedirle nada
  /// a la IA (acción del toque simple en el ícono de cámara superior).
  Future<void> _captureReferenceNow() async {
    final jpeg = await _service.captureLastCameraFrame();
    if (jpeg == null || jpeg.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo capturar la cámara. Reintenta.')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _referenceBytes = jpeg);
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

  /// Enciende/apaga el ciclo de guiado de IA en vivo: al activarlo pide un
  /// primer consejo y luego repite cada [_aiCycleInterval] hasta detenerlo.
  void _toggleAiGuidance() {
    if (!_aiGuidanceActive) {
      setState(() => _aiGuidanceActive = true);
      unawaited(_runAiReview());
      _aiCycleTimer?.cancel();
      _aiCycleTimer = Timer.periodic(_aiCycleInterval, (_) {
        if (!mounted || !_aiGuidanceActive) return;
        unawaited(_runAiReview());
      });
    } else {
      _aiCycleTimer?.cancel();
      _aiCycleTimer = null;
      setState(() => _aiGuidanceActive = false);
    }
  }

  /// Captura el frame actual de la cámara en vivo y pide un consejo real a
  /// la IA. Si ya hay una foto evaluada antes en esta sesión, compara
  /// "antes" vs "después" en vez de dar un consejo aislado. Lo lee en voz
  /// alta al llegar.
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

      // Deja ver de inmediato "cómo va" arriba, sin esperar la IA.
      if (mounted) setState(() => _referenceBytes = jpeg);

      final previous = _lastEvaluatedPhoto;
      final repo = ref.read(trackingRepositoryProvider);
      final feedback = previous != null
          ? await repo.aiCompare(beforeJpegBytes: previous, afterJpegBytes: jpeg)
          : await repo.aiReview(jpeg);
      _lastEvaluatedPhoto = jpeg;

      if (!mounted) return;
      final text = feedback.trim().isNotEmpty
          ? feedback.trim()
          : 'La IA no devolvió un consejo esta vez.';
      setState(() {
        _assistantMessage = text;
        _aiMessageHoldUntil = DateTime.now().add(const Duration(seconds: 10));
      });
      unawaited(_speak(text));
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

  /// Lee [text] en voz alta con el motor de texto-a-voz del celular.
  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
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
        _recordingStart = DateTime.now();
        _tickTimer?.cancel();
        _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() {
            _elapsedSeconds =
                DateTime.now().difference(_recordingStart).inSeconds;
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
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    _aiCycleTimer?.cancel();
    unawaited(_tts.stop());
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
            icon: Icons.camera_alt_outlined,
            // Toque simple = tomar foto ya. Mantener presionado = opciones
            // secundarias (foto de ejemplo, elegir de galería).
            onTap: () => unawaited(_captureReferenceNow()),
            onLongPress: _pickReferenceSheet,
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
    VoidCallback? onLongPress,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => unawaited(_speak(_assistantMessage)),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // "Evaluar ahora": pide un consejo nuevo de inmediato, sin
            // esperar al ciclo automático ni tener que apagarlo/prenderlo.
            GestureDetector(
              onTap: _analyzing ? null : () => unawaited(_runAiReview()),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _analyzing
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: Icon(
                  Icons.camera_alt_outlined,
                  color: _analyzing ? Colors.white30 : Colors.white,
                  size: 17,
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _toggleAiGuidance,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _aiGuidanceActive
                      ? const Color(0xFFE53935)
                      : AppColors.actionGreen,
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
                    : Icon(
                        _aiGuidanceActive
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
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
    final leftPath = _leftModelPath;
    final rightPath = _rightModelPath;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: const Color(0xFF0D0D0D),
          // Solo se crea la vista nativa una vez resueltas ambas rutas del
          // .glb: viajan como `creationParams` en la creación del
          // PlatformView (ver [HybridCameraPreview]), así que Kotlin las
          // recibe siempre con datos reales, sin depender de un segundo
          // viaje Dart→Kotlin por MethodChannel.
          child: (leftPath != null && rightPath != null)
              ? HybridCameraPreview(
                  leftModelPath: leftPath,
                  rightModelPath: rightPath,
                )
              : const SizedBox.expand(),
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

  /// Botón real de grabar/detener video: círculo rojo en reposo, cuadrado
  /// (stop) mientras graba.
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
