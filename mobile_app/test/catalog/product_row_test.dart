import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:precio_justo/features/catalog/product_row.dart';
import 'package:precio_justo/models/models.dart';
import 'package:precio_justo/services/catalog_repository.dart';

Product product({int? price, Duration? age, int offers = 1}) => Product(
      id: 'p',
      name: 'Kingston NV3 1TB',
      brand: 'Kingston',
      categorySlug: 'ssd',
      summary: PriceSummary(
        minPriceCents: price,
        offerCount: offers,
        lastCheckedAt: age == null ? null : DateTime.now().toUtc().subtract(age),
      ),
    );

Future<void> pump(WidgetTester tester, Product p, {Map<String, StoreInfo> stores = const {}}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [storesProvider.overrideWith((ref) async => stores)],
    child: MaterialApp(home: Scaffold(body: ProductRow(product: p))),
  ));
  await tester.pump();
}

void main() {
  testWidgets('precio vigente se muestra "desde"', (tester) async {
    await pump(tester, product(price: 24990, age: const Duration(hours: 2)));
    expect(find.text('S/ 249.90'), findsOneWidget);
    expect(find.text('desde'), findsOneWidget);
  });

  testWidgets('precio vencido no se presenta como confirmado (RN-01)', (tester) async {
    await pump(tester, product(price: 24990, age: const Duration(days: 3)));
    expect(find.text('S/ 249.90'), findsNothing);
    expect(find.text('Precio por\nconfirmar'), findsOneWidget);
  });

  testWidgets('sin precio verificado', (tester) async {
    await pump(tester, product(offers: 0));
    expect(find.text('Sin precio\nverificado'), findsOneWidget);
    expect(find.textContaining('Sin ofertas aún'), findsOneWidget);
  });

  testWidgets('resumen antiguo pero confirmado por la última corrida de la tienda', (tester) async {
    final p = Product(
      id: 'p',
      name: 'Kingston NV3 1TB',
      brand: 'Kingston',
      categorySlug: 'ssd',
      summary: PriceSummary(
        minPriceCents: 24990,
        minPriceStoreCode: 'COOLBOX',
        offerCount: 1,
        lastCheckedAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
      ),
    );
    final stores = {
      'COOLBOX': StoreInfo(code: 'COOLBOX', lastCompleteRunAt: DateTime.now().toUtc().subtract(const Duration(hours: 2))),
    };
    await pump(tester, p, stores: stores);
    expect(find.text('S/ 249.90'), findsOneWidget);
  });

  test('verificación efectiva de una oferta', () {
    final old = DateTime.utc(2026, 11, 20);
    final run = DateTime.utc(2026, 11, 23);
    final offer = StoreOffer(
      id: 'x', storeCode: 'A', storeName: 'A', title: 't', productUrl: 'https://x',
      priceCents: 100, availability: Availability.available, lastCheckedAt: old,
    );
    final store = StoreInfo(code: 'A', lastCompleteRunAt: run);
    expect(effectiveCheckedAt(offer, store), run);
    expect(effectiveCheckedAt(offer, null), old);
    final missing = StoreOffer(
      id: 'x', storeCode: 'A', storeName: 'A', title: 't', productUrl: 'https://x',
      priceCents: 100, availability: Availability.available, lastCheckedAt: old, missedRuns: 1,
    );
    expect(effectiveCheckedAt(missing, store), old); // no apareció en la última corrida
  });
}
