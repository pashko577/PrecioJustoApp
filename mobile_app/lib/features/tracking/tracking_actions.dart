import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../models/models.dart';
import '../../models/tracking.dart';
import '../../services/tracking_repository.dart';

/// Sin sesión: lleva al login y luego de vuelta a [returnTo]. Devuelve `true` si redirigió.
bool requireLogin(BuildContext context, WidgetRef ref, String returnTo) {
  if (ref.read(trackingRepositoryProvider) != null) return false;
  context.push(Uri(path: '/login', queryParameters: {'from': returnTo}).toString());
  return true;
}

/// Guarda o quita un producto de favoritos (pide sesión si hace falta).
Future<void> toggleFavorite(BuildContext context, WidgetRef ref, Product product, {int? currentBestCents}) =>
    _run(context, () async {
      if (requireLogin(context, ref, '/product/${product.id}')) return;
      final repo = ref.read(trackingRepositoryProvider)!;
      if (ref.read(isFavoriteProvider(product.id))) {
        await repo.removeFavorite(product.id);
      } else {
        await repo.addFavorite(productId: product.id, productName: product.name, currentBestCents: currentBestCents);
      }
    });

/// Abre el formulario de alerta de precio (crear o editar).
void openAlertForm(BuildContext context, WidgetRef ref, Product product, {int? currentBestCents}) {
  if (requireLogin(context, ref, '/product/${product.id}')) return;
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialogForm(
      product: product,
      currentBestCents: currentBestCents,
      existing: ref.read(alertForProductProvider(product.id)),
    ),
  );
}

/// Abre la hoja para agregar el producto a una lista.
void openWishlistSheet(BuildContext context, WidgetRef ref, Product product) {
  if (requireLogin(context, ref, '/product/${product.id}')) return;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => AddToWishlistSheet(productId: product.id),
  );
}

/// Botones de seguimiento de un producto: favorito, lista y alerta (RF-06, RF-07).
class TrackingActions extends ConsumerWidget {
  const TrackingActions({
    super.key,
    required this.product,
    this.currentBestCents,
  });

  final Product product;

  /// Mejor precio verificado ahora (para sugerir la alerta y recordar el precio al guardar).
  final int? currentBestCents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavorite = ref.watch(isFavoriteProvider(product.id));
    final alert = ref.watch(alertForProductProvider(product.id));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          key: const Key('favorite-button'),
          icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
          label: Text(isFavorite ? 'Guardado' : 'Guardar'),
          onPressed: () => toggleFavorite(context, ref, product, currentBestCents: currentBestCents),
        ),
        OutlinedButton.icon(
          key: const Key('wishlist-button'),
          icon: const Icon(Icons.playlist_add),
          label: const Text('Lista'),
          onPressed: () => openWishlistSheet(context, ref, product),
        ),
        OutlinedButton.icon(
          key: const Key('alert-button'),
          icon: Icon(alert == null ? Icons.notifications_none : Icons.notifications_active),
          label: Text(alert == null ? 'Crear alerta' : 'Alerta: ${formatCents(alert.targetPriceCents)}'),
          onPressed: () => openAlertForm(context, ref, product, currentBestCents: currentBestCents),
        ),
      ],
    );
  }
}

/// Corazón redondo para guardar (cards y barra del detalle).
class FavoriteIconButton extends ConsumerWidget {
  const FavoriteIconButton({super.key, required this.product, this.currentBestCents, this.size = 34});

  final Product product;
  final int? currentBestCents;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(isFavoriteProvider(product.id));
    return Semantics(
      button: true,
      toggled: on,
      label: on ? 'Quitar de guardados' : 'Guardar',
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => toggleFavorite(context, ref, product, currentBestCents: currentBestCents),
          child: SizedBox.square(
            dimension: size,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: Icon(
                on ? Icons.favorite : Icons.favorite_border,
                key: ValueKey(on),
                size: size * 0.53,
                color: on ? AppColors.magenta : AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ejecuta una acción mostrando los errores (por ejemplo, límite del plan) en un aviso.
Future<void> _run(BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } on TrackingFailure catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('No se pudo completar la acción. Inténtalo de nuevo.'),
      ),
    );
  }
}

