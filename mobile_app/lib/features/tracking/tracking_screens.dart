import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../models/models.dart';
import '../../models/tracking.dart';
import '../../services/catalog_repository.dart';
import '../../services/tracking_repository.dart';
import '../catalog/product_row.dart';
import 'tracking_actions.dart';

/// Mejor precio verificado actual de un producto (`null` si no hay o está vencido).
int? currentBestCents(WidgetRef ref, Product? product) {
  if (product == null) return null;
  final stores = ref.watch(storesProvider).value ?? const <String, StoreInfo>{};
  final s = product.summary;
  return ProductRow.summaryIsFresh(s, stores[s.minPriceStoreCode])
      ? s.minPriceCents
      : null;
}

/// Cambio de precio desde que se guardó: texto para el usuario (`null` si no aplica).
String? priceChangeText(int? savedCents, int? currentCents) {
  if (savedCents == null || currentCents == null || savedCents == currentCents) {
    return null;
  }
  final diff = currentCents - savedCents;
  return diff < 0
      ? 'Bajó ${formatCents(-diff)} desde que lo guardaste'
      : 'Subió ${formatCents(diff)} desde que lo guardaste';
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).hintColor),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------------ Favoritos y listas

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Mis productos'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Favoritos'),
            Tab(text: 'Listas'),
          ],
        ),
      ),
      body: const TabBarView(children: [_FavoritesTab(), _WishlistsTab()]),
    ),
  );
}

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(favoritesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (items) => items.isEmpty
              ? const _Empty(
                  icon: Icons.favorite_border,
                  title: 'Aún no guardaste productos',
                  body:
                      'Toca "Guardar" en un producto para seguir su precio desde aquí.',
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _FavoriteRow(favorite: items[i]),
                ),
        );
  }
}

class _FavoriteRow extends ConsumerWidget {
  const _FavoriteRow({required this.favorite});

  final Favorite favorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productProvider(favorite.productId)).value;
    final current = currentBestCents(ref, product);
    final change = priceChangeText(favorite.priceAtSaveCents, current);
    final theme = Theme.of(context);
    return ListTile(
      title: Text(
        product?.name ?? favorite.productName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            current == null
                ? 'Sin precio verificado ahora'
                : 'Mejor precio: ${formatCents(current)}',
          ),
          if (change != null)
            Text(
              change,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      trailing: IconButton(
        tooltip: 'Quitar de favoritos',
        icon: const Icon(Icons.favorite),
        onPressed: () => ref
            .read(trackingRepositoryProvider)
            ?.removeFavorite(favorite.productId),
      ),
      onTap: () => context.push('/product/${favorite.productId}'),
    );
  }
}

class _WishlistsTab extends ConsumerWidget {
  const _WishlistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(wishlistsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-list'),
        icon: const Icon(Icons.add),
        label: const Text('Nueva lista'),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final name = await askName(context, title: 'Nueva lista');
          if (name == null) return;
          try {
            await ref.read(trackingRepositoryProvider)!.createWishlist(name);
          } on TrackingFailure catch (e) {
            messenger.showSnackBar(SnackBar(content: Text(e.message)));
          }
        },
      ),
      body: lists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) => items.isEmpty
            ? const _Empty(
                icon: Icons.list_alt,
                title: 'No tienes listas',
                body:
                    'Agrupa productos que piensas comprar juntos, por ejemplo "Cocina nueva".',
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: Text(items[i].name),
                  subtitle: Text('${items[i].productIds.length} productos'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/favorites/list/${items[i].id}'),
                ),
              ),
      ),
    );
  }
}

class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(wishlistProvider(listId)).value;
    final repo = ref.watch(trackingRepositoryProvider);
    if (list == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(list.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) async {
              if (action == 'rename') {
                final name = await askName(
                  context,
                  title: 'Renombrar lista',
                  initial: list.name,
                );
                if (name != null) await repo?.renameWishlist(list.id, name);
              } else if (action == 'delete') {
                final router = GoRouter.of(context);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('¿Eliminar la lista?'),
                    content: Text(
                      'Se eliminará "${list.name}". Los productos no se borran del catálogo.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Eliminar'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await repo?.deleteWishlist(list.id);
                  router.pop();
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Renombrar')),
              PopupMenuItem(value: 'delete', child: Text('Eliminar lista')),
            ],
          ),
        ],
      ),
      body: list.productIds.isEmpty
          ? const _Empty(
              icon: Icons.playlist_add,
              title: 'La lista está vacía',
              body: 'En un producto, toca "Lista" para agregarlo aquí.',
            )
          : ListView.separated(
              itemCount: list.productIds.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final id = list.productIds[i];
                final product = ref.watch(productProvider(id)).value;
                return Dismissible(
                  key: ValueKey(id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Theme.of(context).colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete_outline),
                  ),
                  onDismissed: (_) => repo?.removeFromWishlist(list.id, id),
                  child: product == null
                      ? const ListTile(title: Text('Cargando…'))
                      : ProductRow(product: product),
                );
              },
            ),
    );
  }
}

// ------------------------------------------------------------------ Alertas

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis alertas')),
      body: ref
          .watch(alertsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (items) => items.isEmpty
                ? const _Empty(
                    icon: Icons.notifications_none,
                    title: 'No tienes alertas',
                    body:
                        'En un producto, toca "Crear alerta" y te avisaremos cuando baje al precio que quieres.',
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _AlertRow(alert: items[i]),
                  ),
          ),
    );
  }
}

class _AlertRow extends ConsumerWidget {
  const _AlertRow({required this.alert});

  final PriceAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productProvider(alert.productId)).value;
    final current = currentBestCents(ref, product);
    final met = alert.isMetBy(current);
    final paused = alert.status == AlertStatus.paused;
    final theme = Theme.of(context);

    return ListTile(
      title: Text(
        product?.name ?? alert.productName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Avisar si baja a ${formatCents(alert.targetPriceCents)} o menos',
          ),
          Text(
            current == null
                ? 'Sin precio verificado ahora'
                : 'Mejor precio actual: ${formatCents(current)}',
          ),
          if (met && !paused)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '¡Ya cumple!',
                  key: const Key('alert-met'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          if (paused) Text('Pausada', style: theme.textTheme.bodySmall),
        ],
      ),
      isThreeLine: true,
      trailing: Switch(
        value: !paused,
        onChanged: (on) =>
            ref.read(trackingRepositoryProvider)?.setAlertPaused(alert, !on),
      ),
      onTap: product == null
          ? null
          : () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialogForm(
                product: product,
                currentBestCents: current,
                existing: alert,
              ),
            ),
      onLongPress: () => context.push('/product/${alert.productId}'),
    );
  }
}
