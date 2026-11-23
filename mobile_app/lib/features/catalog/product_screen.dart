import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/offer_rules.dart';
import '../../models/models.dart';
import '../../services/catalog_repository.dart';
import '../offers/offer_tile.dart';

class ProductScreen extends ConsumerWidget {
  const ProductScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productProvider(productId));
    final offers = ref.watch(offersProvider(productId));
    final freshness = ref.watch(storeFreshnessProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('Comparar precios')),
      body: product.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (p) => p == null
            ? const Center(child: Text('Producto no encontrado'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(p.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text([p.brand, if (p.model != null) p.model!].join(' · ')),
                  if (p.attributes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in p.attributes.entries)
                          Chip(label: Text('${e.key}: ${e.value}'), visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text('Ofertas', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...offers.when(
                    loading: () => [const Center(child: CircularProgressIndicator())],
                    error: (e, _) => [Text('Error al cargar ofertas: $e')],
                    data: (list) => list.isEmpty
                        ? [const Text('Todavía no encontramos ofertas para este producto.')]
                        : _buildOffers(list, freshness),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Los precios son observaciones de PRECIO JUSTO en las tiendas y pueden cambiar. '
                    'Confirma el precio final en la tienda.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildOffers(List<StoreOffer> offers, Map<String, int> freshness) {
    bool fresh(StoreOffer o) => isFresh(o.lastCheckedAt, freshness[o.storeCode] ?? defaultFreshnessMinutes);
    // La lista ya viene ordenada: la primera vigente y disponible es la mejor oferta.
    final best = offers.where((o) => fresh(o) && o.availability == Availability.available).firstOrNull;
    return [
      for (final o in offers)
        OfferTile(
          offer: o,
          fresh: fresh(o),
          isBest: identical(o, best),
          onOpenStore: o.productUrl.isEmpty ? null : () => _open(o.productUrl),
        ),
    ];
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
