import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/money.dart';
import '../../core/offer_rules.dart';
import '../../models/models.dart';
import '../../services/catalog_repository.dart';
import '../history/price_history_section.dart';
import '../tracking/tracking_actions.dart';
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
            : p.mergedInto != null
            ? _MergedRedirect(target: p.mergedInto!)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(p.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text([p.brand, if (p.model != null) p.model!].join(' · ')),
                  const SizedBox(height: 12),
                  TrackingActions(
                    product: p,
                    currentBestCents: offers.value == null
                        ? null
                        : compareOffers(
                            offers.value!,
                            (o) => isFresh(
                              o.lastCheckedAt,
                              freshness[o.storeCode] ?? defaultFreshnessMinutes,
                            ),
                          ).best?.priceCents,
                  ),
                  if (p.attributes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in p.attributes.entries)
                          Chip(
                            label: Text('${e.key}: ${e.value}'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Ofertas',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ...offers.when(
                    loading: () => [
                      const Center(child: CircularProgressIndicator()),
                    ],
                    error: (e, _) => [Text('Error al cargar ofertas: $e')],
                    data: (list) => list.isEmpty
                        ? [
                            const Text(
                              'Todavía no encontramos ofertas para este producto.',
                            ),
                          ]
                        : _buildOffers(list, freshness),
                  ),
                  const SizedBox(height: 24),
                  PriceHistorySection(productId: productId),
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

  List<Widget> _buildOffers(
    List<StoreOffer> offers,
    Map<String, int> freshness,
  ) {
    bool fresh(StoreOffer o) => isFresh(
      o.lastCheckedAt,
      freshness[o.storeCode] ?? defaultFreshnessMinutes,
    );
    final comparison = compareOffers(offers, fresh);
    return [
      ComparisonHeader(comparison: comparison, totalOffers: offers.length),
      const SizedBox(height: 8),
      for (final o in offers)
        OfferTile(
          offer: o,
          fresh: fresh(o),
          isBest: identical(o, comparison.best),
          differenceCents: differenceFromBest(o, comparison, fresh),
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

/// Resumen de la comparación: mejor precio, tiendas comparadas y ahorro posible (RF-04).
class ComparisonHeader extends StatelessWidget {
  const ComparisonHeader({
    super.key,
    required this.comparison,
    required this.totalOffers,
  });

  final OfferComparison comparison;
  final int totalOffers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = comparison.best;
    if (best == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            totalOffers == 0
                ? 'Todavía no encontramos ofertas para este producto.'
                : 'Ninguna oferta tiene un precio verificado y disponible en este momento.',
          ),
        ),
      );
    }
    final savings = comparison.maxSavingsCents;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mejor precio verificado', style: theme.textTheme.labelMedium),
            Text(
              '${formatCents(best.priceCents)} en ${best.storeName}',
              key: const Key('best-price'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${comparison.storeCount == 1 ? 'Comparado en 1 tienda' : 'Comparado en ${comparison.storeCount} tiendas'}'
              '${comparison.comparableCount > comparison.storeCount ? ' (${comparison.comparableCount} ofertas)' : ''}'
              '${savings != null && savings > 0 ? ' · ahorras hasta ${formatCents(savings)}' : ''}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Un producto unificado lleva al producto conservado (enlaces antiguos, favoritos, notificaciones).
class _MergedRedirect extends StatefulWidget {
  const _MergedRedirect({required this.target});

  final String target;

  @override
  State<_MergedRedirect> createState() => _MergedRedirectState();
}

class _MergedRedirectState extends State<_MergedRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) GoRouter.of(context).replace('/product/${widget.target}');
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}
