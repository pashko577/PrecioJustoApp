import 'package:cloud_firestore/cloud_firestore.dart';

/// Fechas de Firestore (`Timestamp`) o del catálogo local (texto ISO en UTC).
DateTime? _date(Object? value) => switch (value) {
  Timestamp t => t.toDate(),
  String s => DateTime.tryParse(s),
  _ => null,
};
int? _int(Object? value) => value is num ? value.toInt() : null;

class Category {
  const Category({
    required this.slug,
    required this.name,
    this.parentSlug,
    this.order = 0,
    this.icon,
  });

  final String slug;
  final String name;
  final String? parentSlug;
  final int order;

  /// Nombre de ícono Material (por ejemplo, "devices"); ver `categoryIcon`.
  final String? icon;

  bool get isTopLevel => parentSlug == null;

  /// Entrada de `catalog.json` (ver `app/export/catalog.py` en el motor).
  factory Category.fromCatalog(Map<String, dynamic> d) => Category(
    slug: d['slug'] as String,
    name: d['name'] as String? ?? d['slug'] as String,
    parentSlug: d['parentSlug'] as String?,
    order: _int(d['order']) ?? 0,
    icon: d['icon'] as String?,
  );

  factory Category.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Category(
      slug: doc.id,
      name: d['name'] as String? ?? doc.id,
      parentSlug: d['parentSlug'] as String?,
      order: _int(d['order']) ?? 0,
      icon: d['icon'] as String?,
    );
  }
}

class PriceSummary {
  const PriceSummary({
    this.minPriceCents,
    this.minPriceStoreCode,
    this.offerCount = 0,
    this.verifiedOfferCount = 0,
    this.lastCheckedAt,
    this.currency = 'PEN',
    this.priceDropFromCents,
    this.priceDropPercent,
    this.priceDroppedAt,
  });

  final int? minPriceCents;
  final String? minPriceStoreCode;
  final int offerCount;
  final int verifiedOfferCount;
  final DateTime? lastCheckedAt;
  final String currency;

  /// Bajada reciente del mejor precio, medida contra precios que observamos nosotros
  /// (nunca contra el precio «normal» de la tienda). Ver `summary.py` en el motor.
  final int? priceDropFromCents;
  final int? priceDropPercent;
  final DateTime? priceDroppedAt;

  /// Días durante los que se anuncia una bajada (igual que `PRICE_DROP_WINDOW_DAYS`).
  static const dropWindow = Duration(days: 7);

  /// La bajada se puede anunciar: existe y es reciente.
  bool hasRecentDrop({DateTime? now}) {
    final at = priceDroppedAt;
    if (priceDropPercent == null ||
        priceDropPercent! <= 0 ||
        priceDropFromCents == null ||
        at == null) {
      return false;
    }
    return (now ?? DateTime.now()).difference(at) <= dropWindow;
  }

