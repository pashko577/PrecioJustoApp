import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_providers.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/profile_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/sign_in_gate.dart';
import '../features/catalog/home_screen.dart';
import '../features/catalog/product_screen.dart';
import '../features/catalog/search_screen.dart';
import '../features/notifications/notifications.dart';
import '../features/tracking/tracking_screens.dart';
import '../features/admin/review_screen.dart';
import 'shell.dart';

/// Pantallas de acceso: si ya hay sesión, no tiene sentido mostrarlas.
const authPaths = {'/login', '/register', '/forgot-password'};

/// Rutas que exigen sesión: sin ella se redirige al login.
const protectedPrefixes = ['/notifications'];

/// Pestañas con sesión: la raíz es pública (muestra `SignInGate`, sin perder la barra de
/// navegación) y sus subrutas exigen sesión.
const gatedTabs = ['/profile', '/favorites', '/alerts'];

/// Regla de redirección según la sesión. Devuelve `null` si no hay que redirigir.
String? authRedirect({required bool loggedIn, required Uri location}) {
  final path = location.path;
  final isProtected =
      protectedPrefixes.any((p) => path == p || path.startsWith('$p/')) ||
      gatedTabs.any((p) => path.startsWith('$p/'));

  if (!loggedIn && isProtected) {
    return Uri(
      path: '/login',
      queryParameters: {'from': location.toString()},
    ).toString();
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

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final refresh = _AuthRefresh(auth.authStateChanges());
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    refreshListenable: refresh,
    redirect: (context, state) =>
        authRedirect(loggedIn: auth.currentUser != null, location: state.uri),
    routes: [
      // Pestañas principales con la barra de navegación flotante.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (_, state) => SearchScreen(
                  key: ValueKey(state.uri.toString()),
                  initialQuery: state.uri.queryParameters['q'] ?? '',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/favorites',
                builder: (_, _) => const SignInGate(
                  title: 'Guardados',
                  icon: Icons.favorite_border,
                  pitch:
                      'Guarda productos para seguir su precio y armar listas de compra.',
                  returnTo: '/favorites',
                  child: FavoritesScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'list/:id',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) =>
                        WishlistScreen(listId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/alerts',
                builder: (_, _) => const SignInGate(
                  title: 'Alertas',
                  icon: Icons.notifications_none,
                  pitch:
                      'Dinos a qué precio quieres comprar y te avisamos cuando alguna tienda lo baje.',
                  returnTo: '/alerts',
                  child: AlertsScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const SignInGate(
                  title: 'Perfil',
                  icon: Icons.person_outline,
                  pitch:
                      'Con tu cuenta, tus guardados y alertas te acompañan en cualquier celular.',
                  returnTo: '/profile',
                  child: ProfileScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
      // Pantallas completas (sin barra de navegación).
      GoRoute(
        path: '/product/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            ProductScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, state) => ForgotPasswordScreen(
          initialEmail: state.uri.queryParameters['email'],
        ),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/admin/review',
        builder: (_, _) => const ReviewScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
