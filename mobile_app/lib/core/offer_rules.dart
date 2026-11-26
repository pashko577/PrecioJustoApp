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

/// Resultado de comparar las ofertas de un producto (RF-04, RN-02).
class OfferComparison {
  const OfferComparison({this.best, this.highest, this.comparableCount = 0, this.storeCount = 0});

  /// Oferta vigente y disponible más barata.
  final StoreOffer? best;

  /// Mejor oferta de la tienda más cara: el precio más bajo que da cada tienda, y de esas
  /// tiendas la que más cobra. No se usa la oferta más cara a secas: en un marketplace
  /// algún vendedor siempre pide de más (o publica otro modelo) y el «ahorro» se dispara.
  /// `null` si solo hay una tienda.
  final StoreOffer? highest;

  /// Cuántas ofertas son comparables (vigentes, disponibles y en soles).
  final int comparableCount;

  /// Cuántas tiendas distintas tienen ofertas comparables (una tienda puede tener varios vendedores).
  final int storeCount;

  /// Ahorro frente a comprar en la tienda más cara (solo si hay 2 o más tiendas).
  int? get maxSavingsCents =>
      storeCount >= 2 && best != null && highest != null ? highest!.priceCents - best!.priceCents : null;
}

/// Una oferta es comparable si está vigente, disponible y en soles (RN-01, RN-02, RN-04).
bool isComparable(StoreOffer o, bool Function(StoreOffer) fresh) =>
    fresh(o) && o.availability == Availability.available && o.currency == 'PEN';

OfferComparison compareOffers(List<StoreOffer> offers, bool Function(StoreOffer) fresh) {
  final comparable = offers.where((o) => isComparable(o, fresh)).toList()
    ..sort((a, b) => a.priceCents.compareTo(b.priceCents));
  if (comparable.isEmpty) return const OfferComparison();
  // Precio más bajo de cada tienda (la lista ya está ordenada: la primera de cada tienda).
  final cheapestByStore = <String, StoreOffer>{};
  for (final o in comparable) {
    cheapestByStore.putIfAbsent(o.storeCode, () => o);
  }
  final storeBests = cheapestByStore.values.toList();
  return OfferComparison(
    best: comparable.first,
    highest: storeBests.length >= 2 ? storeBests.last : null,
    comparableCount: comparable.length,
    storeCount: storeBests.length,
  );
}

/// Diferencia de precio frente a la mejor oferta, solo para ofertas comparables.
int? differenceFromBest(StoreOffer o, OfferComparison c, bool Function(StoreOffer) fresh) {
  final best = c.best;
  if (best == null || identical(o, best) || !isComparable(o, fresh)) return null;
  return o.priceCents - best.priceCents;
}

/// ¿Hay que mostrar el vendedor? Solo si es un tercero del marketplace (no la tienda misma).
bool isThirdPartySeller(StoreOffer o) {
  final seller = o.sellerName?.trim();
  if (seller == null || seller.isEmpty) return false;
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final s = norm(seller), store = norm(o.storeName);
  return !(s.contains(store) || store.contains(s));
}

/// Texto relativo "hace 2 h" para la fecha de última verificación (RNF-13).
String timeAgo(DateTime date, {DateTime? now}) {
  final diff = (now ?? DateTime.now().toUtc()).difference(date.toUtc());
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return 'hace ${diff.inDays} d';
}
