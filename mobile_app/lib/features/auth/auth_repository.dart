import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/user_profile.dart';
import 'auth_errors.dart';

/// Contrato de autenticación. Las pantallas dependen de esta interfaz,
/// no de Firebase directamente (así se pueden probar con implementaciones falsas).
///
/// Todos los métodos lanzan [AuthFailure] con un mensaje en español.
abstract class AuthRepository {
  Stream<User?> authStateChanges();
  User? get currentUser;

  Future<void> register({required String displayName, required String email, required String password});
  Future<void> signIn({required String email, required String password});
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
  Future<void> sendEmailVerification();

  /// Recarga el usuario (por ejemplo, para saber si ya verificó su correo).
  Future<void> reloadUser();

  Stream<UserProfile?> profileChanges(String uid);
  Future<void> updateDisplayName(String displayName);
  Future<void> updateNotificationPrefs(NotificationPrefs prefs);

  /// Elimina los datos del usuario y su cuenta. Pide la contraseña para reautenticar.
  Future<void> deleteAccount({required String password});
}

/// Subcolecciones de `users/{uid}` que se borran al eliminar la cuenta.
const userSubcollections = ['favorites', 'wishlists', 'alerts', 'devices', 'notifications'];

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) => _db.collection('users').doc(uid);

  @override
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Future<void> register({required String displayName, required String email, required String password}) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
      final user = credential.user!;
      final name = displayName.trim();
      await user.updateDisplayName(name);
      await _createProfile(user.uid, email: user.email ?? email.trim(), displayName: name);
      // No bloquea el registro si falla el envío del correo de verificación.
      await user.sendEmailVerification().catchError((_) {});
    } catch (e) {
      throw mapAuthError(e);
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      await _ensureProfile(credential.user!);
    } catch (e) {
      throw mapAuthError(e);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      // No revelar si el correo existe o no (evita enumerar cuentas).
      if (e.code == 'user-not-found') return;
      throw mapAuthError(e);
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
    } catch (e) {
      throw mapAuthError(e);
    }
  }

  @override
  Future<void> reloadUser() async => _auth.currentUser?.reload();

  @override
  Stream<UserProfile?> profileChanges(String uid) =>
      _userDoc(uid).snapshots().map((doc) => doc.exists ? UserProfile.fromDoc(doc) : null);

  @override
  Future<void> updateDisplayName(String displayName) async {
    final user = _requireUser();
    final name = displayName.trim();
    try {
      await user.updateDisplayName(name);
      await _userDoc(user.uid).update({'displayName': name, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      throw mapAuthError(e);
    }
  }

  @override
  Future<void> updateNotificationPrefs(NotificationPrefs prefs) async {
    final user = _requireUser();
    await _userDoc(user.uid).update({'notificationPrefs': prefs.toMap(), 'updatedAt': FieldValue.serverTimestamp()});
  }

  @override
  Future<void> deleteAccount({required String password}) async {
    final user = _requireUser();
    try {
      final email = user.email;
      if (email == null) throw const AuthFailure('La cuenta no tiene correo asociado.');
      await user.reauthenticateWithCredential(EmailAuthProvider.credential(email: email, password: password));

      // 1) Borrar datos en Firestore (Ley 29733: derecho de cancelación).
      for (final name in userSubcollections) {
        final snap = await _userDoc(user.uid).collection(name).get();
        for (final doc in snap.docs) {
          await doc.reference.delete();
        }
      }
      await _userDoc(user.uid).delete();

      // 2) Borrar la cuenta de autenticación.
      await user.delete();
    } catch (e) {
      throw mapAuthError(e);
    }
  }

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailure('Tu sesión expiró. Inicia sesión nuevamente.');
    return user;
  }

  Future<void> _createProfile(String uid, {required String email, required String displayName}) =>
      _userDoc(uid).set({
        'email': email,
        'displayName': displayName,
        'plan': 'FREE',
        'notificationPrefs': const NotificationPrefs().toMap(),
        'status': 'ACTIVE',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Si el perfil no existe (por ejemplo, falló la creación durante el registro), lo crea.
  Future<void> _ensureProfile(User user) async {
    final doc = await _userDoc(user.uid).get();
    if (!doc.exists) {
      await _createProfile(
        user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? (user.email ?? '').split('@').first,
      );
    }
  }
}
