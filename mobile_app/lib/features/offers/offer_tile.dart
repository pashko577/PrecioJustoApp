import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../core/offer_rules.dart';
import '../../models/models.dart';
import '../../ui/brand.dart';
import '../../ui/common.dart';

/// Una oferta de tienda en la «escalera» de precios del detalle.
/// Nunca presenta un precio desactualizado como confirmado (RF-04).
class OfferTile extends StatelessWidget {
  const OfferTile({
    super.key,
    required this.offer,
    required this.fresh,
    this.isBest = false,
    this.differenceCents,
    this.onOpenStore,
    this.barFraction,
    this.now,
  });

  final StoreOffer offer;
  final bool fresh;
  final bool isBest;

  /// Cuánto más cuesta que la mejor oferta (`null` si no aplica).
  final int? differenceCents;
  final VoidCallback? onOpenStore;

  /// Largo de la barra comparativa (0–1). `null` = sin barra (por ejemplo, una sola tienda).
  final double? barFraction;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = totalCostCents(offer);
    final dropped = offer.previousPriceCents != null && offer.previousPriceCents! > offer.priceCents;
    final muted = theme.textTheme.bodySmall;
    final unavailable = offer.availability == Availability.outOfStock;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: isBest ? AppColors.teal : Colors.transparent, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpenStore,
          child: Opacity(
            opacity: unavailable ? 0.6 : 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StoreBadge(code: offer.storeCode, name: offer.storeName, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(offer.storeName, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  if (isThirdPartySeller(offer)) Text('Vendido por ${offer.sellerName}', style: muted),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatCents(offer.priceCents, currency: offer.currency),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: tabularFigures,
                                    color: fresh ? AppColors.ink : AppColors.muted,
                                    decoration: fresh ? null : TextDecoration.lineThrough,
                                  ),
                                ),
                                if (dropped)
                                  Text(
                                    'antes ${formatCents(offer.previousPriceCents!)}',
                                    style: muted?.copyWith(decoration: TextDecoration.lineThrough),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        if (barFraction != null) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: Stack(
                              children: [
                                Container(height: 6, color: AppColors.bg),
                                FractionallySizedBox(
                                  widthFactor: barFraction!.clamp(0.05, 1.0),
                                  child: Container(height: 6, color: isBest ? AppColors.teal : const Color(0xFFB8C3DC)),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (isBest) const Pill(label: 'Mejor precio', background: AppColors.mint, foreground: AppColors.tealInk, icon: Icons.verified),
                            _AvailabilityLabel(availability: offer.availability),
                            Text(
                              offer.shippingCents == null
                                  ? 'Envío no informado'
                                  : offer.shippingCents == 0
                                      ? 'Envío gratis'
                                      : 'Envío ${formatCents(offer.shippingCents!)}',
                              style: muted,
                            ),
                            if (total != null && offer.shippingCents! > 0) Text('Total ${formatCents(total)}', style: muted),
                          ],
                        ),
                        if (differenceCents != null && differenceCents! > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${formatCents(differenceCents!)} más que el mejor precio',
                            style: muted?.copyWith(color: AppColors.magentaInk, fontWeight: FontWeight.w500),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(fresh ? Icons.schedule : Icons.warning_amber_rounded, size: 14, color: fresh ? AppColors.muted : AppColors.amberInk),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                fresh
                                    ? 'Verificado ${timeAgo(offer.lastCheckedAt, now: now)}'
                                    : 'Desactualizado: última consulta ${timeAgo(offer.lastCheckedAt, now: now)}',
                                style: muted?.copyWith(color: fresh ? null : AppColors.amberInk),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (onOpenStore != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 2),
                      child: Tooltip(
                        message: 'Ir a la tienda',
                        child: Icon(Icons.open_in_new, size: 18, color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvailabilityLabel extends StatelessWidget {
  const _AvailabilityLabel({required this.availability});

  final Availability availability;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (availability) {
      Availability.available => ('Disponible', AppColors.tealInk),
      Availability.outOfStock => ('Agotado', const Color(0xFFB42318)),
      Availability.preorder => ('Preventa', AppColors.amberInk),
      Availability.unknown => ('Disponibilidad desconocida', AppColors.muted),
    };
    return Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12));
  }
}
