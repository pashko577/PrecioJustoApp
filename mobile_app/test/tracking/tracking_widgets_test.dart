import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:compramejor/features/tracking/tracking_actions.dart';
import 'package:compramejor/features/tracking/tracking_screens.dart';
import 'package:compramejor/models/models.dart';
import 'package:compramejor/services/catalog_repository.dart';
import 'package:compramejor/services/tracking_repository.dart';

const product = Product(id: 'p1', name: 'Kingston NV3 1TB', brand: 'Kingston', categorySlug: 'ssd');

Future<FakeFirebaseFirestore> pump(WidgetTester tester, {required bool signedIn, Widget? home}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  final db = FakeFirebaseFirestore();
  await db.collection('config').doc('app').set({'freePlanLimits': {'favorites': 50, 'alerts': 5, 'wishlists': 3}});
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(
        body: home ?? const TrackingActions(product: product, currentBestCents: 24990),
      ),
    ),
    GoRoute(path: '/login', builder: (_, state) => Scaffold(body: Text('LOGIN ${state.uri.queryParameters['from']}'))),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      trackingRepositoryProvider.overrideWithValue(signedIn ? TrackingRepository(db, 'ana') : null),
      catalogRepositoryProvider.overrideWithValue(CatalogRepository(db)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return db;
}

void main() {
  testWidgets('un visitante es llevado al login y vuelve al producto', (tester) async {
    await pump(tester, signedIn: false);
    await tester.tap(find.byKey(const Key('favorite-button')));
    await tester.pumpAndSettle();
    expect(find.text('LOGIN /product/p1'), findsOneWidget);
  });

  testWidgets('guardar en favoritos cambia el botón', (tester) async {
    final db = await pump(tester, signedIn: true);
    expect(find.text('Guardar'), findsOneWidget);
    await tester.tap(find.byKey(const Key('favorite-button')));
    await tester.pumpAndSettle();
    expect(find.text('Guardado'), findsOneWidget);
    expect((await db.doc('users/ana/favorites/p1').get())['priceAtSaveCents'], 24990);
  });

  testWidgets('alerta: sugiere 5 % menos, valida y guarda', (tester) async {
    final db = await pump(tester, signedIn: true);
    await tester.tap(find.byKey(const Key('alert-button')));
    await tester.pumpAndSettle();
    expect(find.text('Mejor precio actual: S/ 249.90'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '237'), findsOneWidget); // 249.90 * 0.95 = 237.40 -> S/ 237

    await tester.enterText(find.byKey(const Key('alert-price')), 'abc');
    await tester.tap(find.byKey(const Key('alert-save')));
    await tester.pump();
    expect(find.text('Ingresa un precio válido.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('alert-price')), '230,50');
    await tester.tap(find.byKey(const Key('alert-save')));
    await tester.pumpAndSettle();
    final alerts = await db.collection('users/ana/alerts').get();
    expect(alerts.docs.single['targetPriceCents'], 23050);
    expect(find.text('Alerta: S/ 230.50'), findsOneWidget);
  });

  testWidgets('pantalla de alertas muestra "¡Ya cumple!" cuando el precio llega al objetivo', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.doc('products/p1').set({
      'displayName': 'Kingston NV3 1TB',
      'status': 'ACTIVE',
      'summary': {'minPriceCents': 22000, 'minPriceStoreCode': 'COOLBOX', 'lastCheckedAt': DateTime.now()},
    });
    await db.doc('stores/COOLBOX').set({'name': 'Coolbox', 'freshnessMinutes': 720});
    final repo = TrackingRepository(db, 'ana');
    await db.doc('config/app').set({'freePlanLimits': {'alerts': 5}});
    await repo.saveAlert(productId: 'p1', productName: 'Kingston NV3 1TB', targetPriceCents: 23050);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        trackingRepositoryProvider.overrideWithValue(repo),
        catalogRepositoryProvider.overrideWithValue(CatalogRepository(db)),
      ],
      child: const MaterialApp(home: AlertsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Avisar si baja a S/ 230.50 o menos'), findsOneWidget);
    expect(find.text('Mejor precio actual: S/ 220.00'), findsOneWidget);
    expect(find.byKey(const Key('alert-met')), findsOneWidget);
  });
}
