import 'package:flutter_test/flutter_test.dart';
import 'package:compramejor/core/price_history.dart';
import 'package:compramejor/models/models.dart';

final now = DateTime.utc(2026, 11, 30, 12);

StoreOffer offer(String store) => StoreOffer(
      id: '${store}__1',
      storeCode: store,
      storeName: store,
      title: 't',
      productUrl: 'https://x',
      priceCents: 0,
      availability: Availability.available,
      lastCheckedAt: now,
    );

PricePoint p(int daysAgo, int cents, {Availability a = Availability.available}) =>
    PricePoint(at: now.subtract(Duration(days: daysAgo)), priceCents: cents, availability: a);

void main() {
  test('parseHistoryPoints ordena y descarta precios inválidos', () {
    final points = parseHistoryPoints([
      {'points': [{'t': 2, 'p': 200, 'a': 'AVAILABLE'}, {'t': 1, 'p': 100, 'a': 'OUT_OF_STOCK'}]},
      {'points': [{'t': 3, 'p': 0, 'a': 'AVAILABLE'}]},
    ], (v) => DateTime.utc(2026, 11, (v as int)));
    expect(points.map((e) => e.priceCents), [100, 200]);
    expect(points.first.isAvailable, isFalse);
  });

  test('monthsCovering cruza meses y años', () {
    expect(monthsCovering(DateTime.utc(2026, 1, 10), 30), ['2025-12', '2026-01']);
    expect(monthsCovering(DateTime.utc(2026, 11, 30), 90), ['2026-09', '2026-10', '2026-11']);
  });

  test('priceAt es escalonado y respeta la disponibilidad', () {
    final h = OfferHistory(offer: offer('A'), points: [p(10, 1000), p(5, 900, a: Availability.outOfStock), p(2, 800)]);
    expect(h.priceAt(now.subtract(const Duration(days: 11))), isNull); // antes del primer dato
    expect(h.priceAt(now.subtract(const Duration(days: 7))), 1000);
    expect(h.priceAt(now.subtract(const Duration(days: 3))), isNull); // agotado
    expect(h.priceAt(now), 800);
  });

  test('estadísticas sobre el mejor precio entre tiendas', () {
    final a = OfferHistory(offer: offer('A'), points: [p(20, 1000), p(10, 900)]);
    final b = OfferHistory(offer: offer('B'), points: [p(20, 1100), p(5, 850)]);
    final s = computeHistoryStats([a, b], now: now, days: 30);
    // Mejor precio: 1000 (20->10 días), 900 (10->5), 850 (5->ahora)
    expect(s.minCents, 850);
    expect(s.maxCents, 1000);
    expect(s.currentCents, 850);
    expect(s.currentIsLowest, isTrue);
    expect(s.changes, 2);
    // Promedio ponderado: (1000*10 + 900*5 + 850*5) / 20 = 937.5
    expect(s.averageCents, 938);
    expect(s.currentVsAveragePercent, closeTo(-9.3, 0.1));
    expect(s.firstObservation, now.subtract(const Duration(days: 20)));
    expect(s.isMeaningful, isTrue);
  });

  test('el periodo recorta puntos antiguos pero usa el precio vigente al inicio', () {
    final a = OfferHistory(offer: offer('A'), points: [p(60, 500), p(20, 1000)]);
    final s = computeHistoryStats([a], now: now, days: 30);
    // Al inicio del periodo (hace 30 días) regía 500; luego 1000.
    expect(s.minCents, 500);
    expect(s.maxCents, 1000);
    expect(s.currentCents, 1000);
    expect(s.currentIsLowest, isFalse);
  });

  test('historial recién iniciado no es significativo', () {
    final a = OfferHistory(offer: offer('A'), points: [PricePoint(
      at: now.subtract(const Duration(hours: 3)), priceCents: 100, availability: Availability.available)]);
    final s = computeHistoryStats([a], now: now, days: 30);
    expect(s.hasData, isTrue);
    expect(s.isMeaningful, isFalse);
  });

  test('sin datos', () {
    final s = computeHistoryStats([], now: now, days: 30);
    expect(s.hasData, isFalse);
    expect(s.currentCents, isNull);
  });

  test('el color sigue a la tienda y nunca se repite en un gráfico', () {
    final a = assignStoreColors(['PROMART', 'COOLBOX']);
    expect(a, {'PROMART': 3, 'COOLBOX': 0}); // fijos, sin importar el orden de llegada
    final b = assignStoreColors(['DEMO_B', 'COOLBOX', 'DEMO_A']);
    expect(b['COOLBOX'], 0);
    expect({b['DEMO_A'], b['DEMO_B']}, {1, 2}); // desconocidas: colores libres, distintos
    expect(b.values.toSet().length, 3);
  });
}
