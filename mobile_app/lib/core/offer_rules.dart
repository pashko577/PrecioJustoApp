import '../models/models.dart';

/// Vigencia por defecto si la tienda no define `freshnessMinutes`.
const int defaultFreshnessMinutes = 12 * 60;

/// RN-01: una oferta está verificada si su última consulta está dentro del periodo de vigencia.
bool isFresh(DateTime lastCheckedAt, int freshnessMinutes, {DateTime? now}) {
  final reference = now ?? DateTime.now().toUtc();
  return reference.difference(lastCheckedAt.toUtc()) <= Duration(minutes: freshnessMinutes);
}

/// RN-03: costo total solo si el envío es conocido. `null` = no se puede calcular.
int? totalCostCents(StoreOffer offer) =>
    offer.shippingCents == null ? null : offer.priceCents + offer.shippingCents!;

/// Ordena ofertas: primero las vigentes y disponibles, luego por precio (RF-04, RN-02, RN-09).
List<StoreOffer> sortOffers(
  List<StoreOffer> offers,
  int Function(String storeCode) freshnessFor, {
  DateTime? now,
}) {
  int rank(StoreOffer o) {
    final fresh = isFresh(o.lastCheckedAt, freshnessFor(o.storeCode), now: now);
    if (fresh && o.availability == Availability.available) return 0;
    if (fresh) return 1;
    return 2;
  }

  return [...offers]..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.priceCents.compareTo(b.priceCents);
    });
}

/// Texto relativo "hace 2 h" para la fecha de última verificación (RNF-13).
String timeAgo(DateTime date, {DateTime? now}) {
  final diff = (now ?? DateTime.now().toUtc()).difference(date.toUtc());
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return 'hace ${diff.inDays} d';
}
