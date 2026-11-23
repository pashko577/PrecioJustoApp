import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/offer_rules.dart';
import '../core/search_normalizer.dart';
import '../models/models.dart';

/// Una página del catálogo y el cursor para pedir la siguiente.
class ProductPage {
  const ProductPage({required this.items, required this.cursor, required this.hasMore});

  final List<Product> items;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

/// Acceso de solo lectura al catálogo público (PRECIO_JUSTO.md, sección 11.1).
/// Todas las consultas usan `limit` y lecturas puntuales (`get`) para cuidar la cuota gratuita.
class CatalogRepository {
  CatalogRepository(this._db);

  final FirebaseFirestore _db;

  static const pageSize = 20;
  static const searchLimit = 40;

  CollectionReference<Map<String, dynamic>> get _products => _db.collection('products');

  Future<List<Category>> categories() async {
    final snap = await _db.collection('categories').where('status', isEqualTo: 'ACTIVE').get();
    return snap.docs.map(Category.fromDoc).toList()..sort((a, b) => a.order.compareTo(b.order));
  }

  /// Productos activos ordenados por precio (los que no tienen precio verificado van al final,
  /// gracias a `summary.sortPriceCents`). Filtra por categorías (máx. 30, límite de `whereIn`).
  Future<ProductPage> productsPage({
    List<String>? categorySlugs,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = pageSize,
  }) async {
    Query<Map<String, dynamic>> query = _products.where('status', isEqualTo: 'ACTIVE');
    if (categorySlugs != null && categorySlugs.isNotEmpty) {
      query = query.where('categorySlug', whereIn: categorySlugs.take(30).toList());
    }
    query = query.orderBy('summary.sortPriceCents');
    if (startAfter != null) query = query.startAfterDocument(startAfter);

    // Se pide uno extra para saber si hay otra página sin hacer otra consulta.
    final snap = await query.limit(limit + 1).get();
    final docs = snap.docs;
    final hasMore = docs.length > limit;
    final pageDocs = hasMore ? docs.sublist(0, limit) : docs;
    return ProductPage(
      items: pageDocs.map(Product.fromDoc).toList(),
      cursor: pageDocs.isEmpty ? startAfter : pageDocs.last,
      hasMore: hasMore,
    );
  }

  /// Búsqueda por palabras (RF-02) o por código de barras.
  ///
  /// Firestore solo permite un `array-contains` por consulta: se envía la palabra más
  /// selectiva y el resto se filtra en la app. No tolera errores ortográficos (fase posterior).
  Future<List<Product>> search(String raw) async {
    final query = SearchQuery.parse(raw);
    if (query.isEmpty) return const [];

    if (query.barcode != null) {
      final code = query.barcode!; // canónico (13 dígitos), ver canonicalGtin
      final snap = await _products.where('identifierKeys', arrayContains: 'GTIN:$code').limit(10).get();
      return snap.docs.map(Product.fromDoc).where((p) => p.status == 'ACTIVE').toList();
    }

    final snap = await _products
        .where('searchTokens', arrayContains: query.keyWord)
        .where('status', isEqualTo: 'ACTIVE')
        .limit(searchLimit)
        .get();
    final results = snap.docs.map(Product.fromDoc).where((p) => query.matches(p.searchTokens)).toList();
    results.sort(compareByPrice);
    return results;
  }

  Future<Product?> product(String id) async {
    final doc = await _products.doc(id).get();
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

/// Más baratos primero; sin precio verificado al final; empate por nombre.
int compareByPrice(Product a, Product b) {
  final pa = a.summary.minPriceCents, pb = b.summary.minPriceCents;
  if (pa == null && pb == null) return a.name.compareTo(b.name);
  if (pa == null) return 1;
  if (pb == null) return -1;
  final byPrice = pa.compareTo(pb);
  return byPrice != 0 ? byPrice : a.name.compareTo(b.name);
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

/// Categoría de primer nivel a la que pertenece [slug].
Category? topLevelOf(String slug, List<Category> all) {
  final bySlug = {for (final c in all) c.slug: c};
  var current = bySlug[slug];
  while (current != null && current.parentSlug != null) {
    current = bySlug[current.parentSlug];
  }
  return current;
}

/// Estado del listado paginado del catálogo.
class CatalogFeed {
  const CatalogFeed({required this.items, required this.hasMore, this.cursor, this.loadingMore = false});

  final List<Product> items;
  final bool hasMore;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool loadingMore;

  CatalogFeed copyWith({bool? loadingMore}) =>
      CatalogFeed(items: items, hasMore: hasMore, cursor: cursor, loadingMore: loadingMore ?? this.loadingMore);
}

class CatalogFeedNotifier extends AsyncNotifier<CatalogFeed> {
  List<String>? _slugs;

  @override
  Future<CatalogFeed> build() async {
    final selected = ref.watch(selectedCategoryProvider);
    _slugs = selected == null ? null : withDescendants(selected, await ref.watch(categoriesProvider.future));
    final page = await ref.watch(catalogRepositoryProvider).productsPage(categorySlugs: _slugs);
    return CatalogFeed(items: page.items, hasMore: page.hasMore, cursor: page.cursor);
  }

  /// Carga la siguiente página. Ignora llamadas repetidas mientras hay una en curso.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(catalogRepositoryProvider)
          .productsPage(categorySlugs: _slugs, startAfter: current.cursor);
      state = AsyncData(CatalogFeed(
        items: [...current.items, ...page.items],
        hasMore: page.hasMore,
        cursor: page.cursor,
      ));
    } catch (_) {
      // Se conserva lo cargado; el usuario puede reintentar al volver a desplazarse.
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }
}

final catalogFeedProvider = AsyncNotifierProvider<CatalogFeedNotifier, CatalogFeed>(CatalogFeedNotifier.new);

final searchResultsProvider = FutureProvider.autoDispose.family<List<Product>, String>(
  (ref, query) => ref.watch(catalogRepositoryProvider).search(query),
);

final productProvider = FutureProvider.family<Product?, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).product(id),
);

final offersProvider = FutureProvider.family<List<StoreOffer>, String>((ref, productId) async {
  final offers = await ref.watch(catalogRepositoryProvider).offers(productId);
  final freshness = await ref.watch(storeFreshnessProvider.future);
  return sortOffers(offers, (code) => freshness[code] ?? defaultFreshnessMinutes);
});
