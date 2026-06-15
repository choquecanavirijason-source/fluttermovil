import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/catalog_model.dart';
import '../../core/models/client_list_item.dart';
import '../../core/recommendation/eye_shape_analyzer.dart';
import '../../core/recommendation/lash_recommender.dart';
import '../../core/services/client_service.dart';
import '../../core/services/tracking_service.dart';
import '../../core/theme/app_theme.dart';

const Color _kBrand = AppColors.brand;
const Color _kBrandDark = AppColors.brandDark;
const Color _kGold = AppColors.gold;

/// Hoja para guardar la recomendación en la ficha (Tracking) de un cliente.
/// Permite elegir el cliente y ajustar diseño/efecto/volumen entre los sugeridos.
class SaveTrackingSheet extends StatefulWidget {
  const SaveTrackingSheet({
    super.key,
    required this.reco,
    required this.analysis,
    this.branchId,
  });

  final LashRecommendation reco;
  final EyeAnalysis analysis;
  final int? branchId;

  @override
  State<SaveTrackingSheet> createState() => _SaveTrackingSheetState();
}

class _SaveTrackingSheetState extends State<SaveTrackingSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<ClientListItem> _results = [];
  bool _searching = false;
  String? _searchError;

  ClientListItem? _selectedClient;

  int? _designId;
  int? _effectId;
  int? _volumeId;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _designId = _firstId(widget.reco.designs);
    _effectId = _firstId(widget.reco.effects);
    _volumeId = _firstId(widget.reco.volumes);
    _runSearch(''); // carga inicial de clientes recientes
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  int? _firstId(List<CatalogModel> list) => list.isEmpty ? null : list.first.id;

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(value));
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final list = await ClientService.search(query: query);
      if (!mounted) return;
      setState(() {
        _results = list;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = e.toString();
        _searching = false;
      });
    }
  }

  String _buildNotes() {
    final shape = widget.analysis.shape.catalogName;
    return 'Sugerencia IA · forma $shape';
  }

  Future<void> _save() async {
    final client = _selectedClient;
    if (client == null) return;

    setState(() => _saving = true);
    try {
      await TrackingService.create(
        clientId: client.id,
        eyeTypeId: widget.reco.eyeType?.id,
        effectId: _effectId,
        volumeId: _volumeId,
        lashDesignId: _designId,
        branchId: widget.branchId,
        designNotes: _buildNotes(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Guardar en ficha',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: _kBrandDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Registra el diseño sugerido en el seguimiento del cliente.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),

                // Cliente
                _label('Cliente'),
                if (_selectedClient != null)
                  _selectedClientTile()
                else
                  _clientSearch(),

                const SizedBox(height: 18),

                // Selección de modelos
                _chipsSection('Diseño', widget.reco.designs, _designId,
                    (id) => setState(() => _designId = id)),
                _chipsSection('Efecto', widget.reco.effects, _effectId,
                    (id) => setState(() => _effectId = id)),
                _chipsSection('Volumen', widget.reco.volumes, _volumeId,
                    (id) => setState(() => _volumeId = id)),

                if (widget.reco.eyeType != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.remove_red_eye_outlined,
                          size: 16, color: _kGold),
                      const SizedBox(width: 6),
                      Text(
                        'Tipo de ojo: ${widget.reco.eyeType!.name}',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kBrand,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed:
                        (_selectedClient == null || _saving) ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Guardando…' : 'Guardar en ficha'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: _kBrandDark,
          ),
        ),
      );

  Widget _selectedClientTile() {
    final c = _selectedClient!;
    return Container(
      decoration: BoxDecoration(
        color: _kBrand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBrand.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: _kBrand,
          child: Icon(Icons.person, color: Colors.white),
        ),
        title: Text(c.displayName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
        trailing: TextButton(
          onPressed: () => setState(() => _selectedClient = null),
          child: const Text('Cambiar', style: TextStyle(color: _kBrand)),
        ),
      ),
    );
  }

  Widget _clientSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Buscar cliente por nombre o teléfono…',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_searching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator(color: _kBrand)),
          )
        else if (_searchError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_searchError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          )
        else if (_results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text('No se encontraron clientes.',
                style: TextStyle(color: Colors.grey.shade600)),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final c = _results[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline, color: _kGold),
                  title: Text(c.displayName),
                  subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
                  onTap: () => setState(() => _selectedClient = c),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _chipsSection(
    String title,
    List<CatalogModel> items,
    int? selectedId,
    ValueChanged<int?> onChanged,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(title),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in items)
              ChoiceChip(
                label: Text(m.name),
                selected: selectedId == m.id,
                onSelected: (sel) => onChanged(sel ? m.id : null),
                selectedColor: _kBrand,
                labelStyle: TextStyle(
                  color: selectedId == m.id ? Colors.white : _kBrandDark,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
