import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Probador/core/theme/app_colors.dart';
import 'package:Probador/features/clientes/domain/entities/client.dart';
import 'package:Probador/features/clientes/presentation/providers/clientes_provider.dart';

/// Bottom sheet para elegir el cliente al que se le guarda el diseño actual.
/// Búsqueda con debounce de 350ms contra [clientSearchProvider].
class ClientPickerSheet extends ConsumerStatefulWidget {
  final ValueChanged<Client> onSelect;

  const ClientPickerSheet({super.key, required this.onSelect});

  @override
  ConsumerState<ClientPickerSheet> createState() => _ClientPickerSheetState();
}

class _ClientPickerSheetState extends ConsumerState<ClientPickerSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(clientSearchProvider.notifier).state = value;
    });
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final s = parts.first;
    return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final asyncClients = ref.watch(clientsListProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Seleccionar cliente',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Buscar cliente…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: asyncClients.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (clients) => clients.isEmpty
                  ? const Center(child: Text('Sin clientes encontrados'))
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: clients.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final c = clients[i];
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.actionGreen,
                            child: Text(
                              _initials(c.displayName),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          title: Text(
                            c.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
                          trailing: const Icon(
                            Icons.check_circle_outline,
                            color: AppColors.actionGreen,
                          ),
                          onTap: () => widget.onSelect(c),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