  factory PriceSummary.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const PriceSummary();
    return PriceSummary(
      minPriceCents: _int(d['minPriceCents']),
      minPriceStoreCode: d['minPriceStoreCode'] as String?,
      offerCount: _int(d['offerCount']) ?? 0,
      verifiedOfferCount: _int(d['verifiedOfferCount']) ?? 0,
      lastCheckedAt: _date(d['lastCheckedAt']),
      currency: d['currency'] as String? ?? 'PEN',
      priceDropFromCents: _int(d['priceDropFromCents']),
      priceDropPercent: _int(d['priceDropPercent']),
      priceDroppedAt: _date(d['priceDroppedAt']),
    );
  }
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.categorySlug,
    this.model,
    this.imageUrl,
    this.description = '',
    this.attributes = const {},
    this.identifiers = const {},
    this.searchTokens = const [],
    this.status = 'ACTIVE',
    this.mergedInto,
    this.summary = const PriceSummary(),
  });

  final String id;
  final String name;
  final String brand;
  final String categorySlug;
  final String? model;
  final String? imageUrl;
  final String description;
  final Map<String, dynamic> attributes;

  /// Códigos comerciales, por ejemplo `{"EAN": ["2001234567893"]}`.
  final Map<String, List<String>> identifiers;

  /// Palabras y prefijos normalizados (ver `search_normalizer.dart`).
  final List<String> searchTokens;
  final String status;

  /// Si el producto se unificó con otro (status MERGED), el producto conservado.
  final String? mergedInto;
  final PriceSummary summary;

  /// Entrada de `catalog.json`: sin `searchTokens` (la búsqueda local los calcula).
  factory Product.fromCatalog(Map<String, dynamic> d) => Product(
    id: d['id'] as String,
    name: d['name'] as String? ?? d['id'] as String,
    brand: d['brand'] as String? ?? '',
    categorySlug: d['categorySlug'] as String? ?? '',
    model: d['model'] as String?,
    imageUrl: d['imageUrl'] as String?,
    identifiers: {
      for (final e in (d['identifiers'] as Map? ?? const {}).entries)
        e.key.toString(): List<String>.from(e.value as List? ?? const []),
    },
    status: d['status'] as String? ?? 'ACTIVE',
    mergedInto: d['mergedInto'] as String?,
    summary: PriceSummary.fromMap((d['summary'] as Map?)?.cast<String, dynamic>()),
  );

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Product(
      id: doc.id,
      name: (d['displayName'] ?? d['normalizedName'] ?? doc.id) as String,
      brand: d['brand'] as String? ?? '',
      categorySlug: d['categorySlug'] as String? ?? '',
      model: d['model'] as String?,
      imageUrl: d['imageUrl'] as String?,
      description: d['description'] as String? ?? '',
      attributes: Map<String, dynamic>.from(
        d['attributes'] as Map? ?? const {},
      ),
      identifiers: {
        for (final e in (d['identifiers'] as Map? ?? const {}).entries)
          e.key.toString(): List<String>.from(e.value as List? ?? const []),
      },
      searchTokens: List<String>.from(d['searchTokens'] as List? ?? const []),
      status: d['status'] as String? ?? 'ACTIVE',
      mergedInto: d['mergedInto'] as String?,
      summary: PriceSummary.fromMap(d['summary'] as Map<String, dynamic>?),
    );
  }
}

/// Valores permitidos de disponibilidad (RN-05).
enum Availability { available, outOfStock, preorder, unknown }

Availability parseAvailability(String? raw) => switch (raw) {
  'AVAILABLE' => Availability.available,
  'OUT_OF_STOCK' => Availability.outOfStock,
  'PREORDER' => Availability.preorder,
  _ => Availability.unknown,
};

/// Una publicación de una tienda (oferta).
class StoreOffer {
  const StoreOffer({
    required this.id,
    required this.storeCode,
    required this.storeName,
    required this.title,
    required this.productUrl,
    required this.priceCents,
    required this.availability,
    required this.lastCheckedAt,
    this.previousPriceCents,
    this.shippingCents,
    this.sellerName,
    this.currency = 'PEN',
    this.missedRuns = 0,
    this.lastChangedAt,
  });

  final String id;
  final String storeCode;
  final String storeName;
  final String title;
  final String productUrl;
  final int priceCents;
  final int? previousPriceCents;

  /// `null` = envío desconocido (RN-03). No es lo mismo que 0 (gratis).
  final int? shippingCents;
  final Availability availability;
  final DateTime lastCheckedAt;
  final String? sellerName;
  final String currency;

  /// Corridas completas seguidas en que la publicación no apareció (0 = apareció en la última).
  final int missedRuns;

  /// Desde cuándo rige el precio/disponibilidad actual (el motor lo fija en cada cambio).
  final DateTime? lastChangedAt;

