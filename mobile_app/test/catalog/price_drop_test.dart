import 'package:compramejor/features/catalog/product_row.dart';
import 'package:compramejor/models/models.dart';
import 'package:compramejor/services/catalog_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.now().toUtc();

PriceSummary summary({Duration checkedAgo = const Duration(hours: 1), Duration? droppedAgo = const Duration(days: 1)}) =>
    PriceSummary(
      minPriceCents: 26900,
      minPriceStoreCode: 'COOLBOX',
      offerCount: 3,
      lastCheckedAt: now.subtract(checkedAgo),
      priceDropFromCents: droppedAgo == null ? null : 32900,
      priceDropPercent: droppedAgo == null ? null : 18,
      priceDroppedAt: droppedAgo == null ? null : now.subtract(droppedAgo),
    );

Future<void> pumpCard(WidgetTester tester, PriceSummary s) async {
  final p = Product(id: 'p', name: 'Monitor Teros', brand: 'Teros', categorySlug: 'monitores', summary: s);
  await tester.pumpWidget(ProviderScope(
    overrides: [storesProvider.overrideWith((ref) async => const <String, StoreInfo>{})],
    child: MaterialApp(home: Scaffold(body: SizedBox(width: 180, height: 286, child: ProductCard(product: p)))),
  ));
  await tester.pump();
}

void main() {
  test('la bajada se lee del resumen y vence a los 7 días', () {
    final s = PriceSummary.fromMap({
      'minPriceCents': 26900,
      'priceDropFromCents': 32900,
      'priceDropPercent': 18,
      'priceDroppedAt': null,
    });
    expect(s.priceDropPercent, 18);
    expect(s.hasRecentDrop(), isFalse); // sin fecha no se anuncia
    expect(summary().hasRecentDrop(), isTrue);
    expect(summary(droppedAgo: const Duration(days: 8)).hasRecentDrop(), isFalse);
    expect(summary(droppedAgo: null).hasRecentDrop(), isFalse);
  });

  testWidgets('la card muestra la bajada y el precio anterior', (tester) async {
    await pumpCard(tester, summary());
    expect(find.text('-18%'), findsOneWidget);
    expect(find.text('S/ 269.00'), findsOneWidget);
    expect(find.text('S/ 329.00'), findsOneWidget);
  });

  testWidgets('con precio por confirmar no se anuncia la bajada (RN-01)', (tester) async {
    await pumpCard(tester, summary(checkedAgo: const Duration(days: 3)));
    expect(find.text('-18%'), findsNothing);
    expect(find.text('Precio por confirmar'), findsOneWidget);
  });
}
