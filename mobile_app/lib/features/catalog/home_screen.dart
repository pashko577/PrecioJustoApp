import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../core/money.dart';
import '../../models/models.dart';
import '../../services/catalog_repository.dart';
import '../../ui/brand.dart';
import '../../ui/common.dart';
import '../notifications/notifications.dart';
import '../tracking/tracking_actions.dart';
import 'product_row.dart';
import 'recent.dart';

const _pad = EdgeInsets.symmetric(horizontal: 16);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(catalogFeedProvider);
    final selected = ref.watch(selectedCategoryProvider);
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final selectedName = categories
        .where((c) => c.slug == selected)
        .firstOrNull
        ?.name;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(categoriesProvider);
          ref.invalidate(storesProvider);
          ref.invalidate(catalogFeedProvider);
          await ref.read(catalogFeedProvider.future);
        },
        child: NotificationListener<ScrollNotification>(
          // Carga la siguiente página al acercarse al final de la lista.
          onNotification: (n) {
            if (n.metrics.extentAfter < 600) {
              ref.read(catalogFeedProvider.notifier).loadMore();
            }
            return false;
          },
          child: CustomScrollView(
            slivers: [
              const SliverSafeArea(
                bottom: false,
                sliver: SliverToBoxAdapter(child: _Header()),
              ),
              const SliverToBoxAdapter(child: _StoresHero()),
              const SliverToBoxAdapter(child: _RecentlyViewed()),
              const SliverToBoxAdapter(child: _StoreStrip()),
              const SliverToBoxAdapter(child: _CategoryGrid()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: _pad,
                  child: SectionHeader(
                    title: selectedName == null
                        ? 'Mejores precios de hoy'
                        : 'Mejores precios en $selectedName',
                    action: selected == null ? null : 'Ver todo',
                    onAction: () => ref
                        .read(selectedCategoryProvider.notifier)
                        .select(null),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: _SubcategoryChips()),
              ...feed.when(
                loading: () => [
                  const SliverToBoxAdapter(child: _GridSkeleton()),
                ],
                error: (e, _) => [
                  SliverToBoxAdapter(child: _ErrorView(error: e)),
                ],
                data: (data) => data.items.isEmpty
                    ? [
                        const SliverToBoxAdapter(
                          child: EmptyState(
                            icon: Icons.storefront_outlined,
                            title: 'Aún no hay productos aquí',
                            body:
                                'Estamos sumando tiendas y productos. Prueba con otra categoría o busca por nombre.',
                          ),
                        ),
                      ]
                    : [
                        SliverPadding(
                          padding: _pad,
                          sliver: SliverGrid.builder(
                            gridDelegate: productGridDelegate,
                            itemCount: data.items.length,
                            itemBuilder: (_, i) => ProductCard(
                              product: data.items[i],
                              favorite: FavoriteIconButton(
                                product: data.items[i],
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _FeedFooter(feed: data)),
                      ],
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: navBarClearance),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grilla de cards: 2 columnas en celular y más en pantallas anchas (tablet, web).
const productGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 240,
  mainAxisSpacing: 12,
  crossAxisSpacing: 12,
  mainAxisExtent: 286,
);

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [BrandLogo(), Spacer(), NotificationsBell()]),
        const SizedBox(height: 14),
        Text(
          '¿Qué quieres\ncomparar hoy?',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: const BorderSide(color: AppColors.line),
            ),
            child: InkWell(
              key: const Key('open-search'),
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => context.go('/search'),
              child: const SizedBox(
                height: 52,
                child: Row(
                  children: [
                    SizedBox(width: 14),
                    Icon(Icons.search, color: AppColors.ink),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Busca producto, marca o código',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.muted, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    ),
  );
}

/// Banner principal: cuántas tiendas comparamos y sus logos.
/// Cuando el resumen del producto guarde el precio anterior, aquí irán «Bajaron de precio».
class _StoresHero extends ConsumerWidget {
  const _StoresHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stores = activeStores(ref);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          gradient: const LinearGradient(
            colors: [AppColors.ink, AppColors.ink2, AppColors.blue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              bottom: -60,
              child: Container(
                width: 180,
                height: 180,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x8CE11D8E), Color(0x00E11D8E)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Pill(
                    label: 'Precios verificados',
                    background: AppColors.teal,
                    foreground: AppColors.ink,
                    icon: Icons.verified,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    stores.isEmpty
                        ? 'Compara antes de comprar'
                        : 'Comparamos ${stores.length} tiendas del Perú por ti',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Mira quién lo tiene más barato, revisa el historial y crea una alerta si quieres esperar.',
                    style: TextStyle(
                      color: Color(0xD9FFFFFF),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  if (stores.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 34,
                      child: Stack(
                        children: [
                          for (var i = 0; i < stores.length && i < 7; i++)
                            Positioned(
                              left: i * 24.0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: AppColors.ink,
                                  shape: BoxShape.circle,
                                ),
                                child: StoreBadge(
                                  code: stores[i].code,
                                  name: stores[i].name,
                                  size: 30,
                                ),
                              ),
                            ),
                        ],
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

/// Tiendas que se consultan de verdad, primero las que tienen logo.
List<StoreInfo> activeStores(WidgetRef ref) {
  final all = ref.watch(storesProvider).value?.values ?? const <StoreInfo>[];
  return all.where((s) => s.active).toList()..sort((a, b) {
    final la = storeBrand(a.code).hasLogo ? 0 : 1,
        lb = storeBrand(b.code).hasLogo ? 0 : 1;
    return la != lb ? la - lb : a.name.compareTo(b.name);
  });
}

class _RecentlyViewed extends ConsumerWidget {
  const _RecentlyViewed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(recentProductsProvider);
    if (ids.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: _pad,
            child: SectionHeader(title: 'Vistos recientemente'),
          ),
          SizedBox(
            height: 170,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: _pad,
              itemCount: ids.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _MiniCard(productId: ids[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniCard extends ConsumerWidget {
  const _MiniCard({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(productProvider(productId)).value;
    final stores =
        ref.watch(storesProvider).value ?? const <String, StoreInfo>{};
    final fresh =
        p != null &&
        summaryPriceState(p.summary, stores[p.summary.minPriceStoreCode]) ==
            SummaryPriceState.fresh;
    return SizedBox(
      width: 128,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/product/$productId'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    height: 84,
                    width: double.infinity,
                    child: ProductImage(url: p?.imageUrl, padding: 6),
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    p?.name ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, height: 1.3),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    fresh
                        ? formatCents(p.summary.minPriceCents!)
                        : 'Por confirmar',
                    style: TextStyle(
                      fontSize: fresh ? 14 : 12,
                      fontWeight: FontWeight.w700,
                      color: fresh ? AppColors.ink : AppColors.amberInk,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreStrip extends ConsumerWidget {
  const _StoreStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stores = activeStores(ref);
    if (stores.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: _pad,
            child: SectionHeader(title: 'Tiendas que comparamos'),
          ),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: _pad,
              itemCount: stores.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) => SizedBox(
                width: 64,
                child: Column(
                  children: [
                    StoreBadge(
                      code: stores[i].code,
                      name: stores[i].name,
                      size: 48,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      stores[i].name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Categorías principales con foto de un producto real. Tocar una filtra la grilla.
class _CategoryGrid extends ConsumerWidget {
  const _CategoryGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value;
    if (categories == null) return const SizedBox(height: 24);
    final top = categories.where((c) => c.isTopLevel).toList();
    final selected = ref.watch(selectedCategoryProvider);
    final selectedTop = selected == null
        ? null
        : topLevelOf(selected, categories)?.slug;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Categorías'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
              mainAxisExtent: 104,
            ),
            itemCount: top.length,
            itemBuilder: (_, i) {
              final c = top[i];
              final isSelected = selectedTop == c.slug;
              return _CategoryTile(
                category: c,
                tone: AppColors.tones[i % AppColors.tones.length],
                selected: isSelected,
                onTap: () => ref
                    .read(selectedCategoryProvider.notifier)
                    .select(isSelected ? null : c.slug),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = categoryPhotos.contains(category.slug);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 72,
              width: double.infinity,
              decoration: BoxDecoration(
                color: tone,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: selected ? AppColors.ink : Colors.transparent,
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.all(8),
              child: hasPhoto
                  ? Image.asset(
                      'assets/categories/${category.slug}.jpg',
                      fit: BoxFit.contain,
                      color: tone,
                      colorBlendMode: BlendMode.multiply,
                    )
                  : Icon(
                      categoryIcon(category.icon),
                      color: AppColors.ink,
                      size: 28,
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              shortCategoryNames[category.slug] ?? category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nombres cortos para las fichas de categoría (el nombre completo se usa en los títulos).
const shortCategoryNames = {
  'electrodomesticos': 'Electro',
  'computacion': 'Cómputo',
};

/// Subcategorías de la categoría elegida.
class _SubcategoryChips extends ConsumerWidget {
  const _SubcategoryChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value;
    final selected = ref.watch(selectedCategoryProvider);
    if (categories == null || selected == null) return const SizedBox.shrink();
    final top = topLevelOf(selected, categories);
    if (top == null) return const SizedBox.shrink();
    final children = categories.where((c) => c.parentSlug == top.slug).toList();
    if (children.isEmpty) return const SizedBox.shrink();
    void select(String slug) =>
        ref.read(selectedCategoryProvider.notifier).select(slug);

    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final c in [top, ...children])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c.slug == top.slug ? 'Todo' : c.name),
                selected: selected == c.slug,
                onSelected: (_) => select(c.slug),
              ),
            ),
        ],
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: _pad,
    child: GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: productGridDelegate,
      itemCount: 4,
      itemBuilder: (_, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1 / 0.85,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
              for (final w in [0.4, 0.9, 0.6])
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
                  child: FractionallySizedBox(
                    widthFactor: w,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FeedFooter extends ConsumerWidget {
  const _FeedFooter({required this.feed});

  final CatalogFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (feed.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (feed.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: OutlinedButton(
            onPressed: () => ref.read(catalogFeedProvider.notifier).loadMore(),
            child: const Text('Cargar más productos'),
          ),
        ),
      );
    }
    return const SizedBox(height: 16);
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => EmptyState(
    icon: Icons.cloud_off_outlined,
    title: 'No pudimos cargar los productos',
    body: 'Revisa tu conexión e inténtalo de nuevo.\n\n$error',
    action: FilledButton(
      onPressed: () => ref.invalidate(catalogFeedProvider),
      child: const Text('Reintentar'),
    ),
  );
}
