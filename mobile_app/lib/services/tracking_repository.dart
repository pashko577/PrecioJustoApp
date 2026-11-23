import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_providers.dart';
import '../models/tracking.dart';

/// Error de seguimiento con mensaje para el usuario (por ejemplo, límite del plan).
class TrackingFailure implements Exception {
  const TrackingFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Favoritos, listas y alertas del usuario (RF-06, RF-07). Solo toca `users/{uid}/...`;
/// las reglas de Firestore garantizan que nadie más pueda leer o escribir estos datos.
class TrackingRepository {
  TrackingRepository(this._db, this.uid, {this.isPremium = false});

  final FirebaseFirestore _db;
  final String uid;
  final bool isPremium;

  DocumentReference<Map<String, dynamic>> get _user => _db.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> get _favorites => _user.collection('favorites');
  CollectionReference<Map<String, dynamic>> get _wishlists => _user.collection('wishlists');
  CollectionReference<Map<String, dynamic>> get _alerts => _user.collection('alerts');

  Future<PlanLimits> limits() async {
    if (isPremium) return PlanLimits.premium;
    final config = await _db.collection('config').doc('app').get();
    return PlanLimits.fromConfig(config.data());
  }

  Future<void> _ensureBelowLimit(CollectionReference col, int limit, String what) async {
    final count = (await col.count().get()).count ?? 0;
    if (count >= limit) {
      throw TrackingFailure('Llegaste al límite de $limit $what del plan gratuito.');
    }
  }

  // ---------- Favoritos ----------

  Stream<List<Favorite>> favorites() => _favorites
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Favorite.fromDoc).toList());

  Future<void> addFavorite({required String productId, required String productName, int? currentBestCents}) async {
    if ((await _favorites.doc(productId).get()).exists) return;
    await _ensureBelowLimit(_favorites, (await limits()).favorites, 'favoritos');
    await _favorites.doc(productId).set({
      'productId': productId,
      'productName': productName,
      'priceAtSaveCents': currentBestCents,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeFavorite(String productId) => _favorites.doc(productId).delete();

  // ---------- Listas ----------

  Stream<List<Wishlist>> wishlists() => _wishlists
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Wishlist.fromDoc).toList());

  Stream<Wishlist?> wishlist(String id) =>
      _wishlists.doc(id).snapshots().map((d) => d.exists ? Wishlist.fromDoc(d) : null);

  Future<String> createWishlist(String name) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 120) throw const TrackingFailure('El nombre debe tener entre 1 y 120 caracteres.');
    await _ensureBelowLimit(_wishlists, (await limits()).wishlists, 'listas');
    final ref = await _wishlists.add({
      'name': clean,
      'productIds': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> renameWishlist(String id, String name) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 120) throw const TrackingFailure('El nombre debe tener entre 1 y 120 caracteres.');
    final doc = await _wishlists.doc(id).get();
    await _wishlists.doc(id).set({
      ...?doc.data(),
      'name': clean,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addToWishlist(String listId, String productId) async {
    final doc = await _wishlists.doc(listId).get();
    final list = Wishlist.fromDoc(doc);
    if (list.productIds.contains(productId)) return;
    if (list.productIds.length >= (await limits()).itemsPerList) {
      throw const TrackingFailure('La lista está llena.');
    }
    await _wishlists.doc(listId).set({
      ...?doc.data(),
      'productIds': [...list.productIds, productId],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeFromWishlist(String listId, String productId) async {
    final doc = await _wishlists.doc(listId).get();
    final list = Wishlist.fromDoc(doc);
    await _wishlists.doc(listId).set({
      ...?doc.data(),
      'productIds': list.productIds.where((p) => p != productId).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteWishlist(String id) => _wishlists.doc(id).delete();

  // ---------- Alertas ----------

  Stream<List<PriceAlert>> alerts() => _alerts
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(PriceAlert.fromDoc).toList());

  Stream<PriceAlert?> alertForProduct(String productId) => _alerts
      .where('productId', isEqualTo: productId)
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : PriceAlert.fromDoc(s.docs.first));

  /// Crea o actualiza la alerta del producto (una por producto). Al editarla se reactiva.
  Future<void> saveAlert({
    required String productId,
    required String productName,
    required int targetPriceCents,
  }) async {
    if (targetPriceCents <= 0) throw const TrackingFailure('Ingresa un precio objetivo mayor a cero.');
    final existing = await _alerts.where('productId', isEqualTo: productId).limit(1).get();
    final data = {
      'productId': productId,
      'variantId': null,
      'productName': productName,
      'targetPriceCents': targetPriceCents,
      'currency': 'PEN',
      'condition': 'AT_OR_BELOW',
      'status': 'ACTIVE',
      // Al cambiar el objetivo, la alerta puede volver a avisar (RN-08).
      'lastTriggeredPriceCents': null,
    };
    if (existing.docs.isNotEmpty) {
      final doc = existing.docs.first;
      await doc.reference.set({...doc.data(), ...data});
      return;
    }
    await _ensureBelowLimit(_alerts, (await limits()).alerts, 'alertas');
    await _alerts.add({...data, 'lastTriggeredAt': null, 'createdAt': FieldValue.serverTimestamp()});
  }

  Future<void> setAlertPaused(PriceAlert alert, bool paused) async {
    final doc = await _alerts.doc(alert.id).get();
    await _alerts.doc(alert.id).set({...?doc.data(), 'status': paused ? 'PAUSED' : 'ACTIVE'});
  }

  Future<void> deleteAlert(String id) => _alerts.doc(id).delete();
}

/// Repositorio del usuario con sesión (`null` si es visitante).
final trackingRepositoryProvider = Provider<TrackingRepository?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  final premium = ref.watch(userProfileProvider).value?.isPremium ?? false;
  return TrackingRepository(FirebaseFirestore.instance, user.uid, isPremium: premium);
});

final favoritesProvider = StreamProvider<List<Favorite>>((ref) {
  final repo = ref.watch(trackingRepositoryProvider);
  return repo == null ? Stream.value(const []) : repo.favorites();
});

final wishlistsProvider = StreamProvider<List<Wishlist>>((ref) {
  final repo = ref.watch(trackingRepositoryProvider);
  return repo == null ? Stream.value(const []) : repo.wishlists();
});

final wishlistProvider = StreamProvider.family<Wishlist?, String>((ref, id) {
  final repo = ref.watch(trackingRepositoryProvider);
  return repo == null ? Stream.value(null) : repo.wishlist(id);
});

final alertsProvider = StreamProvider<List<PriceAlert>>((ref) {
  final repo = ref.watch(trackingRepositoryProvider);
  return repo == null ? Stream.value(const []) : repo.alerts();
});

/// ¿El producto está en favoritos? (derivado de la lista, sin lecturas extra)
final isFavoriteProvider = Provider.family<bool, String>(
  (ref, productId) => ref.watch(favoritesProvider).value?.any((f) => f.productId == productId) ?? false,
);

/// Alerta del producto, si existe (derivada de la lista de alertas).
final alertForProductProvider = Provider.family<PriceAlert?, String>(
  (ref, productId) => ref.watch(alertsProvider).value?.where((a) => a.productId == productId).firstOrNull,
);
