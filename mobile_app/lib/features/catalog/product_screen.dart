import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../core/offer_rules.dart';
import '../../models/models.dart';
import '../../services/catalog_repository.dart';
import '../../services/tracking_repository.dart';
import '../../ui/brand.dart';
import '../../ui/common.dart';
import '../history/price_history_section.dart';
import '../offers/offer_tile.dart';
import '../tracking/tracking_actions.dart';
import 'recent.dart';

class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  @override
  void initState() {
    super.initState();
    // «Vistos recientemente» en Inicio (solo en memoria).
    Future.microtask(() => ref.read(recentProductsProvider.notifier).add(widget.productId));
  }

  @override
  Widget build(BuildContext context) {
    final product = ref.watch(productProvider(widget.productId));
    final offers = ref.watch(offersProvider(widget.productId));
    final freshness = ref.watch(storeFreshnessProvider).value ?? const {};
    bool fresh(StoreOffer o) => isFresh(o.lastCheckedAt, freshness[o.storeCode] ?? defaultFreshnessMinutes);
    final comparison = offers.value == null ? null : compareOffers(offers.value!, fresh);
    final p = product.value;

    return Scaffold(
      body: product.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(text: 'No pudimos cargar el producto. Revisa tu conexión.\n\n$e'),
        data: (p) => p == null
            ? const _Message(text: 'No encontramos este producto. Puede que la tienda lo haya retirado.')
            : p.mergedInto != null
                ? _MergedRedirect(target: p.mergedInto!)
                : _Body(product: p, offers: offers, comparison: comparison, fresh: fresh),
      ),
      bottomNavigationBar: p == null || p.mergedInto != null ? null : _ActionBar(product: p, best: comparison?.best),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.product, required this.offers, required this.comparison, required this.fresh});

  final Product product;
  final AsyncValue<List<StoreOffer>> offers;
  final OfferComparison? comparison;
  final bool Function(StoreOffer) fresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = product;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _TopBar(product: p, currentBestCents: comparison?.best?.priceCents),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: SizedBox(height: 240, child: ProductImage(url: p.imageUrl, background: AppColors.surface, padding: 24)),
          ),
          const SizedBox(height: 18),
          if (p.brand.isNotEmpty) Text([p.brand, if (p.model != null) p.model!].join(', '), style: theme.textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(p.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          ...offers.when(
            loading: () => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
            error: (e, _) => [Text('No pudimos cargar las ofertas: $e')],
            data: (list) => [
              ComparisonHeader(comparison: comparison!, totalOffers: list.length),
              if (list.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(
                  'Precios en ${list.length} ${list.length == 1 ? 'tienda' : 'tiendas'}',
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 12),
                ..._offerTiles(list),
              ],
            ],
          ),
          const SizedBox(height: 28),
          PriceHistorySection(productId: p.id),
          if (p.attributes.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text('Características', style: theme.textTheme.titleMedium?.copyWith(fontSize: 17)),
            const SizedBox(height: 12),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (final (i, e) in p.attributes.entries.indexed) ...[
                    if (i > 0) const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Row(
                        children: [
                          Expanded(child: Text(e.key, style: theme.textTheme.bodySmall?.copyWith(fontSize: 13))),
                          const SizedBox(width: 16),
                          Flexible(
                            child: Text('${e.value}', textAlign: TextAlign.end, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Cada tienda publica sus propios precios y pueden cambiar. Confirma el total en la tienda antes de pagar.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  List<Widget> _offerTiles(List<StoreOffer> list) {
    final c = comparison!;
    final min = c.best?.priceCents;
    final max = c.highest?.priceCents;
    final showBars = c.comparableCount >= 2 && min != null && max != null;
    return [
      for (final o in list)
        OfferTile(
          offer: o,
          fresh: fresh(o),
          isBest: identical(o, c.best),
          differenceCents: differenceFromBest(o, c, fresh),
          barFraction: showBars && isComparable(o, fresh) ? (max == min ? 1.0 : 0.4 + 0.6 * (o.priceCents - min) / (max - min)) : null,
          onOpenStore: o.productUrl.isEmpty ? null : () => openStore(o.productUrl),
        ),
    ];
  }
}

Future<void> openStore(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.product, this.currentBestCents});

  final Product product;
  final int? currentBestCents;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
        children: [
          _RoundButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Volver',
            onTap: () => context.canPop() ? context.pop() : context.go('/'),
          ),
          const Spacer(),
          _RoundButton(
            key: const Key('wishlist-button'),
            icon: Icons.playlist_add,
            tooltip: 'Agregar a una lista',
            onTap: () => openWishlistSheet(context, ref, product),
          ),
          const SizedBox(width: 8),
          FavoriteIconButton(product: product, currentBestCents: currentBestCents, size: 44),
        ],
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(dimension: 44, child: Icon(icon, size: 20, color: AppColors.ink)),
          ),
        ),
      );
}

/// Barra inferior: alerta de precio e ir a la tienda más barata.
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.product, required this.best});

  final Product product;
  final StoreOffer? best;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = ref.watch(alertForProductProvider(product.id));
    return Container(
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.line))),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
          child: Row(
            children: [
              FilledButton.icon(
                key: const Key('alert-button'),
                style: FilledButton.styleFrom(
                  backgroundColor: alert == null ? AppColors.sky : AppColors.cream,
                  foregroundColor: alert == null ? AppColors.ink : AppColors.amberInk,
                ),
                icon: Icon(alert == null ? Icons.notifications_none : Icons.notifications_active, size: 20),
                label: Text(alert == null ? 'Avisarme si baja' : 'Bajo ${formatCents(alert.targetPriceCents)}'),
                onPressed: () => openAlertForm(context, ref, product, currentBestCents: best?.priceCents),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(best == null ? 'Sin oferta vigente' : 'Ir a ${best!.storeName}', overflow: TextOverflow.ellipsis),
                  onPressed: best == null || best!.productUrl.isEmpty ? null : () => openStore(best!.productUrl),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resumen de la comparación: mejor precio, tienda, ahorro posible y tiendas comparadas (RF-04).
class ComparisonHeader extends StatelessWidget {
  const ComparisonHeader({super.key, required this.comparison, required this.totalOffers});

  final OfferComparison comparison;
  final int totalOffers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = comparison.best;
    if (best == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Text(
          totalOffers == 0
              ? 'Todavía no encontramos ofertas para este producto.'
              : 'Ninguna oferta tiene un precio verificado y disponible en este momento.',
          style: const TextStyle(color: AppColors.amberInk, fontWeight: FontWeight.w500, fontSize: 13),
        ),
      );
    }
    final savings = comparison.maxSavingsCents;
    final highest = comparison.highest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mejor precio verificado', style: theme.textTheme.labelMedium),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatCents(best.priceCents),
                        key: const Key('best-price'),
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1, height: 1.15, fontFeatures: tabularFigures),
                      ),
                    ),
                    Text(
                      comparison.storeCount == 1
                          ? 'Comparado en 1 tienda'
                          : 'Comparado en ${comparison.storeCount} tiendas'
                              '${comparison.comparableCount > comparison.storeCount ? ' (${comparison.comparableCount} ofertas)' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: Column(
                  children: [
                    StoreBadge(code: best.storeCode, name: best.storeName, size: 40),
                    const SizedBox(height: 4),
                    Text(
                      'en ${best.storeName}',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (savings != null && savings > 0 && highest != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Row(
              children: [
                const Icon(Icons.check_rounded, size: 18, color: AppColors.tealInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ahorras hasta ${formatCents(savings)} frente a ${highest.storeName}',
                    style: const TextStyle(color: AppColors.tealInk, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.all(8), child: BackButton()),
            Expanded(
              child: EmptyState(icon: Icons.search_off, title: 'Producto no disponible', body: text),
            ),
          ],
        ),
      );
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
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}
