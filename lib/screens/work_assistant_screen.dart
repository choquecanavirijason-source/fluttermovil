import 'dart:async' show Timer, unawaited;
import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:Probador/core/theme/app_colors.dart';
import 'package:Probador/work_assistant_args.dart';

import '../features/tracking/data/tracking_repository_impl.dart';

/// Asistente de verificación: mitad superior foto de referencia (captura automática a los 3 s);
/// mitad inferior cámara en vivo. Incluye guiado de IA en vivo (Beauty Tech):
/// un ciclo automático que pide consejos periódicos a la IA y los lee en voz
/// alta con el motor de texto-a-voz del celular.
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

  /// Cada cuánto se pide un consejo nuevo mientras el guiado está activo.
  /// Además del ciclo automático, el botón de cámara en la barra del
  /// asistente permite pedir un consejo inmediato en cualquier momento
  /// (p. ej. justo después de corregir algo), sin esperar este intervalo.
  static const Duration _aiCycleInterval = Duration(seconds: 15);

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;

  bool _analyzing = false;

  final FlutterTts _tts = FlutterTts();

  /// true mientras el ciclo automático de guiado de IA está corriendo.
  bool _aiGuidanceActive = false;
  Timer? _aiCycleTimer;

  String _assistantMessage =
      'Toca "Iniciar" para que la IA te guíe en vivo mientras aplicas.';

  bool _flashOn = false;
  int _cameraIndex = 0;

  /// true mientras se está grabando video real con la cámara.
  bool _isRecordingVideo = false;
  DateTime _recordingStart = DateTime.now();
  Timer? _tickTimer;
  int _elapsedSeconds = 0;

  /// Evita doble atrás mientras se libera la cámara (plugin camera vs CameraX nativo).
  bool _exitInProgress = false;

  /// Oculta [CameraPreview] antes de [dispose] para evitar BufferQueue abandonado (CameraX vs PlatformView).
  bool _detachingPluginCamera = false;

  /// Foto del panel superior (capturada automáticamente al iniciar la cámara).
  Uint8List? _panelPngFromCamera;

  /// Última foto (sin recortar) que la IA evaluó. Si ya hay una, la próxima
  /// evaluación compara "antes" (esta) vs "después" (la nueva) para decir
  /// si mejoró, en vez de dar un consejo genérico aislado.
  Uint8List? _lastEvaluatedPhoto;

  /// Indica que se está tomando la foto automática.
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final pref = widget.args?.panelPngBytes;
    if (pref != null && pref.isNotEmpty) {
      _panelPngFromCamera = pref;
    }
    unawaited(_initCamera());
    unawaited(_tts.setLanguage('es-MX'));
    unawaited(_tts.setSpeechRate(0.46));
    unawaited(_configureSpanishFemaleVoice());
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
        debugPrint(
          'WorkAssistant TTS voces es disponibles (${esVoices.length}): $esVoices',
        );

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
          debugPrint('WorkAssistant TTS voz femenina elegida: ${female['name']}');
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

  /// Detiene el ciclo de IA al pasar a segundo plano: el plugin `camera`
  /// puede liberar el `CameraController` cuando la app pierde el foco, y
  /// sin esto el `Timer.periodic` seguía disparando `takePicture()` sobre un
  /// controller ya destruido ("CameraController was used after being
  /// disposed") al volver.
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
      if (_isRecordingVideo) {
        _tickTimer?.cancel();
        _tickTimer = null;
        _isRecordingVideo = false;
        final c = _cameraController;
        if (c != null) {
          unawaited(
            c.stopVideoRecording().catchError((Object e) {
              debugPrint('WorkAssistant stopVideoRecording en background: $e');
              return XFile('');
            }),
          );
        }
      }
    }
  }

  Future<void> _loadAsset(String path) async {
    final data = await rootBundle.load(path);
    if (!mounted) return;
    setState(() {
      _panelPngFromCamera = data.buffer.asUint8List();
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
      if (_panelPngFromCamera == null) {
        unawaited(_captureForTopPanel(initialSettleDelay: true));
      }
    } catch (e) {
      debugPrint('WorkAssistant camera: $e');
    }
  }

  /// Toma una foto con la cámara y la muestra en el panel superior (región de ojos).
  ///
  /// [initialSettleDelay] da tiempo a que la superficie de la cámara recién
  /// creada esté lista (solo hace falta en la auto-captura al abrir la
  /// pantalla); en una retoma manual la cámara ya está estable, así que se
  /// omite para que responda al toque sin demora artificial.
  Future<void> _captureForTopPanel({bool initialSettleDelay = false}) async {
    if (_isRecordingVideo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Detén la grabación para tomar una foto.')),
      );
      return;
    }
    if (_isCapturing || _analyzing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Espera un momento, la cámara está ocupada…')),
      );
      return;
    }
    if (mounted) setState(() => _isCapturing = true);
    try {
      if (initialSettleDelay) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      if (!mounted) return;
      final c = _cameraController;
      if (c == null || !c.value.isInitialized) return;
      final xfile = await c.takePicture();
      if (!mounted) return;
      final raw = await File(xfile.path).readAsBytes();
      final cropped = _cropEyeRegion(raw);
      if (!mounted) return;
      setState(() => _panelPngFromCamera = cropped);
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

  /// Inicia/detiene una grabación de video real (sin audio) con el plugin
  /// `camera`. Es independiente de la foto del panel de referencia (que se
  /// toma una sola vez, automáticamente) y del guiado de IA (su propio
  /// botón en la barra del asistente).
  Future<void> _toggleVideoRecording() async {
    if (_isCapturing || _exitInProgress) return;
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Espera a que la cámara esté lista.')),
      );
      return;
    }

    if (_isRecordingVideo) {
      _tickTimer?.cancel();
      _tickTimer = null;
      try {
        final xfile = await c.stopVideoRecording();
        if (!mounted) return;
        setState(() => _isRecordingVideo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Grabación guardada: ${xfile.name}')),
        );
      } catch (e) {
        debugPrint('WorkAssistant stopVideoRecording: $e');
        if (mounted) {
          setState(() => _isRecordingVideo = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo guardar la grabación: $e')),
          );
        }
      }
      return;
    }

    try {
      await c.startVideoRecording();
      if (!mounted) return;
      _recordingStart = DateTime.now();
      _tickTimer?.cancel();
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _elapsedSeconds = DateTime.now().difference(_recordingStart).inSeconds;
        });
      });
      setState(() {
        _isRecordingVideo = true;
        _elapsedSeconds = 0;
      });
    } catch (e) {
      debugPrint('WorkAssistant startVideoRecording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo iniciar la grabación: $e')),
        );
      }
    }
  }

  /// Enciende/apaga el ciclo de guiado de IA en vivo: al activarlo pide un
  /// primer consejo y luego repite cada [_aiCycleInterval] hasta detenerlo.
  void _toggleAiGuidance() {
    if (!_aiGuidanceActive) {
      final c = _cameraController;
      if (c == null || !c.value.isInitialized) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Espera a que la cámara esté lista.')),
        );
        return;
      }
      if (_isRecordingVideo) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Detén la grabación de video para pedir guiado de IA.'),
          ),
        );
        return;
      }
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
  /// la IA (backend `POST /tracking/ai-review`); lo lee en voz alta al llegar.
  Future<void> _runAiReview() async {
    // `_isCapturing` es compartido con `_captureForTopPanel` y con
    // `_switchCamera`: el plugin `camera` no admite dos `takePicture()`
    // simultáneos sobre el mismo controller, y tampoco que se lo dispose
    // mientras hay una captura en curso. Chequear y marcar acá, de forma
    // síncrona (sin `await` de por medio), cierra esa ventana de carrera.
    if (_analyzing || _isCapturing || _isRecordingVideo) return;
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) return;

    setState(() {
      _analyzing = true;
      _isCapturing = true;
    });
    try {
      final xfile = await c.takePicture();
      final bytes = await File(xfile.path).readAsBytes();

      // Actualiza la foto de arriba con este mismo estado ya, sin esperar
      // la respuesta de la IA — así cada toque de este botón deja ver de
      // inmediato "cómo va" y, al repetirlo más tarde, la mejora respecto
      // a la captura anterior.
      if (mounted) {
        setState(() => _panelPngFromCamera = _cropEyeRegion(bytes));
      }

      // Si ya evaluamos una foto antes en esta sesión, comparamos "antes"
      // vs "después" para que la IA diga si mejoró; si es la primera vez,
      // pedimos un consejo simple sobre esta única foto.
      final previous = _lastEvaluatedPhoto;
      final repo = ref.read(trackingRepositoryProvider);
      final feedback = previous != null
          ? await repo.aiCompare(beforeJpegBytes: previous, afterJpegBytes: bytes)
          : await repo.aiReview(bytes);
      _lastEvaluatedPhoto = bytes;

      if (!mounted) return;
      final text = feedback.trim().isNotEmpty
          ? feedback.trim()
          : 'La IA no devolvió un consejo esta vez.';
      setState(() => _assistantMessage = text);
      unawaited(_speak(text));
    } catch (e) {
      debugPrint('WorkAssistant _runAiReview: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo obtener el consejo de IA: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _isCapturing = false;
        });
      } else {
        _analyzing = false;
        _isCapturing = false;
      }
    }
  }

  /// Lee [text] en voz alta con el motor de texto-a-voz del celular.
  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _switchCamera() async {
    if (_detachingPluginCamera || _exitInProgress) return;
    if (_isRecordingVideo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Detén la grabación antes de cambiar de cámara.')),
      );
      return;
    }
    if (_isCapturing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Espera a que termine la captura actual.')),
      );
      return;
    }
    if (_cameras == null || _cameras!.length < 2) return;
    final ctrl = _cameraController;
    if (ctrl == null) return;
    // Se invalida la referencia ANTES de destruir el controller: si algo
    // (guiado de IA, captura del panel) lee `_cameraController` mientras el
    // nuevo todavía se está creando, ve null y aborta en vez de usar un
    // controller ya destruido.
    setState(() => _cameraController = null);
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

  /// Opciones secundarias para la foto de referencia (mantener presionado
  /// el botón de la cámara). La acción principal — tomar una foto nueva —
  /// vive directo en el toque simple de ese botón, sin pasar por acá.
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

  /// Quita el preview del árbol primero, luego [dispose], para no cerrar la cámara con superficie aún enlazada.
  Future<void> _releasePluginCameraAsync() async {
    final c = _cameraController;
    if (c == null) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return;
    }

    if (_isRecordingVideo) {
      _tickTimer?.cancel();
      _tickTimer = null;
      _isRecordingVideo = false;
      try {
        await c.stopVideoRecording();
      } catch (e) {
        debugPrint('WorkAssistant stopVideoRecording al salir: $e');
      }
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
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    _aiCycleTimer?.cancel();
    unawaited(_tts.stop());
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
            icon: Icons.camera_alt_outlined,
            // Toque simple = acción principal (tomar foto ya). Mantener
            // presionado = opciones secundarias (foto de ejemplo, etc.).
            onTap: () => unawaited(_captureForTopPanel()),
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
            // "Tomar foto y analizar": captura el estado actual, lo deja
            // como foto de referencia arriba Y pide un consejo nuevo a la
            // IA, sin esperar al ciclo automático. Pensado para repetirse
            // varias veces mientras se corrige: cada toque muestra "cómo
            // va" y compara contra la corrección anterior.
            GestureDetector(
              onTap: (_analyzing || _isCapturing || _isRecordingVideo)
                  ? null
                  : () => unawaited(_runAiReview()),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (_analyzing || _isCapturing || _isRecordingVideo)
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: Icon(
                  Icons.camera_alt_outlined,
                  color: (_analyzing || _isCapturing || _isRecordingVideo)
                      ? Colors.white30
                      : Colors.white,
                  size: 17,
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _isCapturing ? null : _toggleAiGuidance,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _isCapturing
                      ? Colors.white.withValues(alpha: 0.12)
                      : (_aiGuidanceActive
                          ? const Color(0xFFE53935)
                          : AppColors.actionGreen),
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
        if (_isRecordingVideo)
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

  /// Botón real de grabar/detener video: círculo rojo en reposo, cuadrado
  /// (stop) mientras graba. Independiente de la foto del panel superior
  /// (automática, una sola vez) y del guiado de IA (botón propio).
  Widget _stopStyleButton() {
    final busy = _isCapturing || _analyzing;
    return GestureDetector(
      onTap: busy ? null : () => unawaited(_toggleVideoRecording()),
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
                    color: Color(0xFFE53935),
                  ),
                )
              : AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _isRecordingVideo ? 26 : 56,
                  height: _isRecordingVideo ? 26 : 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius:
                        BorderRadius.circular(_isRecordingVideo ? 6 : 28),
                  ),
                ),
        ),
      ),
    );
  }
}



