import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../models/models.dart';
import '../../services/catalog_repository.dart';
import '../../ui/common.dart';
import 'review_repository.dart';

/// Producto sugerido para una publicación en revisión (del catálogo local: sin lecturas).
final _suggestedProvider = FutureProvider.autoDispose.family<Product?, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).product(id),
);

/// Revisión de asociaciones dudosas, una por una: «¿es el mismo producto?».
/// Solo para administradores; aprobar hace que el precio de esa tienda aparezca en la app.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _queue = <PendingListing>[];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _busy = false;
  String? _error;
  int _approved = 0, _rejected = 0, _skipped = 0;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    final repo = ref.read(reviewRepositoryProvider);
    if (repo == null || _loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await repo.pending(startAfter: _cursor);
      setState(() {
        _queue.addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      setState(() => _error = 'No se pudieron cargar las publicaciones.\n$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(Future<void> Function(PendingListing) action, void Function() count) async {
    final current = _queue.first;
    setState(() => _busy = true);
    try {
      await action(current);
      setState(() {
        count();
        _queue.removeAt(0);
      });
      if (_queue.length < 3) _loadMore();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _skip() {
    setState(() {
      _skipped++;
      _queue.removeAt(0);
    });
    if (_queue.length < 3) _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(reviewRepositoryProvider);
    final reviewed = _approved + _rejected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar asociaciones'),
        actions: [
          if (reviewed + _skipped > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('$_approved ✓  ·  $_rejected ✗', key: const Key('review-counter'))),
            ),
        ],
      ),
      body: SafeArea(child: _body(context, repo)),
    );
  }

  Widget _body(BuildContext context, ReviewRepository? repo) {
    if (repo == null) {
      return const EmptyState(icon: Icons.lock_outline, title: 'Inicia sesión', body: 'Solo para administradores.');
    }
    if (_queue.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) {
        return EmptyState(
          icon: Icons.cloud_off,
          title: 'Sin conexión con la base',
          body: _error!,
          action: FilledButton(onPressed: _loadMore, child: const Text('Reintentar')),
        );
      }
      return const EmptyState(
        icon: Icons.task_alt,
        title: 'Nada pendiente',
        body: 'No hay asociaciones por revisar. Los precios aprobados aparecen en la app después de la '
            'próxima actualización.',
      );
    }
    final listing = _queue.first;
    final suggestedId = listing.suggestedProductId;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ListingCard(listing: listing),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  suggestedId == null ? 'Sin producto sugerido' : '¿Es el mismo producto que…?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (suggestedId != null) _SuggestedCard(productId: suggestedId),
              if (listing.matchReason != null || listing.matchScore != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    [
                      if (listing.matchScore != null) 'Coincidencia ${listing.matchScore} %',
                      if (listing.matchReason != null) listing.matchReason!,
                    ].join(' · '),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('review-reject'),
                      onPressed: _busy ? null : () => _decide(repo.reject, () => _rejected++),
                      icon: const Icon(Icons.close),
                      label: const Text('No es el mismo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('review-approve'),
                      onPressed: _busy || suggestedId == null ? null : () => _decide(repo.approve, () => _approved++),
                      icon: const Icon(Icons.check),
                      label: const Text('Sí, es el mismo'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.tealInk,
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ],
              ),
              TextButton(
                key: const Key('review-skip'),
                onPressed: _busy ? null : _skip,
                child: const Text('No estoy seguro: saltar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.listing});
  final PendingListing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _ReviewCard(
      label: 'En ${listing.storeName}',
      imageUrl: listing.imageUrl,
      title: listing.title,
      price: formatCents(listing.priceCents),
      action: listing.productUrl.isEmpty
          ? null
          : TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(listing.productUrl), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Ver en la tienda'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, textStyle: theme.textTheme.bodySmall),
            ),
    );
  }
}

class _SuggestedCard extends ConsumerWidget {
  const _SuggestedCard({required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(_suggestedProvider(productId));
    return product.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Text('No se pudo cargar el producto sugerido: $e'),
      data: (p) => p == null
          ? Text('El producto sugerido ($productId) ya no existe.', textAlign: TextAlign.center)
          : _ReviewCard(
              label: 'Producto en CompraMejor',
              imageUrl: p.imageUrl,
              title: p.name,
              subtitle: [p.brand, if (p.model != null && p.model!.isNotEmpty) p.model!].join(' · '),
              price: p.summary.minPriceCents == null
                  ? 'Sin precio aún'
                  : 'Desde ${formatCents(p.summary.minPriceCents!)} en ${p.summary.storeCount} tienda(s)',
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.label,
    required this.title,
    required this.price,
    this.imageUrl,
    this.subtitle,
    this.action,
  });

  final String label;
  final String title;
  final String price;
  final String? imageUrl;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 88, height: 88, child: ProductImage(url: imageUrl, padding: 6)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.muted)),
                  const SizedBox(height: 4),
                  Text(title, style: theme.textTheme.titleSmall),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                  ],
                  const SizedBox(height: 6),
                  Text(price, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ?action,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