/// Hoja inferior: elegir una lista o crear una nueva.
class AddToWishlistSheet extends ConsumerWidget {
  const AddToWishlistSheet({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(wishlistsProvider);
    final repo = ref.watch(trackingRepositoryProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Agregar a una lista',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...lists.when(
              loading: () => [const Center(child: CircularProgressIndicator())],
              error: (e, _) => [Text('Error: $e')],
              data: (items) => [
                if (items.isEmpty) const Text('Todavía no tienes listas.'),
                for (final l in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      l.productIds.contains(productId)
                          ? Icons.check_circle
                          : Icons.list_alt,
                    ),
                    title: Text(l.name),
                    subtitle: Text('${l.productIds.length} productos'),
                    onTap: () => _run(context, () async {
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      await repo!.addToWishlist(l.id, productId);
                      navigator.pop();
                      messenger.showSnackBar(
                        SnackBar(content: Text('Agregado a "${l.name}"')),
                      );
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Nueva lista'),
              onPressed: () async {
                final name = await askName(context, title: 'Nueva lista');
                if (name == null || !context.mounted) return;
                await _run(context, () async {
                  final id = await repo!.createWishlist(name);
                  await repo.addToWishlist(id, productId);
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Pide un nombre (crear o renombrar lista).
Future<String?> askName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          key: const Key('list-name'),
          controller: controller,
          autofocus: true,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            hintText: 'Ej.: Mi setup gamer',
          ),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Escribe un nombre.' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/// Crear o editar la alerta de precio de un producto.
class AlertDialogForm extends ConsumerStatefulWidget {
  const AlertDialogForm({
    super.key,
    required this.product,
    this.currentBestCents,
    this.existing,
  });

  final Product product;
  final int? currentBestCents;
  final PriceAlert? existing;

  @override
  ConsumerState<AlertDialogForm> createState() => _AlertDialogFormState();
}

class _AlertDialogFormState extends ConsumerState<AlertDialogForm> {
  final _formKey = GlobalKey<FormState>();
  late final _price = TextEditingController(text: _initialText());
  bool _busy = false;

  String _initialText() {
    final cents =
        widget.existing?.targetPriceCents ??
        (widget.currentBestCents != null
            ? suggestedTargetCents(widget.currentBestCents!)
            : null);
    if (cents == null) return '';
    return cents % 100 == 0
        ? '${cents ~/ 100}'
        : (cents / 100).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final target = parseSolesToCents(_price.text)!;
    try {
      await ref
          .read(trackingRepositoryProvider)!
          .saveAlert(
            productId: widget.product.id,
            productName: widget.product.name,
            targetPriceCents: target,
          );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Te avisaremos si baja a ${formatCents(target)} o menos.',
          ),
        ),
      );
    } on TrackingFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    await ref
        .read(trackingRepositoryProvider)!
        .deleteAlert(widget.existing!.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.currentBestCents;
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Crear alerta de precio' : 'Editar alerta',
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              current == null
                  ? 'Sin precio verificado ahora.'
                  : 'Mejor precio actual: ${formatCents(current)}',
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('alert-price'),
              controller: _price,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Avísame si baja a',
                prefixText: 'S/ ',
              ),
              validator: (v) => parseSolesToCents(v ?? '') == null
                  ? 'Ingresa un precio válido.'
                  : null,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            Text(
              'Te avisaremos cuando una tienda lo ofrezca a ese precio o menos.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            key: const Key('alert-delete'),
            onPressed: _busy ? null : _delete,
            child: const Text('Eliminar'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('alert-save'),
          onPressed: _busy ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
