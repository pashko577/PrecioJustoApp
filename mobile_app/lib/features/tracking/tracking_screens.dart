import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../models/models.dart';
import '../../models/tracking.dart';
import '../../services/catalog_repository.dart';
import '../../services/tracking_repository.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../ui/common.dart';
import '../catalog/product_row.dart';
import '../notifications/notifications.dart';
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

String _shortDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
}

/// Cambio de precio desde que se guardó: texto para el usuario (`null` si no aplica).
String? priceChangeText(int? savedCents, int? currentCents) {
  if (savedCents == null ||
      currentCents == null ||
      savedCents == currentCents) {
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
  Widget build(BuildContext context) =>
      EmptyState(icon: icon, title: title, body: body);
}

/// Tarjeta de un producto seguido: foto, nombre, precio y detalle (cambio de precio, alerta).
class _TrackedCard extends StatelessWidget {
  const _TrackedCard({
    required this.imageUrl,
    required this.title,
    required this.lines,
    required this.onTap,
    this.trailing,
    this.onLongPress,
  });

  final String? imageUrl;
  final String title;
  final List<Widget> lines;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: ProductImage(url: imageUrl, padding: 6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...lines,
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
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
        automaticallyImplyLeading: false,
        title: const Text('Guardados'),
        bottom: const TabBar(
          labelColor: AppColors.ink,
          indicatorColor: AppColors.magenta,
          dividerColor: AppColors.line,
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
              : ListView.builder(
                  padding: const EdgeInsets.only(
                    top: 8,
                    bottom: navBarClearance,
                  ),
                  itemCount: items.length,
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
    final dropped = change != null && change.startsWith('Bajó');
    return _TrackedCard(
      imageUrl: product?.imageUrl,
      title: product?.name ?? favorite.productName,
      lines: [
        Text(
          current == null
              ? 'Sin precio verificado ahora'
              : 'Mejor precio: ${formatCents(current)}',
          style: TextStyle(
            fontSize: current == null ? 12 : 15,
            fontWeight: FontWeight.w700,
            color: current == null ? AppColors.amberInk : AppColors.ink,
            fontFeatures: tabularFigures,
          ),
        ),
        if (change != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Pill(
              label: change,
              background: dropped ? AppColors.mint : AppColors.pink,
              foreground: dropped ? AppColors.tealInk : AppColors.magentaInk,
            ),
          ),
      ],
      trailing: IconButton(
        tooltip: 'Quitar de favoritos',
        icon: const Icon(Icons.favorite, color: AppColors.magenta),
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
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: navBarClearance - 16),
        child: FloatingActionButton.extended(
          backgroundColor: AppColors.blue,
          foregroundColor: Colors.white,
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
                padding: const EdgeInsets.only(
                  top: 8,
                  bottom: navBarClearance + 72,
                ),
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Alertas'),
        actions: const [NotificationsBell(), SizedBox(width: 8)],
      ),
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
                : ListView.builder(
                    padding: const EdgeInsets.only(
                      top: 8,
                      bottom: navBarClearance,
                    ),
                    itemCount: items.length,
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

    final small = theme.textTheme.bodySmall;
    return _TrackedCard(
      imageUrl: product?.imageUrl,
      title: product?.name ?? alert.productName,
      lines: [
        Text(
          'Avisar si baja a ${formatCents(alert.targetPriceCents)} o menos',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.amberInk,
          ),
        ),
        Text(
          current == null
              ? 'Sin precio verificado ahora'
              : 'Mejor precio actual: ${formatCents(current)}',
          style: small,
        ),
        if (met && !paused)
          const Padding(
            key: Key('alert-met'),
            padding: EdgeInsets.only(top: 4),
            child: Pill(
              label: '¡Ya cumple!',
              background: AppColors.mint,
              foreground: AppColors.tealInk,
              icon: Icons.check_circle,
            ),
          ),
        if (paused) Text('Pausada', style: small),
        if (alert.lastTriggeredAt != null &&
            alert.lastTriggeredPriceCents != null)
          Text(
            'Te avisamos el ${_shortDate(alert.lastTriggeredAt!)} a ${formatCents(alert.lastTriggeredPriceCents!)}',
            style: small,
          ),
      ],
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
