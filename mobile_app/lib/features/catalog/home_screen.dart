import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../services/catalog_repository.dart';
import '../auth/auth_providers.dart';
import 'product_row.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(catalogFeedProvider);
    final isSignedIn = ref.watch(authStateProvider).value != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PRECIO JUSTO'),
        actions: [
          IconButton(
            key: const Key('favorites-nav'),
            tooltip: 'Mis productos',
            icon: const Icon(Icons.favorite_border),
            onPressed: () => context.push('/favorites'),
          ),
          IconButton(
            key: const Key('alerts-nav'),
            tooltip: 'Mis alertas',
            icon: const Icon(Icons.notifications_none),
            onPressed: () => context.push('/alerts'),
          ),
          IconButton(
            key: const Key('account-button'),
            tooltip: isSignedIn ? 'Mi cuenta' : 'Iniciar sesión',
            icon: Icon(isSignedIn ? Icons.account_circle : Icons.account_circle_outlined),
            onPressed: () => context.push(isSignedIn ? '/profile' : '/login'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(categoriesProvider);
          ref.invalidate(catalogFeedProvider);
          await ref.read(catalogFeedProvider.future);
        },
        child: NotificationListener<ScrollNotification>(
          // Carga la siguiente página al acercarse al final de la lista.
          onNotification: (n) {
            if (n.metrics.extentAfter < 400) ref.read(catalogFeedProvider.notifier).loadMore();
            return false;
          },
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: _SearchBox()),
              const SliverToBoxAdapter(child: _CategoryBar()),
              ...feed.when(
                loading: () => [const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))],
                error: (e, _) => [SliverFillRemaining(child: _ErrorView(error: e))],
                data: (data) => data.items.isEmpty
                    ? [const SliverFillRemaining(child: Center(child: Text('No hay productos en esta categoría todavía.')))]
                    : [
                        SliverList.separated(
                          itemCount: data.items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) => ProductRow(product: data.items[i]),
                        ),
                        SliverToBoxAdapter(child: _FeedFooter(feed: data)),
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            key: const Key('open-search'),
            borderRadius: BorderRadius.circular(28),
            onTap: () => context.push('/search'),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Icon(Icons.search),
                SizedBox(width: 12),
                Expanded(child: Text('Busca un producto, marca o código')),
              ]),
            ),
          ),
        ),
      );
}

/// Categorías en dos niveles: principales y, al elegir una, sus subcategorías.
class _CategoryBar extends ConsumerWidget {
  const _CategoryBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value;
    if (categories == null) return const SizedBox(height: 56);
    final selected = ref.watch(selectedCategoryProvider);
    final top = selected == null ? null : topLevelOf(selected, categories);
    final children = top == null ? const <Category>[] : categories.where((c) => c.parentSlug == top.slug).toList();
    void select(String? slug) => ref.read(selectedCategoryProvider.notifier).select(slug);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChipRow(children: [
          _Chip(label: 'Todo', selected: selected == null, onTap: () => select(null)),
          for (final c in categories.where((c) => c.isTopLevel))
            _Chip(
              label: c.name,
              icon: categoryIcon(c.icon),
              selected: top?.slug == c.slug,
              onTap: () => select(c.slug),
            ),
        ]),
        if (children.isNotEmpty)
          _ChipRow(children: [
            _Chip(label: 'Todo ${top!.name}', selected: selected == top.slug, onTap: () => select(top.slug)),
            for (final c in children) _Chip(label: c.name, selected: selected == c.slug, onTap: () => select(c.slug)),
          ]),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: children,
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          avatar: icon == null || selected ? null : Icon(icon, size: 18),
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );
}

class _FeedFooter extends ConsumerWidget {
  const _FeedFooter({required this.feed});

  final CatalogFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (feed.loadingMore) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    if (feed.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: OutlinedButton(
            onPressed: () => ref.read(catalogFeedProvider.notifier).loadMore(),
            child: const Text('Cargar más'),
          ),
        ),
      );
    }
    return const SizedBox(height: 32);
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
