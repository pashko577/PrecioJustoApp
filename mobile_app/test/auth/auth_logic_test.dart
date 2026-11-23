import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:precio_justo/app/router.dart';
import 'package:precio_justo/features/auth/auth_errors.dart';
import 'package:precio_justo/features/auth/validators.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('ana'), isNotNull);
      expect(Validators.email('ana@correo'), isNotNull);
      expect(Validators.email(' ana@correo.pe '), isNull);
    });

    test('password exige 8 caracteres con letras y números', () {
      expect(Validators.password('abc123'), contains('8'));
      expect(Validators.password('abcdefgh'), contains('número'));
      expect(Validators.password('12345678'), contains('letra'));
      expect(Validators.password('precio2026'), isNull);
    });

    test('loginPassword solo exige que no esté vacía', () {
      expect(Validators.loginPassword(''), isNotNull);
      expect(Validators.loginPassword('x'), isNull);
    });

    test('confirmPassword compara con la original', () {
      final v = Validators.confirmPassword(() => 'precio2026');
      expect(v('otra'), isNotNull);
      expect(v('precio2026'), isNull);
    });

    test('displayName', () {
      expect(Validators.displayName(' '), isNotNull);
      expect(Validators.displayName('A'), isNotNull);
      expect(Validators.displayName('A' * 81), isNotNull);
      expect(Validators.displayName('Ana'), isNull);
    });
  });

  group('mapAuthError', () {
    String msg(String code) => mapAuthError(FirebaseAuthException(code: code)).message;

    test('no revela si falló el correo o la contraseña', () {
      expect(msg('user-not-found'), msg('wrong-password'));
      expect(msg('invalid-credential'), 'Correo o contraseña incorrectos.');
    });

    test('mensajes en español', () {
      expect(msg('email-already-in-use'), contains('ya está registrado'));
      expect(msg('too-many-requests'), contains('Demasiados intentos'));
      expect(msg('network-request-failed'), contains('Sin conexión'));
    });

    test('código desconocido incluye el código para soporte', () {
      expect(msg('algo-raro'), contains('algo-raro'));
    });

    test('AuthFailure pasa sin cambios', () {
      const f = AuthFailure('x');
      expect(mapAuthError(f), same(f));
    });
  });

  group('authRedirect', () {
    String? go(String location, {required bool loggedIn}) =>
        authRedirect(loggedIn: loggedIn, location: Uri.parse(location));

    test('visitante puede ver catálogo y productos', () {
      expect(go('/', loggedIn: false), isNull);
      expect(go('/product/abc', loggedIn: false), isNull);
      expect(go('/login', loggedIn: false), isNull);
    });

    test('visitante en ruta protegida va al login recordando el destino', () {
      expect(go('/profile', loggedIn: false), '/login?from=%2Fprofile');
      expect(go('/alerts/123', loggedIn: false), '/login?from=%2Falerts%2F123');
    });

    test('con sesión, el login redirige al destino original', () {
      expect(go('/login?from=%2Fprofile', loggedIn: true), '/profile');
      expect(go('/register', loggedIn: true), '/');
    });

    test('no permite redirecciones a otros sitios', () {
      expect(go('/login?from=https://malo.com', loggedIn: true), '/');
      expect(go('/login?from=//malo.com', loggedIn: true), '/');
    });

    test('"/profilexyz" no se confunde con "/profile"', () {
      expect(go('/profilexyz', loggedIn: false), isNull);
    });
  });
}
