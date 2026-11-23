import 'package:flutter_test/flutter_test.dart';
import 'package:precio_justo/core/money.dart';
import 'package:precio_justo/models/tracking.dart';

void main() {
  test('parseSolesToCents', () {
    expect(parseSolesToCents('1199'), 119900);
    expect(parseSolesToCents('1199.9'), 119990);
    expect(parseSolesToCents('1,199.90'), 119990);
    expect(parseSolesToCents('S/ 999,5'), 99950);
    expect(parseSolesToCents('S/. 1.199,90'), 119990);
    expect(parseSolesToCents('1,199'), 119900); // coma de miles
    expect(parseSolesToCents('0'), isNull);
    expect(parseSolesToCents(''), isNull);
    expect(parseSolesToCents('abc'), isNull);
    expect(parseSolesToCents('-5'), isNull);
  });

  test('precio objetivo sugerido: 5 % menos, en soles enteros', () {
    expect(suggestedTargetCents(124990), 118700);
    expect(suggestedTargetCents(100000), 95000);
  });

  test('alerta cumplida', () {
    const a = PriceAlert(id: 'a', productId: 'p', productName: 'x', targetPriceCents: 100000);
    expect(a.isMetBy(99900), isTrue);
    expect(a.isMetBy(100000), isTrue);
    expect(a.isMetBy(100100), isFalse);
    expect(a.isMetBy(null), isFalse);
  });

  test('límites del plan desde config', () {
    final l = PlanLimits.fromConfig({'freePlanLimits': {'favorites': 10, 'alerts': 2}});
    expect((l.favorites, l.alerts, l.wishlists), (10, 2, 3));
    expect(PlanLimits.fromConfig(null).alerts, 5);
  });
}
