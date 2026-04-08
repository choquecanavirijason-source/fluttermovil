import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:test_face/core/config/api_config.dart';
import 'package:test_face/core/models/mobile_appointment.dart';
import 'package:test_face/core/services/agenda_service.dart';
import 'package:test_face/core/services/auth_service.dart';
import 'package:test_face/screens/probador.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _ticketSearchController = TextEditingController();
  String _ticketSearch = '';
  final Set<int> _selectedTicketIds = <int>{};

  List<MobileAppointment> _iaMobileTickets = [];
  bool _ticketsLoading = false;
  String? _ticketsError;

  @override
  void initState() {
    super.initState();
    _loadIaMobileTickets();
  }

  Future<void> _loadIaMobileTickets() async {
    if (AuthSession.accessToken == null || AuthSession.accessToken!.isEmpty) {
      setState(() {
        _ticketsLoading = false;
        _ticketsError = 'Inicia sesión para ver tickets con IA.';
        _iaMobileTickets = [];
      });
      return;
    }

    setState(() {
      _ticketsLoading = true;
      _ticketsError = null;
    });

    try {
      final list = await AgendaService.fetchMobileIaTickets(
        branchId: ApiConfig.defaultBranchId,
      );
      if (!mounted) return;
      setState(() {
        _iaMobileTickets = list;
        _ticketsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ticketsError = e.toString();
        _iaMobileTickets = [];
        _ticketsLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _ticketSearchController.dispose();
    super.dispose();
  }

  /// WIDGET PARA MANEJAR IMÁGENES NO ENCONTRADAS
  Widget _safeImage(String path, {double? width, double? height}) {
    return Image.asset(
      path,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.grey.shade200, Colors.grey.shade300],
            ),
          ),
          child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _ticketSearch.toLowerCase();
    final filteredTickets = _iaMobileTickets.where((t) {
      if (q.isEmpty) return true;
      return t.ticketCode.toLowerCase().contains(q) ||
          t.clientDisplayName.toLowerCase().contains(q) ||
          t.servicesSummary.toLowerCase().contains(q) ||
          t.status.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // IMAGEN DE CABECERA
            Stack(
              children: [
                SizedBox(
                  height: 400,
                  width: double.infinity,
                  child: _safeImage("assets/chica2.png"),
                ),
                EyeTrackingBackButton(onTap: () => Navigator.pop(context)),
              ],
            ),

            Transform.translate(
              offset: const Offset(0, -30),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(35)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 30),
                child: Column(
                  children: [
                    const Text(
                      "Descubre Tu Mejor Mirada",
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 25),

                    // BOTONES DE ACCIÓN
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _actionButton(Icons.remove_red_eye, "Probador", const Color(0xFF0C4B36), () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const ProbadorScreen()));
                        }),
                        _actionButton(Icons.auto_awesome_mosaic, "Servicio", Colors.black, () => context.push('/servicio')),
                        _actionButton(Icons.person_outline, "Cliente", const Color(0xFFBFA36F), () => context.push('/cliente')),
                      ],
                    ),

                    const SizedBox(height: 35),

                    // SECCIÓN TICKETS (móvil + IA desde API)
                    _sectionHeader("Tickets IA (servicio móvil)"),
                    const SizedBox(height: 8),
                    Text(
                      "Citas con IA y categoría móvil en la sucursal configurada.",
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _ticketSearchController,
                      onChanged: (val) => setState(() => _ticketSearch = val),
                      decoration: InputDecoration(
                        hintText: "Buscar por código, cliente o servicio...",
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_ticketsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_ticketsError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _ticketsError!,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                            ),
                            TextButton.icon(
                              onPressed: _loadIaMobileTickets,
                              icon: const Icon(Icons.refresh),
                              label: const Text("Reintentar"),
                            ),
                          ],
                        ),
                      )
                    else if (filteredTickets.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          "No hay tickets que coincidan.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    else
                      ...filteredTickets.map(_buildTicketCard),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      ],
    );
  }

  Widget _buildTicketCard(MobileAppointment t) {
    final timeLine = t.startTime ?? '—';
    final branch = t.branchName != null ? ' · ${t.branchName}' : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: const Icon(Icons.confirmation_number_outlined, color: Color(0xFFBFA36F)),
        title: Text(
          t.clientDisplayName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${t.ticketCode} · ${t.status}$branch'),
            const SizedBox(height: 2),
            Text(t.servicesSummary, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            Text(timeLine, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
        isThreeLine: true,
        trailing: Checkbox(
          value: _selectedTicketIds.contains(t.id),
          onChanged: (v) => setState(() {
            if (v == true) {
              _selectedTicketIds.add(t.id);
            } else {
              _selectedTicketIds.remove(t.id);
            }
          }),
        ),
      ),
    );
  }
}

/// BOTÓN ATRÁS
class EyeTrackingBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const EyeTrackingBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 50,
      left: 20,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(10),
              color: Colors.white.withOpacity(0.2),
              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

