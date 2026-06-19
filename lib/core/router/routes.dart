/// Rutas declaradas como constantes.
class AppRoutes {
  AppRoutes._();

  // Públicas
  static const String splash = '/splash';
  static const String login = '/login';

  // Privado: Inicio es la pantalla central (sin barra de pestañas).
  static const String shell = '/';
  static const String comision = '/comision';
  static const String perfil = '/perfil';

  // Probador AR / IA (pantallas existentes, aún sobre la capa antigua)
  static const String camera = '/camera';
  static const String selection = '/selection';
  static const String recomendacion = '/recomendacion';
  static const String workAssistant = '/work-assistant';

  // Catálogo y clientes
  static const String catalogo = '/catalogo';
  static const String servicio = '/servicio';
  static const String cliente = '/cliente';
  static const String clienteDetalle = '/cliente-detalle';
}
