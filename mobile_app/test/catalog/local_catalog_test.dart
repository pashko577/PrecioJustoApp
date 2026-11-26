import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compramejor/core/search_normalizer.dart';
import 'package:compramejor/services/catalog_repository.dart';
import 'package:compramejor/services/local_catalog.dart';

Map<String, dynamic> catalogJson({int ps5Price = 199900}) => {
  'version': 1,
  'generatedAt': '2026-11-24T12:00:00Z',
  'categories': [
    {'slug': 'tecnologia', 'name': 'Tecnología', 'order': 1},
    {'slug': 'consolas', 'name': 'Consolas', 'parentSlug': 'tecnologia', 'order': 2},
    {'slug': 'laptops', 'name': 'Laptops', 'parentSlug': 'tecnologia', 'order': 3},
  ],
  'stores': [
    {'code': 'COOLBOX', 'name': 'Coolbox', 'freshnessMinutes': 1440, 'lastCompleteRunAt': '2026-11-24T10:00:00Z', 'active': true},
  ],
  'products': [
    {'id': 'ps5', 'name': 'Consola Sony PlayStation 5 Slim', 'brand': 'Sony', 'categorySlug': 'consolas',
     'identifiers': {'GTIN': ['0711719577294']},
     'summary': {'minPriceCents': ps5Price, 'offerCount': 1, 'priceDropPercent': 10, 'priceDropFromCents': 222100,
                 'priceDroppedAt': '2026-11-23T10:00:00Z'}},
    {'id': 'lenovo', 'name': 'Laptop Lenovo IdeaPad Slim 3', 'brand': 'Lenovo', 'categorySlug': 'laptops',
     'summary': {'minPriceCents': 150000, 'offerCount': 2}},
    {'id': 'sin-precio', 'name': 'Laptop sin precio', 'brand': 'X', 'categorySlug': 'laptops', 'summary': {}},
    {'id': 'viejo', 'status': 'MERGED', 'mergedInto': 'ps5'},
  ],
  'offers': [
    {'id': 'COOLBOX__1', 'productId': 'ps5', 'storeCode': 'COOLBOX', 'storeName': 'Coolbox', 'title': 'PS5',
     'productUrl': 'https://x', 'priceCents': ps5Price, 'availability': 'AVAILABLE',
     'lastCheckedAt': '2026-11-24T09:00:00Z', 'lastChangedAt': '2026-11-23T10:00:00Z'},
    // Dos vendedores del marketplace de Plaza Vea: una sola tienda.
    for (final n in [1, 2])
      {'id': 'PLAZAVEA__$n', 'productId': 'lenovo', 'storeCode': 'PLAZAVEA', 'storeName': 'Plaza Vea',
       'title': 'Lenovo', 'productUrl': 'https://x', 'priceCents': 150000 + n, 'availability': 'AVAILABLE',
       'lastCheckedAt': '2026-11-24T09:00:00Z'},
  ],
};

