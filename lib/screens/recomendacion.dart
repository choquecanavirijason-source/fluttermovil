import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/config/api_config.dart';
import '../core/models/catalog_model.dart';
import '../core/recommendation/eye_shape_analyzer.dart';
import '../core/recommendation/lash_recommender.dart';
import '../core/services/catalog_service.dart';
import '../core/theme/app_theme.dart';
import '../recommendation_args.dart';
import 'widgets/save_tracking_sheet.dart';

const Color _kBrand = AppColors.brand;
const Color _kBrandDark = AppColors.brandDark;
const Color _kGold = AppColors.gold;

/// Pantalla del flujo IA: muestra la foto de la clienta, la forma de ojo
/// detectada on-device y los modelos del catálogo recomendados.
class RecomendacionScreen extends StatefulWidget {
  const RecomendacionScreen({super.key, required this.args});

  final RecommendationArgs args;

  @override
  State<RecomendacionScreen> createState() => _RecomendacionScreenState();
}

class _RecomendacionScreenState extends State<RecomendacionScreen> {
  bool _loading = true;
  String? _error;
  LashRecommendation? _reco;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await CatalogService.fetchAll();
      if (!mounted) return;
      final reco = LashRecommender.build(
        analysis: widget.args.analysis,
        eyeTypes: catalog[CatalogKind.eyeType] ?? const [],
        designs: catalog[CatalogKind.lashDesign] ?? const [],
        effects: catalog[CatalogKind.effect] ?? const [],
        volumes: catalog[CatalogKind.volume] ?? const [],
      );
      setState(() {
        _reco = reco;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final analysis = widget.args.analysis;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 320,
            backgroundColor: _kBrand,
            foregroundColor: Colors.white,
            title: const Text('Recomendación IA'),
            flexibleSpace: FlexibleSpaceBar(
              background: _PhotoHeader(
                bytes: widget.args.photoPngBytes,
                mirror: widget.args.mirrorPhoto,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(
                        child: CircularProgressIndicator(color: _kBrand),
                      ),
                    )
                  : _error != null
                      ? _errorView(_error!)
                      : _content(analysis),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSaveSheet(LashRecommendation reco) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SaveTrackingSheet(
        reco: reco,
        analysis: widget.args.analysis,
        branchId: ApiConfig.defaultBranchId,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recomendación guardada en la ficha del cliente.'),
          backgroundColor: _kBrand,
        ),
      );
    }
  }

  Widget _errorView(String message) {
    return Column(
      children: [
        const SizedBox(height: 30),
        const Icon(Icons.cloud_off, size: 44, color: Colors.grey),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.redAccent),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _kBrand),
          onPressed: _build,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      ],
    );
  }

  Widget _content(EyeAnalysis analysis) {
    final reco = _reco;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Forma detectada
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kGold.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.remove_red_eye, color: _kGold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Forma detectada: ${analysis.shape.catalogName}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _kBrandDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    analysis.shape.description,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!analysis.reliable)
          _noticeBox(
            'No se detectó el rostro con claridad. La sugerencia es aproximada; '
            'vuelve a capturar centrando la mirada para mejor precisión.',
            warning: true,
          ),

        if (reco != null && reco.reason.isNotEmpty) ...[
          const SizedBox(height: 14),
          _reasonCard(reco.reason),
        ],

        if (reco != null) ...[
          _section('Diseños recomendados', reco.designs),
          _section('Efecto', reco.effects),
          _section('Volumen', reco.volumes),
          if (reco.eyeType != null) _section('Tu tipo de ojo', [reco.eyeType!]),
          if (!reco.hasAnyItem)
            _noticeBox(
              'Aún no hay modelos en el catálogo. Pide al administrador que cargue '
              'los diseños (con imagen) para ver sugerencias aquí.',
            ),
        ],

        if (reco != null && reco.hasAnyItem) ...[
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _kBrand,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _openSaveSheet(reco),
              icon: const Icon(Icons.save_outlined),
              label: const Text(
                'Guardar en ficha del cliente',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],

        const SizedBox(height: 20),
        Text(
          'Sugerencia generada en el dispositivo a partir de la forma del ojo. '
          'Es orientativa; la operaria decide el diseño final.',
          style: TextStyle(
            fontSize: 11.5,
            color: Colors.grey.shade500,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _reasonCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kBrand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBrand.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome, color: _kGold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: _kBrandDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticeBox(String text, {bool warning = false}) {
    final color = warning ? Colors.orange : Colors.blueGrey;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(warning ? Icons.info_outline : Icons.inventory_2_outlined,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<CatalogModel> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _kBrandDark,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _RecoCard(model: items[i]),
          ),
        ),
      ],
    );
  }
}

class _PhotoHeader extends StatelessWidget {
  const _PhotoHeader({required this.bytes, required this.mirror});

  final Uint8List? bytes;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    if (bytes == null || bytes!.isEmpty) {
      return Container(
        color: _kBrand,
        child: const Center(
          child: Icon(Icons.face_retouching_natural,
              color: Colors.white24, size: 80),
        ),
      );
    }
    Widget img = Image.memory(
      bytes!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
    if (mirror) {
      img = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
        child: img,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        img,
        // Degradado inferior para legibilidad del título.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black54],
            ),
          ),
        ),
      ],
    );
  }
}

class _RecoCard extends StatelessWidget {
  const _RecoCard({required this.model});

  final CatalogModel model;

  @override
  Widget build(BuildContext context) {
    final url = model.imageUrl;
    return SizedBox(
      width: 130,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1.5,
        shadowColor: Colors.black12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: url == null
                    ? _fallback()
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                                ? child
                                : Container(
                                    color: const Color(0xFFF0EDE4),
                                    child: const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: _kGold),
                                      ),
                                    ),
                                  ),
                        errorBuilder: (context, error, stack) => _fallback(),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                model.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _kBrandDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => Container(
        color: _kGold.withValues(alpha: 0.12),
        child: const Center(
          child: Icon(Icons.remove_red_eye_outlined, color: _kGold, size: 32),
        ),
      );
}
