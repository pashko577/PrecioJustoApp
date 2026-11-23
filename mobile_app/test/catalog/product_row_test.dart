import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:precio_justo/features/catalog/product_row.dart';
import 'package:precio_justo/models/models.dart';

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

Future<void> pump(WidgetTester tester, Product p) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: ProductRow(product: p))));

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
}
