import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compramejor/features/catalog/search_screen.dart';
import 'package:compramejor/models/models.dart';
import 'package:compramejor/services/catalog_repository.dart';

const noPrice = 9999999999; // NO_PRICE_SORT_VALUE en Python

/// Tokens como los genera Python (palabras + prefijos desde 3 letras).
List<String> tokens(List<String> words) {
  final result = <String>{};
  for (final w in words) {
    result.add(w);
    if (!RegExp(r'^\d+$').hasMatch(w)) {
      for (var end = 3; end < w.length; end++) {
        result.add(w.substring(0, end));
      }
    }
  }
  return result.toList()..sort();
}

Future<void> addProduct(
  FakeFirebaseFirestore db,
  String id, {
  required String name,
  required String category,
  required List<String> words,
  int? price,
  String status = 'ACTIVE',
  List<String> identifierKeys = const [],
}) =>
    db.collection('products').doc(id).set({
      'displayName': name,
      'brand': name.split(' ').first,
      'categorySlug': category,
      'status': status,
      'searchTokens': tokens(words),
      'identifierKeys': identifierKeys,
      'summary': {'minPriceCents': price, 'sortPriceCents': price ?? noPrice, 'offerCount': price == null ? 0 : 1},
    });

void main() {
  late FakeFirebaseFirestore db;
  late CatalogRepository repo;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = CatalogRepository(db);
    await addProduct(db, 'knv3-1tb', name: 'Kingston NV3 1TB', category: 'ssd',
        words: ['1tb', 'kingston', 'nv3', 'ssd'], price: 24990, identifierKeys: ['GTIN:2001234567893']);
    await addProduct(db, 'knv3-2tb', name: 'Kingston NV3 2TB', category: 'ssd',
        words: ['2tb', 'kingston', 'nv3', 'ssd'], price: 45990);
    await addProduct(db, 'fury', name: 'Kingston Fury Beast 16GB', category: 'memorias-ram',
        words: ['16gb', 'beast', 'fury', 'kingston'], price: 21990);
    await addProduct(db, 'crucial', name: 'Crucial P3 Plus 1TB', category: 'ssd',
        words: ['1tb', 'crucial', 'p3', 'plus', 'ssd']); // sin precio
    await addProduct(db, 'viejo', name: 'Kingston A400 480GB', category: 'ssd',
        words: ['480gb', 'a400', 'kingston', 'ssd'], price: 9990, status: 'INACTIVE');
  });

  group('productsPage', () {
    test('ordena por precio, sin precio al final, y excluye inactivos', () async {
      final page = await repo.productsPage();
      expect(page.items.map((p) => p.id), ['fury', 'knv3-1tb', 'knv3-2tb', 'crucial']);
      expect(page.hasMore, isFalse);
    });

    test('filtra por categorías', () async {
      final page = await repo.productsPage(categorySlugs: ['memorias-ram']);
      expect(page.items.map((p) => p.id), ['fury']);
    });

    test('pagina con cursor sin repetir ni saltar productos', () async {
      final first = await repo.productsPage(limit: 2);
      expect(first.items.map((p) => p.id), ['fury', 'knv3-1tb']);
      expect(first.hasMore, isTrue);

      final second = await repo.productsPage(limit: 2, startAfter: first.cursor);
      expect(second.items.map((p) => p.id), ['knv3-2tb', 'crucial']);
      expect(second.hasMore, isFalse);
    });
  });

  group('search', () {
    Future<List<String>> ids(String q) async => (await repo.search(q)).map((p) => p.id).toList();

    test('todas las palabras deben coincidir', () async {
      expect(await ids('kingston nv3'), ['knv3-1tb', 'knv3-2tb']);
      expect(await ids('Kingston NV3 1000 GB'), ['knv3-1tb']); // 1000 GB = 1tb
      expect(await ids('kingston 2tb'), ['knv3-2tb']);
    });

    test('palabras incompletas', () async {
      expect(await ids('kings'), ['fury', 'knv3-1tb', 'knv3-2tb']);
      expect(await ids('kingston nv'), ['knv3-1tb', 'knv3-2tb']);
    });

    test('tildes y mayúsculas no importan', () async {
      expect(await ids('CRÚCIAL'), ['crucial']);
    });

    test('no devuelve productos inactivos', () async {
      expect(await ids('a400'), isEmpty);
    });

    test('código de barras', () async {
      expect(await ids('2001234567893'), ['knv3-1tb']);
      expect(await ids('2001-2345 67893'), ['knv3-1tb']);
      expect(await ids('0000000000000'), isEmpty);
    });

    test('consulta vacía no consulta Firestore', () async {
      expect(await ids('  '), isEmpty);
    });
  });

  testWidgets('pantalla de búsqueda muestra resultados y estados', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: SearchScreen()),
    ));
    expect(find.text('Lo más buscado'), findsOneWidget); // sugerencias con el buscador vacío

    await tester.enterText(find.byKey(const Key('search-field')), 'kingston nv3');
    await tester.pump(const Duration(milliseconds: 400)); // espera el debounce
    await tester.pumpAndSettle();
    expect(find.text('2 resultados'), findsOneWidget);
    expect(find.text('Kingston NV3 1TB'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('search-field')), 'xiaomi');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('No encontramos «xiaomi»'), findsOneWidget);
  });

  test('offers: solo asociaciones confirmadas (no las que están en revisión)', () async {
    Future<void> offer(String id, String status, int price) => db.collection('storeProducts').doc(id).set({
          'productId': 'knv3-1tb',
          'status': 'ACTIVE',
          'storeCode': id.split('__').first,
          'currentPriceCents': price,
          'matchStatus': status,
        });
    await offer('COOLBOX__1', 'MATCHED_AUTO', 24990);
    await offer('EFE__1', 'MATCHED_MANUAL', 25990);
    await offer('PLAZAVEA__1', 'PENDING_REVIEW', 19990); // sugerencia sin confirmar
    await offer('OECHSLE__1', 'REJECTED', 9990);
    final offers = await repo.offers('knv3-1tb');
    expect(offers.map((o) => o.id).toSet(), {'COOLBOX__1', 'EFE__1'});
  });

  test('compareByPrice', () {
    const a = Product(id: 'a', name: 'A', brand: '', categorySlug: '', summary: PriceSummary(minPriceCents: 100));
    const b = Product(id: 'b', name: 'B', brand: '', categorySlug: '');
    expect([b, a]..sort(compareByPrice), [a, b]);
  });
}
