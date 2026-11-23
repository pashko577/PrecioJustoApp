import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:precio_justo/features/tracking/tracking_screens.dart';
import 'package:precio_justo/models/tracking.dart';
import 'package:precio_justo/services/tracking_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late TrackingRepository repo;

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('config').doc('app').set({
      'freePlanLimits': {'favorites': 2, 'alerts': 2, 'wishlists': 1},
    });
    repo = TrackingRepository(db, 'ana');
  });

  group('favoritos', () {
    test('agregar guarda el precio del momento y no duplica', () async {
      await repo.addFavorite(productId: 'p1', productName: 'Kingston NV3', currentBestCents: 24990);
      await repo.addFavorite(productId: 'p1', productName: 'Kingston NV3', currentBestCents: 1);
      final favs = await repo.favorites().first;
      expect(favs.map((f) => f.productId), ['p1']);
      expect(favs.single.priceAtSaveCents, 24990);
      final doc = await db.doc('users/ana/favorites/p1').get();
      expect(doc['productId'], 'p1'); // exigido por las reglas
    });

    test('respeta el límite del plan gratuito', () async {
      await repo.addFavorite(productId: 'p1', productName: 'a');
      await repo.addFavorite(productId: 'p2', productName: 'b');
      expect(
        () => repo.addFavorite(productId: 'p3', productName: 'c'),
        throwsA(isA<TrackingFailure>().having((e) => e.message, 'message', contains('límite de 2 favoritos'))),
      );
    });

    test('premium no tiene el límite gratuito', () async {
      final premium = TrackingRepository(db, 'ana', isPremium: true);
      for (var i = 0; i < 5; i++) {
        await premium.addFavorite(productId: 'p$i', productName: 'x');
      }
      expect((await premium.favorites().first).length, 5);
    });

    test('quitar', () async {
      await repo.addFavorite(productId: 'p1', productName: 'a');
      await repo.removeFavorite('p1');
      expect(await repo.favorites().first, isEmpty);
    });
  });

  group('listas', () {
    test('crear, agregar sin duplicar, quitar y renombrar', () async {
      final id = await repo.createWishlist('  Cocina nueva ');
      await repo.addToWishlist(id, 'p1');
      await repo.addToWishlist(id, 'p1');
      await repo.addToWishlist(id, 'p2');
      var list = (await repo.wishlist(id).first)!;
      expect(list.name, 'Cocina nueva');
      expect(list.productIds, ['p1', 'p2']);
      await repo.removeFromWishlist(id, 'p1');
      await repo.renameWishlist(id, 'Cocina');
      list = (await repo.wishlist(id).first)!;
      expect(list.name, 'Cocina');
      expect(list.productIds, ['p2']);
    });

    test('límite de listas y nombre obligatorio', () async {
      await repo.createWishlist('Una');
      expect(() => repo.createWishlist('Otra'), throwsA(isA<TrackingFailure>()));
      expect(() => repo.createWishlist('   '), throwsA(isA<TrackingFailure>()));
    });
  });

  group('alertas', () {
    test('una alerta por producto; editar actualiza y reactiva', () async {
      await repo.saveAlert(productId: 'p1', productName: 'NV3', targetPriceCents: 20000);
      final first = (await repo.alerts().first).single;
      // El motor la marcó como cumplida (sprint 8).
      await db.doc('users/ana/alerts/${first.id}').update({'status': 'TRIGGERED', 'lastTriggeredPriceCents': 19900});

      await repo.saveAlert(productId: 'p1', productName: 'NV3', targetPriceCents: 18000);
      final alerts = await repo.alerts().first;
      expect(alerts.length, 1);
      expect(alerts.single.targetPriceCents, 18000);
      expect(alerts.single.status, AlertStatus.active);
      expect(alerts.single.lastTriggeredPriceCents, isNull); // puede volver a avisar (RN-08)
      final doc = await db.doc('users/ana/alerts/${first.id}').get();
      expect((doc['currency'], doc['condition']), ('PEN', 'AT_OR_BELOW')); // exigidos por las reglas
    });

    test('pausar y reanudar', () async {
      await repo.saveAlert(productId: 'p1', productName: 'NV3', targetPriceCents: 20000);
      final alert = (await repo.alerts().first).single;
      await repo.setAlertPaused(alert, true);
      expect((await repo.alerts().first).single.status, AlertStatus.paused);
      await repo.setAlertPaused(alert, false);
      expect((await repo.alerts().first).single.status, AlertStatus.active);
    });

    test('límite de alertas y precio inválido', () async {
      await repo.saveAlert(productId: 'p1', productName: 'a', targetPriceCents: 100);
      await repo.saveAlert(productId: 'p2', productName: 'b', targetPriceCents: 100);
      expect(() => repo.saveAlert(productId: 'p3', productName: 'c', targetPriceCents: 100),
          throwsA(isA<TrackingFailure>()));
      expect(() => repo.saveAlert(productId: 'p1', productName: 'a', targetPriceCents: 0),
          throwsA(isA<TrackingFailure>()));
    });
  });

  test('texto de cambio de precio desde que se guardó', () {
    expect(priceChangeText(30000, 27500), 'Bajó S/ 25.00 desde que lo guardaste');
    expect(priceChangeText(30000, 31000), 'Subió S/ 10.00 desde que lo guardaste');
    expect(priceChangeText(30000, 30000), isNull);
    expect(priceChangeText(null, 30000), isNull);
  });
}
