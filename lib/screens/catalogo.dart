import 'package:flutter/material.dart';

import '../core/models/catalog_model.dart';
import '../core/services/auth_service.dart';
import '../core/services/catalog_service.dart';
import '../core/theme/app_theme.dart';

/// Paleta de marca (centralizada en AppColors).
const Color _kBrand = AppColors.brand;
const Color _kBrandDark = AppColors.brandDark;
const Color _kGold = AppColors.gold;

/// Catálogo de modelos de pestañas (mismos modelos que la app admin):
/// Diseños, Tipos de ojo, Efectos y Volúmenes — con sus imágenes.
class CatalogoScreen extends StatefulWidget {
  const CatalogoScreen({super.key, this.initialKind = CatalogKind.lashDesign});

  final CatalogKind initialKind;

  @override
  State<CatalogoScreen> createState() => _CatalogoScreenState();
}

class _CatalogoScreenState extends State<CatalogoScreen>
    with SingleTickerProviderStateMixin {
  static const _kinds = CatalogKind.values;

  late final TabController _tabController;
  final Map<CatalogKind, List<CatalogModel>> _data = {};
  final Map<CatalogKind, String?> _errors = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _kinds.length,
      vsync: this,
      initialIndex: _kinds.indexOf(widget.initialKind),
    );
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (AuthSession.accessToken == null || AuthSession.accessToken!.isEmpty) {
      setState(() {
        _loading = false;
        for (final k in _kinds) {
          _errors[k] = 'Inicia sesión para ver el catálogo.';
        }
      });
      return;
    }

    setState(() => _loading = true);
    for (final kind in _kinds) {
      try {
        final list = await CatalogService.fetch(kind);
        if (!mounted) return;
        setState(() {
          _data[kind] = list;
          _errors[kind] = null;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _data[kind] = [];
          _errors[kind] = e.toString();
        });
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reload(CatalogKind kind) async {
    try {
      final list = await CatalogService.fetch(kind);
      if (!mounted) return;
      setState(() {
        _data[kind] = list;
        _errors[kind] = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errors[kind] = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        backgroundColor: _kBrand,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Modelos de pestañas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: _kGold,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: [for (final k in _kinds) Tab(text: k.label)],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [for (final k in _kinds) _buildTab(k)],
      ),
    );
  }

  Widget _buildTab(CatalogKind kind) {
    if (_loading && (_data[kind] == null)) {
      return const Center(child: CircularProgressIndicator(color: _kBrand));
    }

    final error = _errors[kind];
    if (error != null) {
      return _ErrorState(message: error, onRetry: () => _reload(kind));
    }

    final items = _data[kind] ?? const [];
    if (items.isEmpty) {
      return _EmptyState(kind: kind, onRetry: () => _reload(kind));
    }

    return RefreshIndicator(
      color: _kBrand,
      onRefresh: () => _reload(kind),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 0.74,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _CatalogCard(
          model: items[i],
          onTap: () => _openDetail(items[i]),
        ),
      ),
    );
  }

  void _openDetail(CatalogModel model) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CatalogDetailSheet(model: model),
    );
  }
}

/// Tarjeta de un modelo con su imagen.
class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.model, required this.onTap});

  final CatalogModel model;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 1.5,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                child: _CatalogImage(model: model),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _kBrandDark,
                    ),
                  ),
                  if (model.description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      model.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Imagen del modelo con placeholder/spinner/fallback.
class _CatalogImage extends StatelessWidget {
  const _CatalogImage({required this.model, this.fit = BoxFit.cover});

  final CatalogModel model;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final url = model.imageUrl;
    if (url == null) return const _ImageFallback();

    return Image.network(
      url,
      fit: fit,
      width: double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: const Color(0xFFF0EDE4),
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: _kGold),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stack) => const _ImageFallback(),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kGold.withValues(alpha: 0.12),
      child: const Center(
        child: Icon(Icons.remove_red_eye_outlined, color: _kGold, size: 40),
      ),
    );
  }
}

/// Detalle (bottom sheet) con imagen grande y descripción.
class _CatalogDetailSheet extends StatelessWidget {
  const _CatalogDetailSheet({required this.model});

  final CatalogModel model;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: controller,
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: 10),
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
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _CatalogImage(model: model, fit: BoxFit.cover),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kGold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        model.kind.label,
                        style: const TextStyle(
                          color: _kBrandDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      model.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: _kBrandDark,
                      ),
                    ),
                    if (model.description != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        model.description!,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _kBrand),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.kind, required this.onRetry});

  final CatalogKind kind;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 90),
        Icon(Icons.style_outlined, size: 52, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'No hay ${kind.label.toLowerCase()} para mostrar.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, color: _kBrand),
            label: const Text('Actualizar', style: TextStyle(color: _kBrand)),
          ),
        ),
      ],
    );
  }
}
