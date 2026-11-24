import 'dart:math' as math;

/// Forma de la curvatura de una fibra, definida por parámetros y no por un
/// nombre fijo: STRAIGHT, J, C, D, L, LC o cualquier curva nueva que el salón
/// quiera crear son combinaciones de estos tres valores.
///
/// - [degrees]: cuánto se dobla la fibra en total (0 = recta).
/// - [position]: dónde se concentra el doblez, de la base (0) a la punta (1).
/// - [sharpness]: 0 = curva gradual (C) … 1 = quiebre marcado (L).
///
/// La fibra nace en la dirección que le da el motor (proyectada hacia
/// adelante, ver `LASH_PROJECTION_DEG`) y se dobla hacia arriba, hacia el
/// párpado, como una extensión real.
class LashCurl {
  final double degrees, position, sharpness;
  const LashCurl(this.degrees, this.position, this.sharpness);

  static const minDegrees = 0.0, maxDegrees = 150.0;
  static const minPosition = .1, maxPosition = .9;

  /// Valida los parámetros publicados (admin → manifiesto).
  factory LashCurl.fromParameters(Map<String, dynamic> p) {
    double number(String key, double min, double max) {
      final n = p[key];
      if (n is! num || !n.isFinite || n < min || n > max) {
        throw const FormatException('Invalid curl parameter');
      }
      return n.toDouble();
    }

    return LashCurl(
      number('curl_deg', minDegrees, maxDegrees),
      number('bend_position', minPosition, maxPosition),
      number('bend_sharpness', 0, 1),
    );
  }

  Map<String, dynamic> toParameters() => {
    'curl_deg': degrees,
    'bend_position': position,
    'bend_sharpness': sharpness,
  };

  /// Curva por defecto de un estilo sin curvatura elegida, a partir de su
  /// `curl` histórico (0.38–0.72 en los estilos incluidos ≈ 32°–61°).
  factory LashCurl.fromStyleCurl(double curl) =>
      LashCurl((curl * 85).clamp(minDegrees, maxDegrees), .5, .25);

  /// Curvas de referencia de las bandejas del salón (punto de partida; el
  /// salón crea las suyas desde el administrador).
  static const presets = <String, LashCurl>{
    'STRAIGHT': LashCurl(0, .5, 0),
    'J': LashCurl(25, .6, .2),
    'B': LashCurl(35, .55, .2),
    'C': LashCurl(50, .5, .25),
    'CC': LashCurl(62, .5, .3),
    'D': LashCurl(72, .45, .3),
    'DD': LashCurl(85, .45, .35),
    'L': LashCurl(60, .3, .9),
    'LC': LashCurl(72, .3, .7),
  };

  /// Perfil de la fibra muestreado en [samples]+1 puntos a lo largo de su
  /// largo (s = 0 raíz … 1 punta), con largo de arco 1: `up` sube en la
  /// dirección de nacimiento y `back` es lo que se dobló hacia el párpado.
  /// Se integra el ángulo φ(s) = degrees · F(s), con F un escalón suave
  /// centrado en [position] cuyo ancho baja con [sharpness].
  ({List<double> up, List<double> back}) profile(int samples) {
    final total = degrees * math.pi / 180;
    final width = .75 + (.06 - .75) * sharpness;
    double bendAt(double s) {
      final t = ((s - (position - width / 2)) / width).clamp(0.0, 1.0);
      return t * t * (3 - 2 * t);
    }

    // Divisible por los muestreos usados (10, 12): cada muestra cae justo.
    const steps = 240;
    final up = <double>[0], back = <double>[0];
    var u = 0.0, b = 0.0;
    for (var k = 1; k <= steps; k++) {
      final sMid = (k - .5) / steps;
      final phi = total * bendAt(sMid);
      u += math.cos(phi) / steps;
      b += math.sin(phi) / steps;
      if (k * samples % steps == 0) {
        up.add(u);
        back.add(b);
      }
    }
    return (up: up, back: back);
  }

  @override
  bool operator ==(Object other) =>
      other is LashCurl &&
      other.degrees == degrees &&
      other.position == position &&
      other.sharpness == sharpness;

  @override
  int get hashCode => Object.hash(degrees, position, sharpness);
}
