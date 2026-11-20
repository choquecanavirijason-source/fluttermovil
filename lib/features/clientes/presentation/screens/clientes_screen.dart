import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/presentation/molecules/search_field.dart';
import '../../../../core/presentation/organisms/async_value_view.dart';
import '../../../../core/presentation/organisms/empty_state.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/client.dart';
import '../providers/clientes_provider.dart';

class ClientesScreen extends ConsumerStatefulWidget {
  const ClientesScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  ConsumerState<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends ConsumerState<ClientesScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(clientSearchProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(clientsListProvider);

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(title: const Text('Clientes'))
          : null,
      body: SafeArea(
        top: !widget.showAppBar,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchField(
                controller: _controller,
                hint: 'Buscar por nombre o teléfono…',
                onChanged: _onChanged,
                onClear: _controller.text.isEmpty
                    ? null
                    : () {
                        _controller.clear();
                        _onChanged('');
                      },
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(clientsListProvider),
                child: AsyncValueView<List<Client>>(
                  value: async,
                  onRetry: () => ref.invalidate(clientsListProvider),
                  builder: (clients) {
                    if (clients.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 80),
                          EmptyState(
                            icon: Icons.person_search_outlined,
                            title: 'No se encontraron clientes',
                            message: _controller.text.isEmpty
                                ? null
                                : 'Prueba con otro nombre o teléfono.',
                          ),
                        ],
                      );
                    }
                    final sorted = [...clients]..sort((a, b) => a.displayName
                        .toLowerCase()
                        .compareTo(b.displayName.toLowerCase()));
                    final rows = <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                        child: Text(
                          sorted.length == 1
                              ? '1 cliente'
                              : '${sorted.length} clientes',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ];
                    String? letter;
                    for (final c in sorted) {
                      final l = c.displayName.isEmpty
                          ? '#'
                          : c.displayName[0].toUpperCase();
                      if (l != letter) {
                        letter = l;
                        rows.add(_LetterHeader(letter: l));
                      }
                      rows.add(_ClientRow(client: c));
                    }
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                          16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
                      children: rows,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LetterHeader extends StatelessWidget {
  const _LetterHeader({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Text(
        letter,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.brandAccent, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client});

  final Client client;

  static const _avatarColors = [
    AppColors.brandPrimary,
    AppColors.avatarOlive,
    AppColors.statusReserva,
    AppColors.statusEnServicio,
    AppColors.statusSiendoAtendido,
    AppColors.statusAtendido,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = _avatarColors[client.id % _avatarColors.length];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRoutes.clienteDetalle, extra: client),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: color,
                  child: Text(client.initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        client.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyLarge?.copyWith(
                            color: cs.onSurface, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        client.phone.isNotEmpty ? client.phone : 'Sin teléfono',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (client.visitCount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    client.visitCount == 1
                        ? '1 visita'
                        : '${client.visitCount} visitas',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
