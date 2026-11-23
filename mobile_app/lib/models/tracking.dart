import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;
int? _int(Object? v) => v is num ? v.toInt() : null;

/// `users/{uid}/favorites/{productId}`.
class Favorite {
  const Favorite({required this.productId, required this.productName, this.priceAtSaveCents, this.createdAt});

  final String productId;
  final String productName;

  /// Mejor precio verificado al guardarlo (para mostrar "bajó desde que lo guardaste").
  final int? priceAtSaveCents;
  final DateTime? createdAt;

  factory Favorite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Favorite(
      productId: doc.id,
      productName: d['productName'] as String? ?? doc.id,
      priceAtSaveCents: _int(d['priceAtSaveCents']),
      createdAt: _date(d['createdAt']),
    );
  }
}

/// `users/{uid}/wishlists/{listId}`.
class Wishlist {
  const Wishlist({required this.id, required this.name, this.productIds = const [], this.updatedAt});

  final String id;
  final String name;
  final List<String> productIds;
  final DateTime? updatedAt;

  factory Wishlist.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Wishlist(
      id: doc.id,
      name: d['name'] as String? ?? 'Lista',
      productIds: List<String>.from(d['productIds'] as List? ?? const []),
      updatedAt: _date(d['updatedAt']),
    );
  }
}

enum AlertStatus { active, paused, triggered }

AlertStatus parseAlertStatus(String? raw) => switch (raw) {
      'PAUSED' => AlertStatus.paused,
      'TRIGGERED' => AlertStatus.triggered,
      _ => AlertStatus.active,
    };

String alertStatusValue(AlertStatus s) => switch (s) {
      AlertStatus.active => 'ACTIVE',
      AlertStatus.paused => 'PAUSED',
      AlertStatus.triggered => 'TRIGGERED',
    };

/// `users/{uid}/alerts/{alertId}` (RF-06). La evalúa el motor tras cada corrida (sprint 8).
class PriceAlert {
  const PriceAlert({
    required this.id,
    required this.productId,
    required this.productName,
    required this.targetPriceCents,
    this.status = AlertStatus.active,
    this.lastTriggeredAt,
    this.lastTriggeredPriceCents,
    this.createdAt,
  });

  final String id;
  final String productId;
  final String productName;
  final int targetPriceCents;
  final AlertStatus status;
  final DateTime? lastTriggeredAt;
  final int? lastTriggeredPriceCents;
  final DateTime? createdAt;

  factory PriceAlert.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return PriceAlert(
      id: doc.id,
      productId: d['productId'] as String? ?? '',
      productName: d['productName'] as String? ?? '',
      targetPriceCents: _int(d['targetPriceCents']) ?? 0,
      status: parseAlertStatus(d['status'] as String?),
      lastTriggeredAt: _date(d['lastTriggeredAt']),
      lastTriggeredPriceCents: _int(d['lastTriggeredPriceCents']),
      createdAt: _date(d['createdAt']),
    );
  }

  /// ¿El mejor precio verificado actual ya cumple la alerta? (condición AT_OR_BELOW)
  bool isMetBy(int? currentBestCents) => currentBestCents != null && currentBestCents <= targetPriceCents;
}

/// Límites del plan gratuito (`config/app.freePlanLimits`, RN-11).
class PlanLimits {
  const PlanLimits({this.favorites = 50, this.alerts = 5, this.wishlists = 3, this.itemsPerList = 100});

  final int favorites;
  final int alerts;
  final int wishlists;
  final int itemsPerList;

  factory PlanLimits.fromConfig(Map<String, dynamic>? config) {
    final l = (config?['freePlanLimits'] as Map?)?.cast<String, dynamic>() ?? const {};
    const defaults = PlanLimits();
    return PlanLimits(
      favorites: _int(l['favorites']) ?? defaults.favorites,
      alerts: _int(l['alerts']) ?? defaults.alerts,
      wishlists: _int(l['wishlists']) ?? defaults.wishlists,
      itemsPerList: _int(l['itemsPerList']) ?? defaults.itemsPerList,
    );
  }

  /// Premium: sin límites prácticos (el máximo lo fija la regla de Firestore para listas).
  static const premium = PlanLimits(favorites: 1000, alerts: 100, wishlists: 50, itemsPerList: 100);
}

/// Precio objetivo sugerido: 5 % por debajo del mejor precio actual, redondeado a sol entero.
int suggestedTargetCents(int currentBestCents) {
  final target = (currentBestCents * 0.95).floor();
  return (target ~/ 100) * 100;
}
