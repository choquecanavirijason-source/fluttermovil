import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

// Datos falsos de usuarios y sus citas
final List<Map<String, dynamic>> usuarios = [
  {
    "nombre": "Ana López",
    "foto": "assets/chica.png",
    "fecha": "18-04-2001",
    "tipo": "Almendrados",
    "citas": [
      {
        "fecha": "31/12/2025",
        "detalles": [
          "Curva: C Tamaño: 12 mm Grosor: 0.15",
          "Efecto: Natural",
          "Tipo: Volumen ruso",
          "Duración: 3 a 4 semanas",
          "Tiempo: 1 h 30 min",
        ],
        "observaciones": [
          "Material hipoalergénico.",
          "Refuerzo externo para efecto alargado.",
          "Sin irritación."
        ]
      }
    ]
  },
  {
    "nombre": "María Torres",
    "foto": "assets/chica.png",
    "fecha": "22-07-1998",
    "tipo": "Foxy",
    "citas": [
      {
        "fecha": "28/12/2025",
        "detalles": [
          "Curva: D Tamaño: 13 mm Grosor: 0.20",
          "Efecto: Foxy",
          "Tipo: Megavolumen",
          "Duración: 4 a 5 semanas",
          "Tiempo: 2 horas",
        ],
        "observaciones": [
          "Cliente pidió look dramático.",
          "Fibra matte para mayor densidad.",
        ]
      }
    ]
  },
  {
    "nombre": "Lucía Ramírez",
    "foto": "assets/chica.png",
    "fecha": "05-11-1995",
    "tipo": "Natural Light",
    "citas": [
      {
        "fecha": "26/12/2025",
        "detalles": [
          "Curva: CC Tamaño: 11 mm Grosor: 0.10",
          "Efecto: Natural Light",
          "Tipo: Clásicas",
          "Duración: 2 a 3 semanas",
          "Tiempo: 1 hora",
        ],
        "observaciones": [
          "Acabado suave para uso diario.",
        ]
      }
    ]
  },
  {
    "nombre": "Sofía Mendoza",
    "foto": "assets/chica.png",
    "fecha": "14-02-2000",
    "tipo": "Dramático",
    "citas": [
      {
        "fecha": "31/11/2023",
        "detalles": [
          "Curva: D Tamaño: 14 mm",
          "Efecto: Dramático",
          "Tipo: Megavolumen",
        ],
        "observaciones": [
          "Se recomendó retoque a los 15 días.",
        ]
      }
    ]
  },
  {
    "nombre": "Valeria Gómez",
    "foto": "assets/chica.png",
    "fecha": "09-09-1999",
    "tipo": "Clásicas",
    "citas": [
      {
        "fecha": "15/10/2025",
        "detalles": [
          "Curva: B Tamaño: 10 mm Grosor: 0.12",
          "Efecto: Natural",
          "Tipo: Clásicas",
          "Duración: 2 semanas",
          "Tiempo: 50 min",
        ],
        "observaciones": [
          "Cliente primeriza.",
        ]
      }
    ]
  },
];

class ServicioPage extends StatefulWidget {
  final String nombre;
  const ServicioPage({super.key, required this.nombre});

  @override
  State<ServicioPage> createState() => _ServicioPageState();
}

class _ServicioPageState extends State<ServicioPage> {
  String searchText = "";
  List<Map<String, dynamic>> resultados = [];
  Map<String, dynamic>? usuarioSeleccionado;
  List<bool> isOpen = [];

  // NUEVO: para mostrar el modal/cámara de mapeo
  bool mostrarMapeo = false;
  CameraController? _camController;
  List<CameraDescription>? _cameras;
  bool _camInitialized = false;

  // NUEVO: para grabar video y controlar cámara
  bool _isRecording = false;
  FlashMode _flashMode = FlashMode.off;
  int _cameraIndex = 0;

  // Función para quitar tildes de un string
  String quitarTildes(String s) {
    return s
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U');
  }

  void buscarUsuarios(String nombre) {
    final filtro = quitarTildes(nombre.trim().toLowerCase());
    resultados = filtro.isEmpty
        ? []
        : usuarios
            .where((u) => quitarTildes(u["nombre"].toString().toLowerCase())
                .startsWith(filtro))
            .toList();
    setState(() {
      usuarioSeleccionado = null;
      isOpen = [];
    });
  }

