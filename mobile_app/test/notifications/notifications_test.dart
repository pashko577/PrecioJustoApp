import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:compramejor/features/notifications/notifications.dart';
import 'package:compramejor/services/push_service.dart';

Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  final col = db.collection('users/ana/notifications');
  await col.doc('n1').set({
    'type': 'PRICE_ALERT', 'title': '¡Bajó de precio!',
    'message': 'Kingston NV3 1TB está a S/ 229.00 en Coolbox (tu alerta: S/ 230.50).',
    'payload': {'productId': 'kingston-nv3-1tb'}, 'readAt': null,
    'createdAt': DateTime.now().subtract(const Duration(minutes: 5)),
  });
  await col.doc('n2').set({
    'type': 'PRICE_ALERT', 'title': 'Antigua', 'message': 'ya leída', 'payload': {},
    'readAt': DateTime.now(), 'createdAt': DateTime.now().subtract(const Duration(days: 2)),
  });
  return db;
}

Widget app(FakeFirebaseFirestore db) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => Scaffold(appBar: AppBar(actions: const [NotificationsBell()]))),
    GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
    GoRoute(path: '/product/:id', builder: (_, s) => Scaffold(body: Text('PRODUCTO ${s.pathParameters['id']}'))),
    GoRoute(path: '/alerts', builder: (_, _) => const Scaffold(body: Text('ALERTAS'))),
  ]);
  return ProviderScope(
    overrides: [notificationsRepositoryProvider.overrideWithValue(NotificationsRepository(db, 'ana'))],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  test('el push no se activa en pruebas/emuladores', () {
    expect(pushSupported, isFalse);
  });

  testWidgets('la campana muestra las no leídas', (tester) async {
    await tester.pumpWidget(app(await seed()));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.byTooltip('Notificaciones: 1 sin leer'), findsOneWidget);
  });

  testWidgets('abrir una notificación la marca leída y lleva al producto', (tester) async {
    final db = await seed();
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notifications-nav')));
    await tester.pumpAndSettle();
    expect(find.text('¡Bajó de precio!'), findsOneWidget);
    expect(find.textContaining('hace 5 min'), findsOneWidget);

    await tester.tap(find.text('¡Bajó de precio!'));
    await tester.pumpAndSettle();
    expect(find.text('PRODUCTO kingston-nv3-1tb'), findsOneWidget);
    expect((await db.doc('users/ana/notifications/n1').get())['readAt'], isNotNull);
  });

  testWidgets('marcar todo como leído', (tester) async {
    final db = await seed();
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notifications-nav')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcar todo leído'));
    await tester.pumpAndSettle();
    expect(find.text('Marcar todo leído'), findsNothing);
    expect((await db.doc('users/ana/notifications/n1').get())['readAt'], isNotNull);
  });

  testWidgets('bandeja vacía invita a crear alertas', (tester) async {
    await tester.pumpWidget(app(FakeFirebaseFirestore()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notifications-nav')));
    await tester.pumpAndSettle();
    expect(find.text('Sin notificaciones'), findsOneWidget);
    await tester.tap(find.text('Ver mis alertas'));
    await tester.pumpAndSettle();
    expect(find.text('ALERTAS'), findsOneWidget);
  });
}
