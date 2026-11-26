import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../core/offer_rules.dart';
import '../../models/models.dart';
import '../../services/catalog_repository.dart';
import '../../ui/brand.dart';
import '../../ui/common.dart';

/// Estado del precio del resumen de un producto, igual para la card y la fila.
enum SummaryPriceState { fresh, unconfirmed, none }

SummaryPriceState summaryPriceState(PriceSummary s, StoreInfo? store) {
  if (s.minPriceCents == null) return SummaryPriceState.none;
  return ProductRow.summaryIsFresh(s, store)
      ? SummaryPriceState.fresh
      : SummaryPriceState.unconfirmed;
}

String storesLabel(int n) =>
    n == 0 ? 'Sin ofertas aún' : '$n ${n == 1 ? 'tienda' : 'tiendas'}';

/// Fila de producto (listas y resultados compactos): foto, nombre, tienda y precio.
class ProductRow extends ConsumerWidget {
  const ProductRow({super.key, required this.product});

  final Product product;

  /// RN-01: el precio del resumen es vigente si se verificó dentro del plazo de su tienda.
  /// La verificación puede venir del propio resumen o de la última corrida completa de la tienda.
  static bool summaryIsFresh(
    PriceSummary s,
    StoreInfo? store, {
    DateTime? now,
  }) {
    var checked = s.lastCheckedAt;
    final run = store?.lastCompleteRunAt;
    if (run != null && (checked == null || run.isAfter(checked))) checked = run;
    return checked != null &&
        isFresh(
          checked,
          store?.freshnessMinutes ?? defaultFreshnessMinutes,
          now: now,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = product.summary;
    final theme = Theme.of(context);
    final stores =
        ref.watch(storesProvider).value ?? const <String, StoreInfo>{};
    final state = summaryPriceState(s, stores[s.minPriceStoreCode]);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/product/${product.id}'),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: ProductImage(url: product.imageUrl, padding: 6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${product.brand.isEmpty ? '' : '${product.brand}, '}${storesLabel(s.storeCount)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: switch (state) {
                    SummaryPriceState.fresh => [
                      Text('desde', style: theme.textTheme.labelSmall),
                      Text(
                        formatCents(s.minPriceCents!),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                    SummaryPriceState.unconfirmed => [
                      Text(
                        'Precio por\nconfirmar',
                        textAlign: TextAlign.end,
                        style: _pending,
                      ),
                    ],
                    SummaryPriceState.none => [
                      Text(
                        'Sin precio\nverificado',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _pending = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: AppColors.amberInk,
  height: 1.3,
);

/// Card de la grilla: foto, marca, nombre, precio más bajo y la tienda que lo tiene.
class ProductCard extends ConsumerWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.favorite,
    this.onOpen,
  });

  final Product product;

  /// Se llama justo antes de abrir el detalle (por ejemplo, para recordar la búsqueda).
  final VoidCallback? onOpen;

  /// Botón de favorito superpuesto a la foto (opcional).
  final Widget? favorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = product.summary;
    final theme = Theme.of(context);
    final stores =
        ref.watch(storesProvider).value ?? const <String, StoreInfo>{};
    final storeCode = s.minPriceStoreCode;
    final store = storeCode == null ? null : stores[storeCode];
    final state = summaryPriceState(s, store);
    final drop = state == SummaryPriceState.fresh && s.hasRecentDrop();

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          onOpen?.call();
          context.push('/product/${product.id}');
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // La foto toma el alto que deja el texto: la card nunca se desborda.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ProductImage(url: product.imageUrl),
                      if (drop)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Pill(
                            label: '-${s.priceDropPercent}%',
                            background: AppColors.magenta,
                            foreground: Colors.white,
                          ),
                        ),
                      if (favorite != null)
                        Positioned(top: 6, right: 6, child: favorite!),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 128,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (product.brand.isNotEmpty)
                      Text(
                        product.brand,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                    const Spacer(),
                    switch (state) {
                      // Se encoge antes que desbordarse (precios de 5 cifras en cards angostas).
                      SummaryPriceState.fresh => FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              formatCents(s.minPriceCents!),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                            if (drop) ...[
                              const SizedBox(width: 6),
                              Text(
                                formatCents(s.priceDropFromCents!),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SummaryPriceState.unconfirmed => const Text(
                        'Precio por confirmar',
                        style: _pending,
                      ),
                      SummaryPriceState.none => Text(
                        'Sin precio verificado',
                        style: theme.textTheme.bodySmall,
                      ),
                    },
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (storeCode != null && s.offerCount > 0) ...[
                          StoreBadge(
                            code: storeCode,
                            name: store?.name ?? '',
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              store?.name ?? storeCode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ] else
                          const Spacer(),
                        Text(
                          storesLabel(s.storeCount),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Íconos de las categorías de primer nivel (`categories.icon`).
IconData categoryIcon(String? name) => switch (name) {
  'devices' => Icons.devices,
  'memory' => Icons.memory,
  'kitchen' => Icons.kitchen,
  'chair' => Icons.chair,
  'checkroom' => Icons.checkroom,
  'spa' => Icons.spa,
  'sports_soccer' => Icons.sports_soccer,
  'toys' => Icons.toys,
  'child_care' => Icons.child_care,
  'directions_car' => Icons.directions_car,
  'handyman' => Icons.handyman,
  'menu_book' => Icons.menu_book,
  _ => Icons.category,
};

/// Foto de una categoría de primer nivel (`assets/categories/{slug}.jpg`), si existe.
const categoryPhotos = {
  'tecnologia',
  'computacion',
  'electrodomesticos',
  'hogar',
  'moda',
  'belleza',
  'deportes',
  'juguetes',
  'bebes',
  'automotriz',
  'ferreteria',
  'libros',
};
