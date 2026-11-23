import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/offer_rules.dart';
import '../core/price_history.dart';
import '../core/search_normalizer.dart';
import '../models/models.dart';

/// Una página del catálogo y el cursor para pedir la siguiente.
class ProductPage {
  const ProductPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });

  final List<Product> items;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

/// Acceso de solo lectura al catálogo público (COMPRA_MEJOR.md, sección 11.1).
/// Todas las consultas usan `limit` y lecturas puntuales (`get`) para cuidar la cuota gratuita.
class CatalogRepository {
  CatalogRepository(this._db);

  final FirebaseFirestore _db;

  static const pageSize = 20;
  static const searchLimit = 40;

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('products');

  Future<List<Category>> categories() async {
    final snap = await _db
        .collection('categories')
        .where('status', isEqualTo: 'ACTIVE')
        .get();
    return snap.docs.map(Category.fromDoc).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  /// Productos activos ordenados por precio (los que no tienen precio verificado van al final,
  /// gracias a `summary.sortPriceCents`). Filtra por categorías (máx. 30, límite de `whereIn`).
  Future<ProductPage> productsPage({
    List<String>? categorySlugs,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = pageSize,
  }) async {
    Query<Map<String, dynamic>> query = _products.where(
      'status',
      isEqualTo: 'ACTIVE',
    );
    if (categorySlugs != null && categorySlugs.isNotEmpty) {
      query = query.where(
        'categorySlug',
        whereIn: categorySlugs.take(30).toList(),
      );
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
      final snap = await _products
          .where('identifierKeys', arrayContains: 'GTIN:$code')
          .limit(10)
          .get();
      return snap.docs
          .map(Product.fromDoc)
          .where((p) => p.status == 'ACTIVE')
          .toList();
    }

    final snap = await _products
        .where('searchTokens', arrayContains: query.keyWord)
        .where('status', isEqualTo: 'ACTIVE')
        .limit(searchLimit)
        .get();
    final results = snap.docs
        .map(Product.fromDoc)
        .where((p) => query.matches(p.searchTokens))
        .toList();
    results.sort(compareByPrice);
    return results;
  }

  /// Productos cuyo mejor precio bajó hace poco, de mayor a menor bajada (banner de Inicio).
  /// Una sola consulta con `limit`: unas pocas lecturas por visita.
  Future<List<Product>> priceDrops({int limit = 8}) async {
    final snap = await _products
        .where('status', isEqualTo: 'ACTIVE')
        .where('summary.priceDropPercent', isGreaterThan: 0)
        .orderBy('summary.priceDropPercent', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(Product.fromDoc).toList();
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
    return snap.docs.where(isShownMatch).map(StoreOffer.fromDoc).toList();
  }

  /// Solo asociaciones confirmadas: una publicación en revisión conserva el producto como
  /// sugerencia y no se muestra como precio hasta que se apruebe (igual que el motor).
  static bool isShownMatch(DocumentSnapshot<Map<String, dynamic>> doc) =>
      shownMatchStatuses.contains(doc.data()?['matchStatus'] ?? 'MATCHED_AUTO');

  static const shownMatchStatuses = {'MATCHED_AUTO', 'MATCHED_MANUAL'};

  /// Historial de precios de las ofertas en los últimos [days] días (RF-05).
  /// Lee un documento `history/{YYYY-MM}` por oferta y por mes, en paralelo.
  Future<List<OfferHistory>> history(
    List<StoreOffer> offers, {
    required int days,
    DateTime? now,
  }) async {
    final months = monthsCovering(now ?? DateTime.now().toUtc(), days);
    return Future.wait(
      offers.map((offer) async {
        final docs = await Future.wait(
          months.map(
            (m) => _db
                .collection('storeProducts')
                .doc(offer.id)
                .collection('history')
                .doc(m)
                .get(),
          ),
        );
        final data = [
          for (final d in docs)
            if (d.exists) d.data()!,
        ];
        return OfferHistory(
          offer: offer,
          points: parseHistoryPoints(data, _toUtc),
        );
      }),
    );
  }

  static DateTime _toUtc(Object? value) => value is Timestamp
      ? value.toDate().toUtc()
      : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// Vigencia y última corrida completa por tienda. Pocas tiendas: una sola lectura de la colección.
  Future<Map<String, StoreInfo>> stores() async {
    final snap = await _db.collection('stores').get();
    return {for (final d in snap.docs) d.id: StoreInfo.fromDoc(d)};
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

final storesProvider = FutureProvider<Map<String, StoreInfo>>(
  (ref) => ref.watch(catalogRepositoryProvider).stores(),
);

/// Vigencia en minutos por tienda (derivado de `storesProvider`).
final storeFreshnessProvider = FutureProvider<Map<String, int>>((ref) async {
  final stores = await ref.watch(storesProvider.future);
  return {for (final s in stores.values) s.code: s.freshnessMinutes};
});

/// Categoría seleccionada en la pantalla de inicio (`null` = todas).
class SelectedCategory extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? slug) => state = slug;
}

final selectedCategoryProvider = NotifierProvider<SelectedCategory, String?>(
  SelectedCategory.new,
);

/// Incluye la categoría elegida y todas sus subcategorías.
List<String> withDescendants(String slug, List<Category> all) {
  final result = <String>[slug];
  for (var i = 0; i < result.length; i++) {
    result.addAll(
      all.where((c) => c.parentSlug == result[i]).map((c) => c.slug),
    );
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
  const CatalogFeed({
    required this.items,
    required this.hasMore,
    this.cursor,
    this.loadingMore = false,
  });

  final List<Product> items;
  final bool hasMore;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool loadingMore;

  CatalogFeed copyWith({bool? loadingMore}) => CatalogFeed(
    items: items,
    hasMore: hasMore,
    cursor: cursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

class CatalogFeedNotifier extends AsyncNotifier<CatalogFeed> {
  List<String>? _slugs;

  @override
  Future<CatalogFeed> build() async {
    final selected = ref.watch(selectedCategoryProvider);
    _slugs = selected == null
        ? null
        : withDescendants(selected, await ref.watch(categoriesProvider.future));
    final page = await ref
        .watch(catalogRepositoryProvider)
        .productsPage(categorySlugs: _slugs);
    return CatalogFeed(
      items: page.items,
      hasMore: page.hasMore,
      cursor: page.cursor,
    );
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
      state = AsyncData(
        CatalogFeed(
          items: [...current.items, ...page.items],
          hasMore: page.hasMore,
          cursor: page.cursor,
        ),
      );
    } catch (_) {
      // Se conserva lo cargado; el usuario puede reintentar al volver a desplazarse.
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }
}

final catalogFeedProvider =
    AsyncNotifierProvider<CatalogFeedNotifier, CatalogFeed>(
      CatalogFeedNotifier.new,
    );

/// Historial de un producto para un periodo: clave `(productId, días)`.
final historyProvider = FutureProvider.autoDispose
    .family<List<OfferHistory>, (String, int)>((ref, key) async {
      final (productId, days) = key;
      final offers = await ref.watch(offersProvider(productId).future);
      return ref.watch(catalogRepositoryProvider).history(offers, days: days);
    });

/// Bajadas recientes y vigentes para el banner de Inicio (vacío si la consulta falla, por
/// ejemplo mientras se crea el índice: el banner cae al mensaje general).
final priceDropsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final items = await ref.watch(catalogRepositoryProvider).priceDrops();
    return items.where((p) => p.summary.hasRecentDrop()).toList();
  } catch (_) {
    return const [];
  }
});

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<Product>, String>(
      (ref, query) => ref.watch(catalogRepositoryProvider).search(query),
    );

final productProvider = FutureProvider.family<Product?, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).product(id),
);

final offersProvider = FutureProvider.family<List<StoreOffer>, String>((
  ref,
  productId,
) async {
  final raw = await ref.watch(catalogRepositoryProvider).offers(productId);
  final stores = await ref.watch(storesProvider.future);
  // La fecha que ve el usuario es la verificación real (incluye la última corrida completa).
  final offers = [
    for (final o in raw)
      o.withCheckedAt(effectiveCheckedAt(o, stores[o.storeCode])),
  ];
  return sortOffers(
    offers,
    (code) => stores[code]?.freshnessMinutes ?? defaultFreshnessMinutes,
  );
});
