import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/presentation/molecules/search_field.dart';
import '../../../../core/presentation/organisms/async_value_view.dart';
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
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Text('No se encontraron clientes.',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                          ),
                        ],
                      );
                    }
                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                          16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
                      itemCount: clients.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _ClientCard(client: clients[i]),
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

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client});

  final Client client;

  String get _initials {
    final parts = client.displayName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final s = parts.first;
    return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.brandPrimary,
          child: Text(_initials,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
        ),
        title: Text(client.displayName,
            style: TextStyle(
                color: cs.onSurface, fontWeight: FontWeight.w600)),
        subtitle: client.phone.isNotEmpty
            ? Text(client.phone, style: TextStyle(color: cs.onSurfaceVariant))
            : null,
        trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        onTap: () => context.push(AppRoutes.clienteDetalle, extra: client),
      ),
    );
  }
}
