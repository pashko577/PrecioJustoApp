import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../models/models.dart';

/// Fila de producto usada en el catálogo y en la búsqueda.
class ProductRow extends StatelessWidget {
  const ProductRow({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final s = product.summary;
    final theme = Theme.of(context);
    final stores = s.offerCount == 0
        ? 'Sin ofertas aún'
        : '${s.offerCount} ${s.offerCount == 1 ? 'tienda' : 'tiendas'}';
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
      title: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${product.brand} · $stores'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (s.minPriceCents != null) ...[
            Text('desde', style: theme.textTheme.labelSmall),
            Text(
              formatCents(s.minPriceCents!),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ] else
            Text('Sin precio\nverificado', textAlign: TextAlign.end, style: theme.textTheme.bodySmall),
        ],
      ),
      onTap: () => context.push('/product/${product.id}'),
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
