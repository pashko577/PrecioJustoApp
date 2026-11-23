import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:precio_justo/core/offer_rules.dart';
import 'package:precio_justo/features/catalog/product_screen.dart';
import 'package:precio_justo/features/offers/offer_tile.dart';
import 'package:precio_justo/models/models.dart';

final now = DateTime.utc(2026, 11, 23, 12);

StoreOffer offer(String store, int price, {Availability a = Availability.available, int hoursAgo = 1}) => StoreOffer(
      id: '${store}__1',
      storeCode: store,
      storeName: store,
      title: 'Kingston NV3 1TB',
      productUrl: 'https://example.com',
      priceCents: price,
      availability: a,
      lastCheckedAt: now.subtract(Duration(hours: hoursAgo)),
    );

bool fresh(StoreOffer o) => isFresh(o.lastCheckedAt, 720, now: now);

void main() {
  test('mejor y peor precio solo entre ofertas comparables', () {
    final offers = [
      offer('COOLBOX', 25990),
      offer('PLAZAVEA', 23990),
      offer('OECHSLE', 19990, hoursAgo: 48), // vieja: no cuenta
      offer('PROMART', 9990, a: Availability.outOfStock), // agotada: no cuenta
      offer('WONG', 27990),
    ];
    final c = compareOffers(offers, fresh);
    expect(c.best!.storeCode, 'PLAZAVEA');
    expect(c.highest!.storeCode, 'WONG');
    expect(c.comparableCount, 3);
    expect(c.maxSavingsCents, 4000);
    expect(differenceFromBest(offers[0], c, fresh), 2000);
    expect(differenceFromBest(offers[1], c, fresh), isNull); // es la mejor
    expect(differenceFromBest(offers[2], c, fresh), isNull); // no comparable
  });

  test('con una sola oferta no hay ahorro que mostrar', () {
    final c = compareOffers([offer('COOLBOX', 25990)], fresh);
    expect(c.best!.storeCode, 'COOLBOX');
    expect(c.maxSavingsCents, isNull);
  });

  test('sin ofertas comparables', () {
    final c = compareOffers([offer('A', 100, hoursAgo: 99)], fresh);
    expect(c.best, isNull);
    expect(c.maxSavingsCents, isNull);
  });

  Future<void> pump(WidgetTester tester, Widget w) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));

  testWidgets('encabezado muestra mejor precio, tiendas y ahorro', (tester) async {
    final c = compareOffers([offer('Coolbox', 25990), offer('Plaza Vea', 23990)], fresh);
    await pump(tester, ComparisonHeader(comparison: c, totalOffers: 2));
    expect(tester.widget<Text>(find.byKey(const Key('best-price'))).data, 'S/ 239.90');
    expect(find.text('en Plaza Vea'), findsOneWidget);
    expect(find.text('Comparado en 2 tiendas'), findsOneWidget);
    expect(find.text('Ahorras hasta S/ 20.00 frente a Coolbox'), findsOneWidget);
  });

  testWidgets('encabezado sin precios verificados', (tester) async {
    await pump(tester, const ComparisonHeader(comparison: OfferComparison(), totalOffers: 3));
    expect(find.textContaining('Ninguna oferta tiene un precio verificado'), findsOneWidget);
  });

  testWidgets('la oferta muestra cuánto más cuesta', (tester) async {
    await pump(tester, OfferTile(offer: offer('Coolbox', 25990), fresh: true, differenceCents: 2000, now: now));
    expect(find.text('S/ 20.00 más que el mejor precio'), findsOneWidget);
  });

  test('cuenta tiendas distintas y detecta vendedores de marketplace', () {
    final a = offer('OECHSLE', 28900);
    final b = StoreOffer(
      id: 'OECHSLE__2', storeCode: 'OECHSLE', storeName: 'Oechsle', title: 't', productUrl: 'https://x',
      priceCents: 34900, availability: Availability.available, lastCheckedAt: now, sellerName: 'LG ELECTRONICS',
    );
    final c = compareOffers([a, b, offer('PLAZAVEA', 28900)], fresh);
    expect(c.comparableCount, 3);
    expect(c.storeCount, 2);
    expect(isThirdPartySeller(b), isTrue);
    final own = StoreOffer(
      id: 'x', storeCode: 'OECHSLE', storeName: 'Oechsle', title: 't', productUrl: 'https://x',
      priceCents: 1, availability: Availability.available, lastCheckedAt: now, sellerName: 'oechsle',
    );
    expect(isThirdPartySeller(own), isFalse);
  });

  testWidgets('la oferta de un tercero muestra el vendedor', (tester) async {
    final b = StoreOffer(
      id: 'OECHSLE__2', storeCode: 'OECHSLE', storeName: 'Oechsle', title: 't', productUrl: 'https://x',
      priceCents: 34900, availability: Availability.available, lastCheckedAt: now, sellerName: 'LG ELECTRONICS',
    );
    await pump(tester, OfferTile(offer: b, fresh: true, now: now));
    expect(find.text('Vendido por LG ELECTRONICS'), findsOneWidget);
  });
}
