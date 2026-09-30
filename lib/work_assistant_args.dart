import 'dart:typed_data';

/// Argumentos opcionales al abrir [WorkAssistantScreen] desde la cámara con pestañas.
class WorkAssistantArgs {
  const WorkAssistantArgs({
    this.panelPngBytes,
    this.panelBytesFuture,
    this.mirrorTopPanel = false,
  });

  /// Captura (preview + filtro dibujado en Flutter), ya lista.
  final Uint8List? panelPngBytes;

  /// La misma captura, todavía componiéndose en segundo plano. Permite
  /// navegar apenas sale la foto en vez de esperar la composición (varios
  /// cientos de ms a segundos); la pantalla muestra un cargando en el panel
  /// hasta que termina. Si viene, tiene prioridad sobre [panelPngBytes].
  final Future<Uint8List?>? panelBytesFuture;

  /// Espejo horizontal solo en el panel superior (p. ej. selfie coherente con preview).
  final bool mirrorTopPanel;
}