void main() {
  final catalog = LocalCatalog.fromJson(catalogJson());

  test('listado ordenado por precio, sin precio al final, con filtro de categoría', () {
    final all = catalog.page(limit: 2);
    expect(all.items.map((p) => p.id), ['lenovo', 'ps5']);
    expect(all.hasMore, isTrue);
    expect(catalog.page(offset: all.next).items.single.id, 'sin-precio');
    expect(catalog.page(categorySlugs: ['laptops']).items.map((p) => p.id), ['lenovo', 'sin-precio']);
    expect(catalog.productCount, 3); // el unificado no se lista
  });

  test('búsqueda local por palabras (con prefijo) y por código de barras', () {
    expect(catalog.search(SearchQuery.parse('playstation slim')).single.id, 'ps5');
    expect(catalog.search(SearchQuery.parse('lenovo idea')).single.id, 'lenovo');
    expect(catalog.search(SearchQuery.parse('711719577294')).single.id, 'ps5'); // UPC → GTIN canónico
    expect(catalog.search(SearchQuery.parse('nokia')), isEmpty);
  });

  test('ofertas, tiendas, bajadas y productos unificados', () {
    final offer = catalog.offers('ps5').single;
    expect(offer.priceCents, 199900);
    expect(offer.lastChangedAt, DateTime.utc(2026, 11, 23, 10));
    expect(catalog.stores['COOLBOX']!.lastCompleteRunAt, DateTime.utc(2026, 11, 24, 10));
    expect(catalog.priceDrops().single.id, 'ps5');
    expect(catalog.product('viejo')!.mergedInto, 'ps5');
    expect(catalog.categories.first.slug, 'tecnologia');
  });

  test('formato desconocido se rechaza', () {
    expect(() => LocalCatalog.fromJson({'version': 99}), throwsFormatException);
  });

  group('CatalogCache', () {
    late HttpServer server;
    late Directory dir;
    var hits = 0;
    var price = 199900;

    setUp(() async {
      hits = 0;
      dir = await Directory.systemTemp.createTemp('catalogo');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        hits++;
        final etag = '"v$price"';
        if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
          req.response.statusCode = HttpStatus.notModified;
        } else {
          req.response.headers.set(HttpHeaders.etagHeader, etag);
          req.response.write(jsonEncode(catalogJson(ps5Price: price)));
        }
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    CatalogCache cache({Duration maxAge = const Duration(hours: 2)}) => CatalogCache(
      url: Uri.parse('http://127.0.0.1:${server.port}/catalog.json'),
      directory: () async => dir,
      maxAge: maxAge,
    );

    test('descarga, guarda en el celular y luego abre sin internet', () async {
      final online = cache();
      final first = await online.get();
      expect(first!.product('ps5'), isNotNull);
      expect(File('${dir.path}/catalog.json').existsSync(), isTrue);

      final url = online.url;
      await server.close(force: true); // sin conexión
      final offline = await CatalogCache(url: url, directory: () async => dir).get();
      expect(offline!.offers('ps5').single.priceCents, 199900);
    });

    test('al vencer pregunta con ETag: 304 no vuelve a descargar; cambio sí', () async {
      final c = cache(maxAge: Duration.zero);
      await c.get();
      await c.refresh(); // mismo ETag → 304
      expect(hits, 2);
      price = 189900;
      await c.refresh();
      expect((await c.get())!.offers('ps5').single.priceCents, 189900);
      price = 199900;
    });

    test('el repositorio usa el catálogo local y no Firestore', () async {
      final repo = CatalogRepository(FakeFirebaseFirestore(), local: cache());
      expect((await repo.productsPage()).items.first.id, 'lenovo');
      expect((await repo.search('playstation slim')).single.id, 'ps5');
      expect((await repo.offers('ps5')).single.storeCode, 'COOLBOX');
      expect((await repo.stores()).keys, ['COOLBOX']);
    });
  });

  test('sin catálogo disponible el repositorio vuelve a Firestore', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('products').doc('p1').set({
      'displayName': 'Producto en línea', 'status': 'ACTIVE', 'categorySlug': 'laptops',
      'summary': {'sortPriceCents': 100},
    });
    final repo = CatalogRepository(db, local: CatalogCache(
      url: Uri.parse('http://127.0.0.1:1/no-existe.json'),
      directory: () async => Directory.systemTemp.createTemp('vacio'),
    ));
    expect((await repo.productsPage()).items.single.name, 'Producto en línea');
  });

  test('cuenta tiendas distintas, no publicaciones', () {
    final lenovo = catalog.page(limit: 10).items.firstWhere((p) => p.id == 'lenovo');
    expect(lenovo.summary.offerCount, 2); // dos publicaciones (resumen sin storeCount)
    expect(lenovo.summary.storeCount, 1);
    final ps5 = catalog.page(limit: 10).items.firstWhere((p) => p.id == 'ps5');
    expect(ps5.summary.storeCount, 1);
  });
}
