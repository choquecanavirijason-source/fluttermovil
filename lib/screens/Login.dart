import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:test_face/core/services/auth_service.dart';


// Definición del CustomClipper para crear la forma curva en el encabezado.
class HeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    // Inicia en la esquina superior izquierda
    path.lineTo(0, size.height * 0.65);

    // Punto de control para el arco: lo empuja hacia abajo para crear la curva convexa
    final controlPoint = Offset(size.width / 2, size.height * 1.35);
    // Punto final del arco
    final endPoint = Offset(size.width, size.height * 0.65);

    // Agrega la curva Bezier cuadrática
    path.quadraticBezierTo(
      controlPoint.dx,
      controlPoint.dy,
      endPoint.dx,
      endPoint.dy,
    );

    // Dibuja la línea de vuelta a la esquina superior derecha y cierra el camino
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class LoginPage extends StatefulWidget {
  // Inicialización de Firebase
 

  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Inicialización de Firebase
 

  final TextEditingController userCtrl = TextEditingController();
  final TextEditingController passCtrl = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoggingIn = false;

  final Color primaryColor = const Color(0xFF094732);
  final double headerHeight = 350; // Altura para el encabezado verde

  Future<void> _loginWithApi() async {
    final username = userCtrl.text.trim();
    final password = passCtrl.text.trim();
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Por favor, completa todos los campos")),
      );
      return;
    }

    setState(() => _isLoggingIn = true);
    try {
      await _authService.login(username: username, password: password);
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo iniciar sesion: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.value(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error inicializando Firebase'));
        } else {
          return Scaffold(
            backgroundColor: const Color(0xFFFDFDFD),
            body: SafeArea(
              child: Column(
                children: [
                  // 1. ENCABEZADO CON CURVA Y IMAGEN
                  ClipPath(
                    clipper: HeaderClipper(),
                    child: Container(
                      width: double.infinity,
                      height: headerHeight,
                      color: primaryColor, // Fondo verde oscuro
                      child: Center(
                        // La imagen con un recorte ovalado/circular para el diseño
                        child: ClipOval(
                          child: SizedBox(
                            width: 400, // Tamaño de la imagen visible
                            height: 400,
                            child: Image.asset(
                              "assets/chica.png",
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                // Placeholder si la imagen no se encuentra
                                return Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  color: Colors.white,
                                  child: Center(
                                    child: Icon(Icons.person,
                                        size: 80,
                                        color: primaryColor.withOpacity(0.6)),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 2. CONTENIDO DEL FORMULARIO (Se expande para llenar el espacio restante y es scrollable)
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(
                          top: 18), // Espacio inicial después del encabezado
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // TÍTULO
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 25),
                            child: Text(
                              "Iniciar sesión",
                              style: TextStyle(
                                color: primaryColor,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          const SizedBox(height: 6),

                          // SUBTÍTULO
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 25),
                            child: Text(
                              "Comienza tu viaje de belleza",
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 16,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // LABEL USUARIO
                          const Padding(
                            padding: EdgeInsets.only(left: 25),
                            child: Text(
                              "Usuario",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),

                          // INPUT USUARIO
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 25),
                            child: TextField(
                              controller: userCtrl,
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.person_outline,
                                    color: primaryColor),
                                hintText: "Ingresa tu usuario",
                                focusedBorder: UnderlineInputBorder(
                                  borderSide:
                                      BorderSide(color: primaryColor, width: 2),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color: primaryColor, width: 1.4),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          // LABEL CONTRASEÑA
                          const Padding(
                            padding: EdgeInsets.only(left: 25),
                            child: Text(
                              "Contraseña",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),

                          // INPUT CONTRASEÑA
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 25),
                            child: TextField(
                              controller: passCtrl,
                              obscureText: true,
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.lock_outline,
                                    color: primaryColor),
                                hintText: "Ingresa tu contraseña",
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color: primaryColor, width: 1.4),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide:
                                      BorderSide(color: primaryColor, width: 2),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 30),

                          // BOTÓN LOGIN
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 25),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  minimumSize: const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                                onPressed: _isLoggingIn ? null : _loginWithApi,
                                child: _isLoggingIn
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        "Iniciar Sesión",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                        ),
                                      ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    userCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }
}