  void seleccionarUsuario(Map<String, dynamic> usuario) {
    FocusScope.of(context).unfocus(); // Oculta el teclado
    setState(() {
      usuarioSeleccionado = usuario;
      isOpen = usuario["citas"] != null
          ? List.generate(usuario["citas"].length, (_) => false)
          : [];
      resultados = [];
      searchText = "";
    });
  }

  Future<void> _abrirMapeo() async {
    setState(() {
      mostrarMapeo = true;
    });
    if (_cameras == null) {
      _cameras = await availableCameras();
    }
    if (_cameras != null && _cameras!.isNotEmpty) {
      _camController = CameraController(
        _cameras![_cameraIndex],
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await _camController!.initialize();
      await _camController!.setFlashMode(_flashMode);
      setState(() {
        _camInitialized = true;
      });
    }
  }

  Future<void> _toggleFlash() async {
    if (_camController != null) {
      _flashMode =
          _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
      await _camController!.setFlashMode(_flashMode);
      setState(() {});
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.isEmpty) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras!.length;
    await _camController?.dispose();
    _camController = CameraController(
      _cameras![_cameraIndex],
      ResolutionPreset.medium,
      enableAudio: true,
    );
    await _camController!.initialize();
    await _camController!.setFlashMode(_flashMode);
    setState(() {});
  }

  Future<void> _startVideoRecording() async {
    if (_camController != null && !_isRecording) {
      try {
        await _camController!.startVideoRecording();
        setState(() {
          _isRecording = true;
        });
      } catch (e) {}
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_camController != null && _isRecording) {
      try {
        await _camController!.stopVideoRecording();
        setState(() {
          _isRecording = false;
        });
        // Ya no se copia ni se muestra la ruta del video
      } catch (e) {}
    }
  }

  void _cerrarMapeo() {
    setState(() {
      mostrarMapeo = false;
      _camInitialized = false;
      _isRecording = false;
    });
    _camController?.dispose();
    _camController = null;
  }

  Widget _fechaButton(int index, Map<String, dynamic> item) {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            setState(() => isOpen[index] = !isOpen[index]);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFBFA36F),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Fecha de aplicación: ${item["fecha"]}",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(
                  isOpen[index] ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white,
                )
              ],
            ),
          ),
        ),
        if (isOpen[index])
          Row(
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 6, left: 2, right: 2),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Detalles Tratamiento",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (item["detalles"] != null &&
                          item["detalles"].isNotEmpty)
                        ..._detalleTratamiento(item["detalles"]),
                      const SizedBox(height: 10),
                      const Text(
                        "Observaciones:",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      for (var o in item["observaciones"])
                        Text("• $o", style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "Ruta mapeo: assets/Mapeo.png.png",
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            TextButton(
                              onPressed: _abrirMapeo,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                backgroundColor: const Color(0xFFBFA36F),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                "Aplicar Mapeo",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 10),
      ],
    );
  }

  // Helper para mostrar los detalles en formato de la imagen
  List<Widget> _detalleTratamiento(List detalles) {
    // Intenta extraer los valores de los detalles
    String curva = "", tamano = "", grosor = "", efecto = "";
    for (var d in detalles) {
      if (d.toString().toLowerCase().contains("curva")) {
        final match = RegExp(r'Curva:\s*([A-Za-z]+)').firstMatch(d);
        if (match != null) curva = match.group(1) ?? "";
      }
      if (d.toString().toLowerCase().contains("tamaño")) {
        final match = RegExp(r'Tamaño:\s*([0-9]+)').firstMatch(d);
        if (match != null) tamano = match.group(1) ?? "";
      }
      if (d.toString().toLowerCase().contains("grosor")) {
        final match = RegExp(r'Grosor:\s*([0-9.]+)').firstMatch(d);
        if (match != null) grosor = match.group(1) ?? "";
      }
      if (d.toString().toLowerCase().contains("efecto")) {
        final match = RegExp(r'Efecto:\s*(.+)').firstMatch(d);
        if (match != null) efecto = match.group(1) ?? "";
      }
    }
    return [
      Row(
        children: [
          const Text("Curva:",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(width: 4),
          Text(curva, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 18),
          const Text("Tamaño:",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(width: 4),
          Text(tamano, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 18),
          const Text("Grosor:",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(width: 4),
          Text(grosor, style: const TextStyle(fontSize: 14)),
        ],
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          const Text("Efecto:",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(width: 4),
          Text(efecto,
              style: const TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF144C38),
      appBar: AppBar(
        backgroundColor: const Color(0xFF144C38),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Seleccionar Cliente",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Stack(
        children: [
          Container(
            color: const Color(0xFF144C38),
            child: SizedBox(
              width: double.infinity,
              height: MediaQuery.of(context).size.height,
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height,
                  ),
                  padding:
                      const EdgeInsets.symmetric(vertical: 25, horizontal: 25),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(35),
                      topRight: Radius.circular(35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 5),
                      const Text(
                        "Selección un cliente guardado",
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // BUSCADOR
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        height: 45,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFFF2F2F2),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  hintText: "Ingresa cliente",
                                  border: InputBorder.none,
                                ),
                                onChanged: (value) {
                                  searchText = value;
                                  buscarUsuarios(value);
                                },
                              ),
                            ),
                            Icon(Icons.search, color: Colors.grey),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Lista de resultados de búsqueda
                      if (resultados.isNotEmpty)
                        Column(
                          children: resultados.map((usuario) {
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: AssetImage(usuario["foto"]),
                              ),
                              title: Text(usuario["nombre"]),
                              subtitle: Text("📅 ${usuario["fecha"]}"),
                              onTap: () => seleccionarUsuario(usuario),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 25),
                      // Solo muestra la tarjeta y citas si hay usuario seleccionado
                      if (usuarioSeleccionado != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 25),
                          decoration: BoxDecoration(
                            color: const Color(0xFF144C38),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          width: double.infinity,
                          child: Column(
                            children: [
                              Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  image: DecorationImage(
                                    image: AssetImage(
                                        usuarioSeleccionado!["foto"]),
                                    fit: BoxFit.cover,
                                  ),
                                  border:
                                      Border.all(color: Colors.white, width: 4),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                usuarioSeleccionado!["nombre"],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                "📅 ${usuarioSeleccionado!["fecha"]}",
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 14),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                usuarioSeleccionado!["tipo"],
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25),
                        // LISTA DE FECHAS DINÁMICAS
                        ...List.generate(usuarioSeleccionado!["citas"].length,
                            (index) {
                          return _fechaButton(
                              index, usuarioSeleccionado!["citas"][index]);
                        }),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          // MODAL DE MAPEO
          if (mostrarMapeo)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.95),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    // Barra superior con botón cerrar
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 30),
                          onPressed: _cerrarMapeo,
                        ),
                        const Spacer(),
                      ],
                    ),
                    // Mapeo estático (imagen PNG/SVG encima)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: SizedBox(
                        height: 160,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Imagen de mapeo de pestañas (ajusta el asset)
                            Image.asset(
                              "assets/Mapeo.png.png", // <-- Cambia aquí la ruta
                              height: 150,
                              fit: BoxFit.contain,
                            ),
                            // Puedes agregar más overlays aquí si lo necesitas
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Cámara ocupando el resto de la pantalla
                    Expanded(
                      child: Stack(
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: _camInitialized && _camController != null
                                ? CameraPreview(_camController!)
                                : const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                          // Botones de control de cámara
                          if (_camInitialized)
                            Positioned(
                              bottom: 24,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      _flashMode == FlashMode.torch
                                          ? Icons.flash_on
                                          : Icons.flash_off,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    onPressed: _toggleFlash,
                                  ),
                                  const SizedBox(width: 32),
                                  GestureDetector(
                                    onTap: _isRecording
                                        ? _stopVideoRecording
                                        : _startVideoRecording,
                                    child: Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: _isRecording
                                            ? Colors.red
                                            : Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _isRecording
                                            ? Icons.stop
                                            : Icons.videocam,
                                        color: _isRecording
                                            ? Colors.white
                                            : Colors.black,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 32),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.cameraswitch,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    onPressed: _switchCamera,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
