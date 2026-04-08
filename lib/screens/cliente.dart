import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../core/config/api_config.dart';
import '../core/models/client_list_item.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';

class ClientePage extends StatefulWidget {
  const ClientePage({super.key});

  @override
  State<ClientePage> createState() => _ClientePageState();
}

class _ClientePageState extends State<ClientePage> {
  final List<ClientListItem> _clientes = [];

  String _searchQuery = '';
  String _sortedColumn = 'nombre';
  bool _isAscending = true;

  bool _loading = true;
  String? _error;

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadClients() async {
    if (AuthSession.accessToken == null || AuthSession.accessToken!.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Inicia sesion para ver clientes.';
        _clientes.clear();
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await ApiClient.get(
        ApiConfig.clients,
        queryParameters: {
          'skip': 0,
          'limit': 100,
          if (_searchQuery.trim().isNotEmpty) 'search': _searchQuery.trim(),
        },
      );

      final decoded = jsonDecode(body);
      if (decoded is! List) {
        throw FormatException('Se esperaba una lista de clientes');
      }

      final list = decoded
          .map((e) => ClientListItem.fromApi(Map<String, dynamic>.from(e as Map)))
          .toList();

      if (!mounted) return;
      setState(() {
        _clientes
          ..clear()
          ..addAll(list);
        _applySort();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _clientes.clear();
      });
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _loadClients();
    });
  }

  int _compareClients(ClientListItem a, ClientListItem b, String column) {
    switch (column) {
      case 'nombre':
        return a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase());
      case 'fecha':
        final byFecha =
            a.fechaUltimaVisita.compareTo(b.fechaUltimaVisita);
        if (byFecha != 0) return byFecha;
        return a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase());
      case 'tipo':
        final byTipo =
            a.tipoOjo.toLowerCase().compareTo(b.tipoOjo.toLowerCase());
        if (byTipo != 0) return byTipo;
        return a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase());
      default:
        return 0;
    }
  }

  void _applySort() {
    _clientes.sort((a, b) {
      final c = _compareClients(a, b, _sortedColumn);
      return _isAscending ? c : -c;
    });
  }

  void sortColumn(String column) {
    setState(() {
      if (_sortedColumn == column) {
        _isAscending = !_isAscending;
      } else {
        _sortedColumn = column;
        _isAscending = true;
      }
      _applySort();
    });
  }

  Widget buildHeader(String title, String column) {
    return Expanded(
      flex: column == 'nombre' ? 3 : 2,
      child: InkWell(
        onTap: () => sortColumn(column),
        child: Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_sortedColumn == column)
              Icon(
                _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: Colors.white,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Lista de Clientes'),
        backgroundColor: const Color(0xFF0C4B36),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadClients,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar por nombre, teléfono…',
                  border: InputBorder.none,
                  icon: Icon(Icons.search),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Colors.red.shade800, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              color: const Color(0xFF0C4B36),
              child: Row(
                children: [
                  buildHeader('Nombre', 'nombre'),
                  buildHeader('Fecha', 'fecha'),
                  buildHeader('Tipo ojo', 'tipo'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading && _clientes.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _loadClients,
                      child: _clientes.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 48),
                                Center(
                                  child: Text(
                                    'No hay clientes',
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _clientes.length,
                              itemBuilder: (context, index) {
                                final cliente = _clientes[index];
                                final fecha = cliente.fechaUltimaVisita;
                                final tipo = cliente.tipoOjo;

                                return Slidable(
                                  key: ValueKey(cliente.id),
                                  endActionPane: ActionPane(
                                    motion: const ScrollMotion(),
                                    children: [
                                      SlidableAction(
                                        onPressed: (_) {},
                                        backgroundColor: const Color(0xFF0C4B36),
                                        foregroundColor: Colors.white,
                                        icon: Icons.visibility,
                                        label: 'Ver',
                                      ),
                                    ],
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: GestureDetector(
                                            onTap: () => GoRouter.of(context)
                                                .push('/servicio', extra: cliente.displayName),
                                            child: Text(cliente.displayName),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            fecha,
                                            style: TextStyle(
                                              color: fecha.isEmpty
                                                  ? Colors.black26
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            tipo,
                                            style: TextStyle(
                                              color: tipo.isEmpty
                                                  ? Colors.black26
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
