import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/offer_rules.dart';
import '../../models/models.dart';

/// Una oferta de tienda. Nunca presenta un precio desactualizado como confirmado (RF-04).
class OfferTile extends StatelessWidget {
  const OfferTile({
    super.key,
    required this.offer,
    required this.fresh,
    this.isBest = false,
    this.differenceCents,
    this.onOpenStore,
    this.now,
  });

  final StoreOffer offer;
  final bool fresh;
  final bool isBest;

  /// Cuánto más cuesta que la mejor oferta (`null` si no aplica).
  final int? differenceCents;
  final VoidCallback? onOpenStore;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = totalCostCents(offer);
    final dropped = offer.previousPriceCents != null && offer.previousPriceCents! > offer.priceCents;

    return Card(
      shape: isBest
          ? RoundedRectangleBorder(
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(offer.storeName, style: theme.textTheme.titleMedium),
                      if (isThirdPartySeller(offer))
                        Text('Vendido por ${offer.sellerName}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (isBest) const _Badge(label: 'Mejor precio', icon: Icons.verified),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatCents(offer.priceCents, currency: offer.currency),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: fresh ? null : theme.disabledColor,
                    decoration: fresh ? null : TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 8),
                if (dropped)
                  Text(
                    'antes ${formatCents(offer.previousPriceCents!)}',
                    style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough),
                  ),
              ],
            ),
            if (differenceCents != null && differenceCents! > 0) ...[
              const SizedBox(height: 2),
              Text(
                '${formatCents(differenceCents!)} más que el mejor precio',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _AvailabilityChip(availability: offer.availability),
                Text(
                  offer.shippingCents == null
                      ? 'Envío no informado'
                      : offer.shippingCents == 0
                          ? 'Envío gratis'
                          : 'Envío ${formatCents(offer.shippingCents!)}',
                  style: theme.textTheme.bodySmall,
                ),
                if (total != null && offer.shippingCents! > 0)
                  Text('Total ${formatCents(total)}', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(fresh ? Icons.schedule : Icons.warning_amber, size: 16,
                    color: fresh ? theme.hintColor : theme.colorScheme.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    fresh
                        ? 'Verificado ${timeAgo(offer.lastCheckedAt, now: now)}'
                        : 'Desactualizado · última consulta ${timeAgo(offer.lastCheckedAt, now: now)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: fresh ? null : theme.colorScheme.error),
                  ),
                ),
                if (onOpenStore != null)
                  TextButton.icon(
                    onPressed: onOpenStore,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Ir a la tienda'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailabilityChip extends StatelessWidget {
  const _AvailabilityChip({required this.availability});

  final Availability availability;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (availability) {
      Availability.available => ('Disponible', Colors.green),
      Availability.outOfStock => ('Agotado', Colors.red),
      Availability.preorder => ('Preventa', Colors.orange),
      Availability.unknown => ('Disponibilidad desconocida', Colors.grey),
    };
    return Text(label, style: TextStyle(color: color.shade700, fontWeight: FontWeight.w600, fontSize: 12));
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    ]);
  }
}
