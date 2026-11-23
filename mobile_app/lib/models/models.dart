import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(Object? value) => value is Timestamp ? value.toDate() : null;
int? _int(Object? value) => value is num ? value.toInt() : null;

class Category {
  const Category({required this.slug, required this.name, this.parentSlug, this.order = 0});

  final String slug;
  final String name;
  final String? parentSlug;
  final int order;

  factory Category.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Category(
      slug: doc.id,
      name: d['name'] as String? ?? doc.id,
      parentSlug: d['parentSlug'] as String?,
      order: _int(d['order']) ?? 0,
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
  });

  final int? minPriceCents;
  final String? minPriceStoreCode;
  final int offerCount;
  final int verifiedOfferCount;
  final DateTime? lastCheckedAt;
  final String currency;

  factory PriceSummary.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const PriceSummary();
    return PriceSummary(
      minPriceCents: _int(d['minPriceCents']),
      minPriceStoreCode: d['minPriceStoreCode'] as String?,
      offerCount: _int(d['offerCount']) ?? 0,
      verifiedOfferCount: _int(d['verifiedOfferCount']) ?? 0,
      lastCheckedAt: _date(d['lastCheckedAt']),
      currency: d['currency'] as String? ?? 'PEN',
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
    this.attributes = const {},
    this.summary = const PriceSummary(),
  });

  final String id;
  final String name;
  final String brand;
  final String categorySlug;
  final String? model;
  final String? imageUrl;
  final Map<String, dynamic> attributes;
  final PriceSummary summary;

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Product(
      id: doc.id,
      name: (d['displayName'] ?? d['normalizedName'] ?? doc.id) as String,
      brand: d['brand'] as String? ?? '',
      categorySlug: d['categorySlug'] as String? ?? '',
      model: d['model'] as String?,
      imageUrl: d['imageUrl'] as String?,
      attributes: Map<String, dynamic>.from(d['attributes'] as Map? ?? const {}),
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
      lastCheckedAt: _date(d['lastCheckedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      sellerName: d['sellerName'] as String?,
      currency: d['currency'] as String? ?? 'PEN',
    );
  }
}
