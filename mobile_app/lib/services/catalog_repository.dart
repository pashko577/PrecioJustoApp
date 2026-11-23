import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/offer_rules.dart';
import '../models/models.dart';

/// Acceso de solo lectura al catálogo público (PRECIO_JUSTO.md, sección 11.1).
/// Todas las consultas usan `limit` y lecturas puntuales (`get`) para cuidar la cuota gratuita.
class CatalogRepository {
  CatalogRepository(this._db);

  final FirebaseFirestore _db;

  Future<List<Category>> categories() async {
    final snap = await _db.collection('categories').where('status', isEqualTo: 'ACTIVE').get();
    return snap.docs.map(Category.fromDoc).toList()..sort((a, b) => a.order.compareTo(b.order));
  }

  /// Productos activos, opcionalmente filtrados por categorías (máx. 30 por la cláusula `whereIn`).
  Future<List<Product>> products({List<String>? categorySlugs, int limit = 30}) async {
    Query<Map<String, dynamic>> query = _db.collection('products').where('status', isEqualTo: 'ACTIVE');
    if (categorySlugs != null && categorySlugs.isNotEmpty) {
      query = query.where('categorySlug', whereIn: categorySlugs.take(30).toList());
    }
    final snap = await query.limit(limit).get();
    final products = snap.docs.map(Product.fromDoc).toList();
    // Más baratos primero; los productos sin precio verificado, al final.
    products.sort((a, b) {
      final pa = a.summary.minPriceCents, pb = b.summary.minPriceCents;
      if (pa == null && pb == null) return a.name.compareTo(b.name);
      if (pa == null) return 1;
      if (pb == null) return -1;
      return pa.compareTo(pb);
    });
    return products;
  }

  Future<Product?> product(String id) async {
    final doc = await _db.collection('products').doc(id).get();
    return doc.exists ? Product.fromDoc(doc) : null;
  }

  Future<List<StoreOffer>> offers(String productId) async {
    final snap = await _db
        .collection('storeProducts')
        .where('productId', isEqualTo: productId)
        .where('status', isEqualTo: 'ACTIVE')
        .limit(50)
        .get();
    return snap.docs.map(StoreOffer.fromDoc).toList();
  }

  /// Vigencia por tienda (`stores.freshnessMinutes`). Pocas tiendas: una sola lectura de la colección.
  Future<Map<String, int>> storeFreshness() async {
    final snap = await _db.collection('stores').get();
    return {
      for (final d in snap.docs)
        d.id: (d.data()['freshnessMinutes'] as num?)?.toInt() ?? defaultFreshnessMinutes,
    };
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(FirebaseFirestore.instance),
);

final categoriesProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(catalogRepositoryProvider).categories(),
);

final storeFreshnessProvider = FutureProvider<Map<String, int>>(
  (ref) => ref.watch(catalogRepositoryProvider).storeFreshness(),
);

/// Categoría seleccionada en la pantalla de inicio (`null` = todas).
class SelectedCategory extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? slug) => state = slug;
}

final selectedCategoryProvider = NotifierProvider<SelectedCategory, String?>(SelectedCategory.new);

/// Incluye la categoría elegida y todas sus subcategorías.
List<String> withDescendants(String slug, List<Category> all) {
  final result = <String>[slug];
  for (var i = 0; i < result.length; i++) {
    result.addAll(all.where((c) => c.parentSlug == result[i]).map((c) => c.slug));
  }
  return result;
}

final productsProvider = FutureProvider<List<Product>>((ref) async {
  final selected = ref.watch(selectedCategoryProvider);
  final repo = ref.watch(catalogRepositoryProvider);
  if (selected == null) return repo.products();
  final categories = await ref.watch(categoriesProvider.future);
  return repo.products(categorySlugs: withDescendants(selected, categories));
});

final productProvider = FutureProvider.family<Product?, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).product(id),
);

final offersProvider = FutureProvider.family<List<StoreOffer>, String>((ref, productId) async {
  final offers = await ref.watch(catalogRepositoryProvider).offers(productId);
  final freshness = await ref.watch(storeFreshnessProvider.future);
  return sortOffers(offers, (code) => freshness[code] ?? defaultFreshnessMinutes);
});
