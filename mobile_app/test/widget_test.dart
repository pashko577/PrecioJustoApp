import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compramejor/features/offers/offer_tile.dart';
import 'package:compramejor/models/models.dart';

final now = DateTime.utc(2026, 11, 22, 22);

StoreOffer offer({int? shipping, Availability availability = Availability.available, int? previous}) =>
    StoreOffer(
      id: 'DEMO_STORE__KNV3-1TB',
      storeCode: 'DEMO_STORE',
      storeName: 'Tienda Demo',
      title: 'Kingston NV3 1TB',
      productUrl: 'https://demo.example.com/p/KNV3-1TB',
      priceCents: 24990,
      previousPriceCents: previous,
      shippingCents: shipping,
      availability: availability,
      lastCheckedAt: now.subtract(const Duration(hours: 2)),
    );

Future<void> pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))));

void main() {
  testWidgets('oferta vigente muestra precio y verificación', (tester) async {
    await pump(tester, OfferTile(offer: offer(shipping: 1000), fresh: true, isBest: true, now: now));
    expect(find.text('S/ 249.90'), findsOneWidget);
    expect(find.text('Mejor precio'), findsOneWidget);
    expect(find.text('Verificado hace 2 h'), findsOneWidget);
    expect(find.text('Envío S/ 10.00'), findsOneWidget);
    expect(find.text('Total S/ 259.90'), findsOneWidget);
  });

  testWidgets('envío desconocido no se suma como cero (RN-03)', (tester) async {
    await pump(tester, OfferTile(offer: offer(), fresh: true, now: now));
    expect(find.text('Envío no informado'), findsOneWidget);
    expect(find.textContaining('Total'), findsNothing);
  });

  testWidgets('oferta desactualizada se identifica como tal (RF-04)', (tester) async {
    await pump(tester, OfferTile(offer: offer(), fresh: false, now: now));
    expect(find.textContaining('Desactualizado'), findsOneWidget);
    expect(find.textContaining('Verificado'), findsNothing);
  });

  testWidgets('muestra precio anterior cuando bajó', (tester) async {
    await pump(tester, OfferTile(offer: offer(previous: 26990), fresh: true, now: now));
    expect(find.text('antes S/ 269.90'), findsOneWidget);
  });

  testWidgets('agotado se muestra como agotado', (tester) async {
    await pump(tester, OfferTile(offer: offer(availability: Availability.outOfStock), fresh: true, now: now));
    expect(find.text('Agotado'), findsOneWidget);
  });
}
