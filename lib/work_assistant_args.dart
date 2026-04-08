import 'dart:typed_data';

/// Argumentos opcionales al abrir [WorkAssistantScreen] desde la cámara con pestañas.
class WorkAssistantArgs {
  const WorkAssistantArgs({
    this.panelPngBytes,
    this.mirrorTopPanel = false,
  });

  /// Captura PNG (preview + filtro dibujado en Flutter).
  final Uint8List? panelPngBytes;

  /// Espejo horizontal solo en el panel superior (p. ej. selfie coherente con preview).
  final bool mirrorTopPanel;
}
