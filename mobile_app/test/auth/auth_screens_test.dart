import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:compramejor/features/auth/auth_errors.dart';
import 'package:compramejor/features/auth/auth_providers.dart';
import 'package:compramejor/features/auth/auth_repository.dart';
import 'package:compramejor/features/auth/forgot_password_screen.dart';
import 'package:compramejor/features/auth/login_screen.dart';
import 'package:compramejor/features/auth/register_screen.dart';
import 'package:compramejor/models/user_profile.dart';

/// Implementación falsa para probar las pantallas sin Firebase.
class FakeAuthRepository implements AuthRepository {
  AuthFailure? failWith;
  final calls = <String>[];

  @override
  Stream<User?> authStateChanges() => const Stream.empty();
  @override
  User? get currentUser => null;

  Future<void> _record(String call) async {
    calls.add(call);
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> register({required String displayName, required String email, required String password}) =>
      _record('register:$displayName:$email');
  @override
  Future<void> signIn({required String email, required String password}) => _record('signIn:$email');
  @override
  Future<void> sendPasswordReset(String email) => _record('reset:$email');
  @override
  Future<void> signOut() => _record('signOut');
  @override
  Future<void> sendEmailVerification() => _record('verify');
  @override
  Future<void> reloadUser() async {}
  @override
  Stream<UserProfile?> profileChanges(String uid) => Stream.value(null);
  @override
  Future<void> updateDisplayName(String displayName) => _record('name:$displayName');
  @override
  Future<void> updateNotificationPrefs(NotificationPrefs prefs) => _record('prefs');
  @override
  Future<void> deleteAccount({required String password}) => _record('delete');
}

Future<FakeAuthRepository> pumpScreen(WidgetTester tester, Widget screen) async {
  // Pantalla de celular alta para que todo el formulario sea visible.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  final fake = FakeAuthRepository();
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => screen),
    GoRoute(path: '/register', builder: (_, _) => const Scaffold(body: Text('PANTALLA REGISTRO'))),
    GoRoute(path: '/login', builder: (_, _) => const Scaffold(body: Text('PANTALLA LOGIN'))),
    GoRoute(path: '/forgot-password', builder: (_, s) => ForgotPasswordScreen(initialEmail: s.uri.queryParameters['email'])),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('LoginScreen', () {
    testWidgets('valida campos vacíos sin llamar a Firebase', (tester) async {
      final fake = await pumpScreen(tester, const LoginScreen());
      await tester.tap(find.text('Ingresar'));
      await tester.pump();
      expect(find.text('Ingresa tu correo.'), findsOneWidget);
      expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
      expect(fake.calls, isEmpty);
    });

    testWidgets('envía credenciales válidas', (tester) async {
      final fake = await pumpScreen(tester, const LoginScreen());
      await tester.enterText(find.byKey(const Key('login-email')), 'ana@correo.pe');
      await tester.enterText(find.byKey(const Key('login-password')), 'precio2026');
      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle();
      expect(fake.calls, ['signIn:ana@correo.pe']);
    });

    testWidgets('muestra el error en español', (tester) async {
      final fake = await pumpScreen(tester, const LoginScreen());
      fake.failWith = const AuthFailure('Correo o contraseña incorrectos.');
      await tester.enterText(find.byKey(const Key('login-email')), 'ana@correo.pe');
      await tester.enterText(find.byKey(const Key('login-password')), 'mala');
      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle();
      expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
    });

    testWidgets('el botón se desactiva mientras espera', (tester) async {
      final completer = Completer<void>();
      final fake = await pumpScreen(tester, const LoginScreen());
      await tester.enterText(find.byKey(const Key('login-email')), 'ana@correo.pe');
      await tester.enterText(find.byKey(const Key('login-password')), 'precio2026');
      // Sustituye signIn por una operación lenta.
      fake.failWith = null;
      final slow = _SlowAuth(fake, completer.future);
      await tester.pumpWidget(ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(slow)],
        child: const MaterialApp(home: LoginScreen()),
      ));
      await tester.enterText(find.byKey(const Key('login-email')), 'ana@correo.pe');
      await tester.enterText(find.byKey(const Key('login-password')), 'precio2026');
      await tester.tap(find.text('Ingresar'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      completer.complete();
      await tester.pumpAndSettle();
      expect(find.text('Ingresar'), findsOneWidget);
    });

    testWidgets('"Crear cuenta" lleva al registro', (tester) async {
      await pumpScreen(tester, const LoginScreen());
      await tester.tap(find.text('Crear cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('PANTALLA REGISTRO'), findsOneWidget);
    });
  });

  group('RegisterScreen', () {
    Future<void> fill(WidgetTester tester, {String confirm = 'precio2026'}) async {
      await tester.enterText(find.byKey(const Key('register-name')), 'Ana');
      await tester.enterText(find.byKey(const Key('register-email')), 'ana@correo.pe');
      await tester.enterText(find.byKey(const Key('register-password')), 'precio2026');
      await tester.enterText(find.byKey(const Key('register-confirm')), confirm);
    }

    /// Toca la casilla (no el texto, que contiene el enlace a la política).
    Future<void> tapTerms(WidgetTester tester) async {
      await tester.tap(find.descendant(of: find.byKey(const Key('register-terms')), matching: find.byType(Checkbox)));
      await tester.pump();
    }

    testWidgets('el enlace muestra la política de privacidad', (tester) async {
      await pumpScreen(tester, const RegisterScreen());
      await tester.tap(find.byKey(const Key('register-terms')));
      await tester.pumpAndSettle();
      expect(find.text('Términos y privacidad'), findsOneWidget);
      expect(find.textContaining('fuera del Perú'), findsOneWidget);
    });

    Future<void> submit(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Crear cuenta').first);
      await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
      await tester.pumpAndSettle();
    }

    testWidgets('exige aceptar los términos', (tester) async {
      final fake = await pumpScreen(tester, const RegisterScreen());
      await fill(tester);
      await submit(tester);
      expect(find.text('Debes aceptar para continuar.'), findsOneWidget);
      expect(fake.calls, isEmpty);
    });

    testWidgets('detecta contraseñas distintas', (tester) async {
      final fake = await pumpScreen(tester, const RegisterScreen());
      await fill(tester, confirm: 'otra2026');
      await tapTerms(tester);
      await submit(tester);
      expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
      expect(fake.calls, isEmpty);
    });

    testWidgets('registra con datos válidos', (tester) async {
      final fake = await pumpScreen(tester, const RegisterScreen());
      await fill(tester);
      await tapTerms(tester);
      await submit(tester);
      expect(fake.calls, ['register:Ana:ana@correo.pe']);
    });
  });

  group('ForgotPasswordScreen', () {
    testWidgets('confirma el envío sin revelar si la cuenta existe', (tester) async {
      final fake = await pumpScreen(tester, const ForgotPasswordScreen(initialEmail: 'ana@correo.pe'));
      await tester.tap(find.text('Enviar enlace'));
      await tester.pumpAndSettle();
      expect(fake.calls, ['reset:ana@correo.pe']);
      expect(find.text('Revisa tu correo'), findsOneWidget);
      expect(find.textContaining('Si existe una cuenta'), findsOneWidget);
    });
  });
}

/// Repositorio cuyo signIn tarda hasta que se completa [_wait].
class _SlowAuth extends FakeAuthRepository {
  _SlowAuth(this._inner, this._wait);

  final FakeAuthRepository _inner;
  final Future<void> _wait;

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _wait;
    await _inner.signIn(email: email, password: password);
  }
}
