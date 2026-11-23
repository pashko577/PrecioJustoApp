import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compramejor/features/auth/auth_errors.dart';
import 'package:compramejor/features/auth/auth_repository.dart';
import 'package:compramejor/models/user_profile.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  test('registro crea el perfil con plan FREE y preferencias por defecto', () async {
    final auth = MockFirebaseAuth();
    final repo = FirebaseAuthRepository(auth, db);

    await repo.register(displayName: '  Ana Pérez ', email: ' ana@correo.pe ', password: 'precio2026');

    final uid = auth.currentUser!.uid;
    final doc = await db.collection('users').doc(uid).get();
    expect(doc.exists, isTrue);
    expect(doc['displayName'], 'Ana Pérez');
    expect(doc['email'], 'ana@correo.pe');
    expect(doc['plan'], 'FREE');
    expect(doc['status'], 'ACTIVE');
    expect(doc['notificationPrefs'], const NotificationPrefs().toMap());
  });

  test('inicio de sesión crea el perfil si faltaba', () async {
    final user = MockUser(uid: 'u1', email: 'luis@correo.pe', displayName: 'Luis');
    final repo = FirebaseAuthRepository(MockFirebaseAuth(mockUser: user), db);

    await repo.signIn(email: 'luis@correo.pe', password: 'cualquiera1');

    final doc = await db.collection('users').doc('u1').get();
    expect(doc['displayName'], 'Luis');
    expect(doc['plan'], 'FREE');
  });

  test('inicio de sesión no sobrescribe un perfil existente', () async {
    await db.collection('users').doc('u1').set({'displayName': 'Nombre propio', 'plan': 'PREMIUM'});
    final user = MockUser(uid: 'u1', email: 'luis@correo.pe', displayName: 'Luis');
    final repo = FirebaseAuthRepository(MockFirebaseAuth(mockUser: user), db);

    await repo.signIn(email: 'luis@correo.pe', password: 'cualquiera1');

    final doc = await db.collection('users').doc('u1').get();
    expect(doc['displayName'], 'Nombre propio');
    expect(doc['plan'], 'PREMIUM');
  });

  test('profileChanges emite el perfil', () async {
    await db.collection('users').doc('u1').set({'email': 'a@b.pe', 'displayName': 'Ana', 'plan': 'FREE'});
    final repo = FirebaseAuthRepository(MockFirebaseAuth(), db);

    final profile = await repo.profileChanges('u1').first;
    expect(profile!.displayName, 'Ana');
    expect(profile.isPremium, isFalse);
  });

  test('actualizar nombre y preferencias', () async {
    final user = MockUser(uid: 'u1', email: 'ana@correo.pe', displayName: 'Ana');
    final repo = FirebaseAuthRepository(MockFirebaseAuth(mockUser: user, signedIn: true), db);
    await db.collection('users').doc('u1').set({'displayName': 'Ana', 'plan': 'FREE'});

    await repo.updateDisplayName(' Ana María ');
    await repo.updateNotificationPrefs(const NotificationPrefs(weeklySummary: true));

    final doc = await db.collection('users').doc('u1').get();
    expect(doc['displayName'], 'Ana María');
    expect(doc['notificationPrefs']['weeklySummary'], isTrue);
  });

  test('sin sesión, las acciones de perfil fallan con mensaje claro', () async {
    final repo = FirebaseAuthRepository(MockFirebaseAuth(), db);
    expect(
      () => repo.updateDisplayName('X'),
      throwsA(isA<AuthFailure>().having((e) => e.message, 'message', contains('sesión'))),
    );
  });

  test('eliminar cuenta borra el perfil y todas sus subcolecciones', () async {
    final user = MockUser(uid: 'u1', email: 'ana@correo.pe');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final repo = FirebaseAuthRepository(auth, db);
    final userDoc = db.collection('users').doc('u1');
    await userDoc.set({'displayName': 'Ana', 'plan': 'FREE'});
    for (final sub in userSubcollections) {
      await userDoc.collection(sub).doc('x').set({'a': 1});
    }
    // Datos de otro usuario: no deben tocarse.
    await db.collection('users').doc('u2').set({'displayName': 'Otro'});

    await repo.deleteAccount(password: 'precio2026');

    expect((await userDoc.get()).exists, isFalse);
    for (final sub in userSubcollections) {
      expect((await userDoc.collection(sub).get()).docs, isEmpty, reason: sub);
    }
    expect((await db.collection('users').doc('u2').get()).exists, isTrue);
  });
}
