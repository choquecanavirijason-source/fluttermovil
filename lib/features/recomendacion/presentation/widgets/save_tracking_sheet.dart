import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env.dart';
import '../../../../core/presentation/molecules/search_field.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../catalogo/domain/entities/catalog_item.dart';
import '../../../clientes/data/clients_repository_impl.dart';
import '../../../clientes/domain/entities/client.dart';
import '../../../tracking/data/tracking_repository_impl.dart';
import '../../domain/lash_recommendation.dart';

/// Hoja para guardar la recomendación en la ficha (Tracking) de un cliente.
class SaveTrackingSheet extends ConsumerStatefulWidget {
  const SaveTrackingSheet({
    super.key,
    required this.reco,
    required this.shapeName,
  });

  final LashRecommendation reco;
  final String shapeName;

  @override
  ConsumerState<SaveTrackingSheet> createState() => _SaveTrackingSheetState();
}

class _SaveTrackingSheetState extends ConsumerState<SaveTrackingSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<Client> _results = [];
  bool _searching = false;
  String? _searchError;
  Client? _selected;

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
    _runSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  int? _firstId(List<CatalogItem> l) => l.isEmpty ? null : l.first.id;

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(v));
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final list =
          await ref.read(clientsRepositoryProvider).list(search: query);
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

  Future<void> _save() async {
    final client = _selected;
    if (client == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(trackingRepositoryProvider).create(
            clientId: client.id,
            eyeTypeId: widget.reco.eyeType?.id,
            effectId: _effectId,
            volumeId: _volumeId,
            lashDesignId: _designId,
            branchId: Env.defaultBranchId,
            designNotes: 'Sugerencia IA · forma ${widget.shapeName}',
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
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
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Guardar en ficha',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface)),
              const SizedBox(height: 4),
              Text('Registra el diseño sugerido en el seguimiento del cliente.',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              _label('Cliente', cs),
              if (_selected != null)
                _selectedClientTile(cs)
              else
                _clientSearch(cs),
              const SizedBox(height: 18),
              _chips('Diseño', widget.reco.designs, _designId,
                  (id) => setState(() => _designId = id), cs),
              _chips('Efecto', widget.reco.effects, _effectId,
                  (id) => setState(() => _effectId = id), cs),
              _chips('Volumen', widget.reco.volumes, _volumeId,
                  (id) => setState(() => _volumeId = id), cs),
              if (widget.reco.eyeType != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.remove_red_eye_outlined,
                      size: 16, color: AppColors.goldAccent),
                  const SizedBox(width: 6),
                  Text('Tipo de ojo: ${widget.reco.eyeType!.name}',
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurfaceVariant)),
                ]),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_selected == null || _saving) ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.black87))
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Guardando…' : 'Guardar en ficha'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: cs.onSurface)),
      );

  Widget _selectedClientTile(ColorScheme cs) {
    final c = _selected!;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.brandPrimary,
          child: Icon(Icons.person, color: Colors.white),
        ),
        title: Text(c.displayName,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: cs.onSurface)),
        subtitle: c.phone.isNotEmpty
            ? Text(c.phone, style: TextStyle(color: cs.onSurfaceVariant))
            : null,
        trailing: TextButton(
          onPressed: () => setState(() => _selected = null),
          child: const Text('Cambiar'),
        ),
      ),
    );
  }

  Widget _clientSearch(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchField(
          controller: _searchCtrl,
          hint: 'Buscar cliente por nombre o teléfono…',
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 10),
        if (_searching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_searchError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_searchError!,
                style: const TextStyle(
                    color: AppColors.offlineRed, fontSize: 13)),
          )
        else if (_results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text('No se encontraron clientes.',
                style: TextStyle(color: cs.onSurfaceVariant)),
          )
        else
          // Sin scroll anidado: la hoja (DraggableScrollableSheet) ya scrollea.
          Column(
            children: [
              for (final c in _results)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline,
                      color: AppColors.goldAccent),
                  title: Text(c.displayName,
                      style: TextStyle(color: cs.onSurface)),
                  subtitle: c.phone.isNotEmpty
                      ? Text(c.phone,
                          style: TextStyle(color: cs.onSurfaceVariant))
                      : null,
                  onTap: () => setState(() => _selected = c),
                ),
            ],
          ),
      ],
    );
  }

  Widget _chips(
    String title,
    List<CatalogItem> items,
    int? selectedId,
    ValueChanged<int?> onChanged,
    ColorScheme cs,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(title, cs),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in items)
              ChoiceChip(
                label: Text(m.name),
                selected: selectedId == m.id,
                onSelected: (sel) => onChanged(sel ? m.id : null),
              ),
          ],
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
