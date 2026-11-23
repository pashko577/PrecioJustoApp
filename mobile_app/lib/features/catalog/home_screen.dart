import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../models/models.dart';
import '../../services/catalog_repository.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final selected = ref.watch(selectedCategoryProvider);
    final products = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('PRECIO JUSTO')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(categoriesProvider);
          ref.invalidate(productsProvider);
          await ref.read(productsProvider.future);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: 56,
                child: categories.when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => const SizedBox.shrink(),
                  data: (list) => ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      _CategoryChip(label: 'Todo', selected: selected == null, onTap: () => _select(ref, null)),
                      for (final c in list)
                        _CategoryChip(label: c.name, selected: selected == c.slug, onTap: () => _select(ref, c.slug)),
                    ],
                  ),
                ),
              ),
            ),
            ...products.when(
              loading: () => [const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))],
              error: (e, _) => [SliverFillRemaining(child: _ErrorView(error: e))],
              data: (list) => list.isEmpty
                  ? [const SliverFillRemaining(child: Center(child: Text('No hay productos todavía.')))]
                  : [
                      SliverList.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _ProductRow(product: list[i]),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  void _select(WidgetRef ref, String? slug) => ref.read(selectedCategoryProvider.notifier).select(slug);
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final s = product.summary;
    final theme = Theme.of(context);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
      title: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${product.brand} · ${s.offerCount} ${s.offerCount == 1 ? 'tienda' : 'tiendas'}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (s.minPriceCents != null) ...[
            Text('desde', style: theme.textTheme.labelSmall),
            Text(formatCents(s.minPriceCents!), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ] else
            Text('Sin precio\nverificado', textAlign: TextAlign.end, style: theme.textTheme.bodySmall),
        ],
      ),
      onTap: () => context.push('/product/${product.id}'),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No se pudo cargar el catálogo.\n¿Están levantados los emuladores de Firebase?\n\n$error',
            textAlign: TextAlign.center,
          ),
        ),
      );
}