  /// Copia con otra fecha de verificación (ver `effectiveCheckedAt`).
  StoreOffer withCheckedAt(DateTime checkedAt) => StoreOffer(
    id: id,
    storeCode: storeCode,
    storeName: storeName,
    title: title,
    productUrl: productUrl,
    priceCents: priceCents,
    previousPriceCents: previousPriceCents,
    shippingCents: shippingCents,
    availability: availability,
    lastCheckedAt: checkedAt,
    sellerName: sellerName,
    currency: currency,
    missedRuns: missedRuns,
    lastChangedAt: lastChangedAt,
  );

  /// Entrada de `catalog.json`.
  factory StoreOffer.fromCatalog(Map<String, dynamic> d) => StoreOffer(
    id: d['id'] as String,
    storeCode: d['storeCode'] as String? ?? '',
    storeName: d['storeName'] as String? ?? '',
    title: d['title'] as String? ?? '',
    productUrl: d['productUrl'] as String? ?? '',
    priceCents: _int(d['priceCents']) ?? 0,
    previousPriceCents: _int(d['previousPriceCents']),
    shippingCents: _int(d['shippingCents']),
    availability: parseAvailability(d['availability'] as String?),
    lastCheckedAt: _date(d['lastCheckedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    sellerName: d['sellerName'] as String?,
    currency: d['currency'] as String? ?? 'PEN',
    missedRuns: _int(d['missedRuns']) ?? 0,
    lastChangedAt: _date(d['lastChangedAt']),
  );

  factory StoreOffer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return StoreOffer(
      id: doc.id,
      storeCode: d['storeCode'] as String? ?? '',
      storeName: d['storeName'] as String? ?? '',
      title: d['title'] as String? ?? '',
      productUrl: d['productUrl'] as String? ?? '',
      priceCents: _int(d['currentPriceCents']) ?? 0,
      previousPriceCents: _int(d['previousPriceCents']),
      shippingCents: _int(d['currentShippingCents']),
      availability: parseAvailability(d['availability'] as String?),
      lastCheckedAt:
          _date(d['lastCheckedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      sellerName: d['sellerName'] as String?,
      currency: d['currency'] as String? ?? 'PEN',
      missedRuns: _int(d['missedRuns']) ?? 0,
      lastChangedAt: _date(d['lastChangedAt']),
    );
  }
}

/// Datos de una tienda necesarios para la vigencia (RN-01).
class StoreInfo {
  const StoreInfo({
    required this.code,
    this.name = '',
    this.freshnessMinutes = 720,
    this.lastCompleteRunAt,
    this.active = true,
  });

  final String code;
  final String name;
  final int freshnessMinutes;

  /// Inicio de la última corrida completa del scraper para esta tienda.
  final DateTime? lastCompleteRunAt;

  /// `false` = tienda evaluada pero que no se consulta (no se muestra como «comparada»).
  final bool active;

  /// Entrada de `catalog.json`.
  factory StoreInfo.fromCatalog(Map<String, dynamic> d) => StoreInfo(
    code: d['code'] as String,
    name: d['name'] as String? ?? d['code'] as String,
    freshnessMinutes: _int(d['freshnessMinutes']) ?? 720,
    lastCompleteRunAt: _date(d['lastCompleteRunAt']),
    active: d['active'] as bool? ?? true,
  );

  factory StoreInfo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return StoreInfo(
      code: doc.id,
      name: d['name'] as String? ?? doc.id,
      freshnessMinutes: _int(d['freshnessMinutes']) ?? 720,
      lastCompleteRunAt: _date(d['lastCompleteRunAt']),
      active: d['scrapingEnabled'] as bool? ?? true,
    );
  }
}

/// Verificación real de una oferta. Las publicaciones sin cambios no se reescriben en cada
/// corrida: si apareció en la última corrida completa de su tienda (`missedRuns == 0`), cuenta
/// como verificada en esa fecha. Debe coincidir con `effective_checked_at` en Python.
DateTime effectiveCheckedAt(StoreOffer offer, StoreInfo? store) {
  final run = store?.lastCompleteRunAt;
  if (run == null || offer.missedRuns != 0) return offer.lastCheckedAt;
  return run.isAfter(offer.lastCheckedAt) ? run : offer.lastCheckedAt;
}
