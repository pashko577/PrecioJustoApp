import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_providers.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/profile_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/catalog/home_screen.dart';
import '../features/catalog/product_screen.dart';

/// Pantallas de acceso: si ya hay sesión, no tiene sentido mostrarlas.
const authPaths = {'/login', '/register', '/forgot-password'};

/// Rutas que exigen sesión. Favoritos y alertas se agregarán en el sprint 7.
const protectedPrefixes = ['/profile', '/favorites', '/alerts'];

/// Regla de redirección según la sesión. Devuelve `null` si no hay que redirigir.
String? authRedirect({required bool loggedIn, required Uri location}) {
  final path = location.path;
  final isProtected = protectedPrefixes.any((p) => path == p || path.startsWith('$p/'));

  if (!loggedIn && isProtected) {
    return Uri(path: '/login', queryParameters: {'from': location.toString()}).toString();
  }
  if (loggedIn && authPaths.contains(path)) {
    final from = location.queryParameters['from'];
    // Solo rutas internas (evita redirecciones abiertas a otros sitios).
    final safe = from != null && from.startsWith('/') && !from.startsWith('//');
    return safe ? from : '/';
  }
  return null;
}

/// Notifica al router cada vez que cambia la sesión.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<Object?> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final refresh = _AuthRefresh(auth.authStateChanges());
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) => authRedirect(loggedIn: auth.currentUser != null, location: state.uri),
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'product/:id',
            builder: (_, state) => ProductScreen(productId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, state) => ForgotPasswordScreen(initialEmail: state.uri.queryParameters['email']),
      ),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
