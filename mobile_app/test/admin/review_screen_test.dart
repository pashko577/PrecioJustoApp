import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compramejor/features/admin/review_repository.dart';
import 'package:compramejor/features/admin/review_screen.dart';
import 'package:compramejor/services/catalog_repository.dart';

Future<FakeFirebaseFirestore> pump(WidgetTester tester, {bool seed = true}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  final db = FakeFirebaseFirestore();
  if (seed) {
    await db.doc('products/ps5').set({
      'displayName': 'Consola PlayStation 5 Slim Digital', 'brand': 'Sony', 'status': 'ACTIVE',
      'categorySlug': 'consolas', 'summary': {'minPriceCents': 189900, 'offerCount': 2},
    });
    Map<String, Object?> listing(String title, int minutesAgo, {String? productId = 'ps5'}) => {
      'storeCode': 'OECHSLE', 'storeName': 'Oechsle', 'title': title, 'currentPriceCents': 179900,
      'productUrl': 'https://example.com/x', 'productId': productId, 'matchStatus': 'PENDING_REVIEW',
      'matchScore': 74, 'matchReason': 'nombre parecido',
      'createdAt': Timestamp.fromDate(DateTime.now().subtract(Duration(minutes: minutesAgo))),
    };
    await db.doc('storeProducts/OECHSLE__1').set(listing('PS5 Slim Digital 1TB', 1));
    await db.doc('storeProducts/OECHSLE__2').set(listing('PS5 Slim con lectora + juego', 2));
    await db.doc('storeProducts/OECHSLE__3').set(listing('Control DualSense', 3, productId: null));
    await db.doc('storeProducts/OECHSLE__4').set({...listing('Ya aprobado', 4), 'matchStatus': 'MATCHED_AUTO'});
  }
  await tester.pumpWidget(ProviderScope(
    overrides: [
      reviewRepositoryProvider.overrideWithValue(ReviewRepository(db, 'admin-1')),
      catalogRepositoryProvider.overrideWithValue(CatalogRepository(db)),
    ],
    child: const MaterialApp(home: ReviewScreen()),
  ));
  await tester.pumpAndSettle();
  return db;
}

void main() {
  testWidgets('muestra la publicación y el producto sugerido; aprobar guarda la decisión', (tester) async {
    final db = await pump(tester);
    expect(find.text('PS5 Slim Digital 1TB'), findsOneWidget);
    expect(find.text('Consola PlayStation 5 Slim Digital'), findsOneWidget);
    expect(find.text('Coincidencia 74 % · nombre parecido'), findsOneWidget);

    await tester.tap(find.byKey(const Key('review-approve')));
    await tester.pumpAndSettle();
    final approved = (await db.doc('storeProducts/OECHSLE__1').get()).data()!;
    expect(approved['matchStatus'], 'MATCHED_MANUAL');
    expect(approved['productId'], 'ps5');
    expect(approved['needsSummary'], isTrue); // el motor recalcula el precio
    expect(approved['reviewedBy'], 'admin-1');
    expect(find.text('PS5 Slim con lectora + juego'), findsOneWidget); // pasa a la siguiente
  });

  testWidgets('rechazar quita el producto sugerido; sin sugerencia no se puede aprobar', (tester) async {
    final db = await pump(tester);
    await tester.tap(find.byKey(const Key('review-skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-reject')));
    await tester.pumpAndSettle();
    final rejected = (await db.doc('storeProducts/OECHSLE__2').get()).data()!;
    expect(rejected['matchStatus'], 'REJECTED');
    expect(rejected['productId'], isNull);
    expect((await db.doc('storeProducts/OECHSLE__1').get())['matchStatus'], 'PENDING_REVIEW'); // saltada

    expect(find.text('Control DualSense'), findsOneWidget);
    expect(find.text('Sin producto sugerido'), findsOneWidget);
    final approve = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Sí, es el mismo'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(approve.onPressed, isNull);
    expect(find.byKey(const Key('review-counter')), findsOneWidget);
  });

  testWidgets('sin pendientes muestra el estado vacío', (tester) async {
    await pump(tester, seed: false);
    expect(find.text('Nada pendiente'), findsOneWidget);
  });
}
