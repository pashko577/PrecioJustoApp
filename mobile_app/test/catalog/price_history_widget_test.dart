import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:precio_justo/core/price_history.dart';
import 'package:precio_justo/features/history/price_history_section.dart';
import 'package:precio_justo/models/models.dart';
import 'package:precio_justo/services/catalog_repository.dart';

final now = DateTime.now().toUtc();

StoreOffer offer(String code, String name) => StoreOffer(
      id: '${code}__1', storeCode: code, storeName: name, title: 't', productUrl: 'https://x',
      priceCents: 0, availability: Availability.available, lastCheckedAt: now,
    );

PricePoint p(int daysAgo, int cents, {Availability a = Availability.available}) =>
    PricePoint(at: now.subtract(Duration(days: daysAgo)), priceCents: cents, availability: a);

Future<void> pump(WidgetTester tester, List<OfferHistory> histories) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [historyProvider.overrideWith((ref, key) async => histories)],
    child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PriceHistorySection(productId: 'p')))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('seriesSpots: escalonado, corte por falta de stock y extensión hasta hoy', () {
    final from = now.subtract(const Duration(days: 30));
    final h = OfferHistory(offer: offer('A', 'A'), points: [
      p(20, 1000), p(10, 900, a: Availability.outOfStock), p(5, 800),
    ]);
    final spots = seriesSpots(h, from, now);
    expect(spots.where((s) => s == FlSpot.nullSpot).length, 1);
    expect(spots.first.y, 10.0);
    expect(spots.last.y, 8.0);
    expect(spots.last.x, closeTo(30 * 24, 0.1));
  });

  testWidgets('historial con datos: cifras, gráfico, leyenda y tabla', (tester) async {
    await pump(tester, [
      OfferHistory(offer: offer('COOLBOX', 'Coolbox'), points: [p(20, 100000), p(3, 90000)]),
      OfferHistory(offer: offer('PLAZAVEA', 'Plaza Vea'), points: [p(20, 105000)]),
    ]);
    expect(find.text('Historial de precios'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Mejor precio hoy'), findsOneWidget);
    expect(find.text('S/ 900.00'), findsWidgets); // mejor precio actual y mínimo
    expect(find.text('Es el precio más bajo observado en los últimos 30 días.'), findsOneWidget);
    expect(find.textContaining('Coolbox · S/ 900.00'), findsOneWidget); // leyenda
    expect(find.textContaining('Ver datos del gráfico (3)'), findsOneWidget);
  });

  testWidgets('historial recién iniciado muestra aviso en lugar del gráfico', (tester) async {
    await pump(tester, [
      OfferHistory(offer: offer('COOLBOX', 'Coolbox'), points: [
        PricePoint(at: now.subtract(const Duration(hours: 2)), priceCents: 50000, availability: Availability.available),
      ]),
    ]);
    expect(find.byType(LineChart), findsNothing);
    expect(find.textContaining('Empezamos a registrar este producto'), findsOneWidget);
  });

  testWidgets('sin observaciones', (tester) async {
    await pump(tester, []);
    expect(find.textContaining('Todavía no hay observaciones'), findsOneWidget);
  });

  test('cada tienda conserva su color y no se repiten', () {
    final c = colorsForStores(['COOLBOX', 'PLAZAVEA', 'DEMO_STORE', 'DEMO_STORE_B']);
    expect(c['COOLBOX'], seriesColors[0]);
    expect(c['PLAZAVEA'], seriesColors[1]);
    expect(c.values.toSet().length, 4);
  });
}
