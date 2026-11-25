import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';

/// Publicación que el motor no pudo asociar con seguridad (`matchStatus: PENDING_REVIEW`).
/// Conserva el producto sugerido (`productId`) sin mostrarse como precio hasta que se apruebe.
class PendingListing {
  const PendingListing({
    required this.id,
    required this.storeName,
    required this.title,
    required this.priceCents,
    required this.productUrl,
    this.suggestedProductId,
    this.imageUrl,
    this.matchScore,
    this.matchReason,
  });

  final String id;
  final String storeName;
  final String title;
  final int priceCents;
  final String productUrl;
  final String? suggestedProductId;
  final String? imageUrl;
  final int? matchScore;
  final String? matchReason;

  factory PendingListing.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return PendingListing(
      id: doc.id,
      storeName: d['storeName'] as String? ?? d['storeCode'] as String? ?? '',
      title: d['title'] as String? ?? '',
      priceCents: (d['currentPriceCents'] as num?)?.toInt() ?? 0,
      productUrl: d['productUrl'] as String? ?? '',
      suggestedProductId: d['productId'] as String?,
      imageUrl: d['imageUrl'] as String?,
      matchScore: (d['matchScore'] as num?)?.toInt(),
      matchReason: d['matchReason'] as String?,
    );
  }
}

class PendingPage {
  const PendingPage(this.items, this.cursor, this.hasMore);
  final List<PendingListing> items;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

/// Revisión manual de asociaciones desde la app (solo administradores; ver firestore.rules).
///
/// Hace lo mismo que `python -m app.admin.review_matches approve|reject`, salvo recalcular el
/// precio del producto: eso lo hace el motor al final de la próxima corrida, con las
/// publicaciones marcadas `needsSummary` (la app no puede calcular el resumen completo).
class ReviewRepository {
  ReviewRepository(this._db, this._uid);

  final FirebaseFirestore _db;
  final String _uid;
  static const pageSize = 20;

  CollectionReference<Map<String, dynamic>> get _listings => _db.collection('storeProducts');

  /// Más recientes primero (índice `matchStatus + createdAt`). Cada página cuesta ~20 lecturas.
  Future<PendingPage> pending({DocumentSnapshot<Map<String, dynamic>>? startAfter}) async {
    Query<Map<String, dynamic>> query = _listings
        .where('matchStatus', isEqualTo: 'PENDING_REVIEW')
        .orderBy('createdAt', descending: true);
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    final snap = await query.limit(pageSize + 1).get();
    final docs = snap.docs.take(pageSize).toList();
    return PendingPage(docs.map(PendingListing.fromDoc).toList(), docs.isEmpty ? startAfter : docs.last,
        snap.docs.length > pageSize);
  }

  Future<void> approve(PendingListing listing) {
    if (listing.suggestedProductId == null) {
      throw StateError('La publicación no tiene un producto sugerido.');
    }
    return _decide(listing.id, {
      'matchStatus': 'MATCHED_MANUAL',
      'matchScore': 100,
      'matchReason': 'aprobado en la app',
      'needsSummary': true, // el motor recalcula el precio del producto
    });
  }

  Future<void> reject(PendingListing listing) => _decide(listing.id, {
    'matchStatus': 'REJECTED',
    'productId': null,
    'matchReason': 'rechazado en la app',
  });

  Future<void> _decide(String id, Map<String, Object?> changes) => _listings.doc(id).update({
    ...changes,
    'reviewedBy': _uid,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

/// ¿La sesión tiene el permiso `admin` (custom claim)? Se lee del token, sin consultas.
final isAdminProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return false;
  final token = await user.getIdTokenResult();
  return token.claims?['admin'] == true;
});

final reviewRepositoryProvider = Provider<ReviewRepository?>((ref) {
  final User? user = ref.watch(authStateProvider).value;
  return user == null ? null : ReviewRepository(FirebaseFirestore.instance, user.uid);
});
