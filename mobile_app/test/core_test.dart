import 'package:flutter_test/flutter_test.dart';
import 'package:precio_justo/core/money.dart';
import 'package:precio_justo/core/offer_rules.dart';
import 'package:precio_justo/models/models.dart';
import 'package:precio_justo/services/catalog_repository.dart';

void main() {
  group('formatCents', () {
    test('formatea soles con separador de miles', () {
      expect(formatCents(24990), 'S/ 249.90');
      expect(formatCents(124990), 'S/ 1,249.90');
      expect(formatCents(123456789), 'S/ 1,234,567.89');
      expect(formatCents(5), 'S/ 0.05');
      expect(formatCents(100000), 'S/ 1,000.00');
    });

    test('variación porcentual', () {
      expect(percentChange(10000, 9000), closeTo(-10, 0.001));
      expect(percentChange(0, 9000), 0);
    });
  });

  group('vigencia (RN-01)', () {
    final now = DateTime.utc(2026, 11, 22, 12);

    test('dentro del periodo es vigente', () {
      expect(isFresh(now.subtract(const Duration(hours: 11)), 720, now: now), isTrue);
    });

    test('fuera del periodo está desactualizada', () {
      expect(isFresh(now.subtract(const Duration(hours: 13)), 720, now: now), isFalse);
    });
  });

  group('ordenamiento de ofertas', () {
    final now = DateTime.utc(2026, 11, 22, 12);
    StoreOffer o(String store, int price, {Availability a = Availability.available, int hoursAgo = 1}) =>
        StoreOffer(
          id: '${store}__x',
          storeCode: store,
          storeName: store,
          title: 'x',
          productUrl: 'https://example.com',
          priceCents: price,
          availability: a,
          lastCheckedAt: now.subtract(Duration(hours: hoursAgo)),
        );

    test('una oferta vieja más barata no gana a una vigente', () {
      final sorted = sortOffers(
        [o('VIEJA', 100, hoursAgo: 48), o('CARA', 300), o('BARATA', 200), o('AGOTADA', 50, a: Availability.outOfStock)],
        (_) => 720,
        now: now,
      );
      expect(sorted.map((e) => e.storeCode), ['BARATA', 'CARA', 'AGOTADA', 'VIEJA']);
    });

    test('costo total solo con envío conocido (RN-03)', () {
      final base = o('A', 1000);
      expect(totalCostCents(base), isNull);
    });
  });

  test('withDescendants incluye subcategorías', () {
    const cats = [
      Category(slug: 'tecnologia', name: 'Tecnología'),
      Category(slug: 'computacion', name: 'Computación', parentSlug: 'tecnologia'),
      Category(slug: 'ssd', name: 'SSD', parentSlug: 'computacion'),
      Category(slug: 'monitores', name: 'Monitores', parentSlug: 'tecnologia'),
      Category(slug: 'moda', name: 'Moda'),
    ];
    expect(withDescendants('tecnologia', cats).toSet(), {'tecnologia', 'computacion', 'ssd', 'monitores'});
    expect(withDescendants('ssd', cats), ['ssd']);
  });
}
