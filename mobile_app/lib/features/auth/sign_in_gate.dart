import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../ui/common.dart';
import 'auth_providers.dart';

/// Pestaña que necesita sesión: sin sesión invita a ingresar sin sacar al usuario de la
/// navegación principal; con sesión muestra [child].
class SignInGate extends ConsumerWidget {
  const SignInGate({
    super.key,
    required this.title,
    required this.icon,
    required this.pitch,
    required this.returnTo,
    required this.child,
  });

  final String title;
  final IconData icon;

  /// Qué gana el usuario al ingresar en esta pestaña.
  final String pitch;

  /// Ruta a la que se vuelve después de ingresar.
  final String returnTo;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (auth.value != null) return child;

    String withReturn(String path) => Uri(path: path, queryParameters: {'from': returnTo}).toString();
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: Text(title)),
      body: EmptyState(
        icon: icon,
        title: 'Inicia sesión para continuar',
        body: pitch,
        action: Column(
          children: [
            FilledButton(
              key: const Key('gate-login'),
              onPressed: () => context.push(withReturn('/login')),
              child: const Text('Iniciar sesión'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => context.push(withReturn('/register')),
              style: TextButton.styleFrom(foregroundColor: AppColors.blue),
              child: const Text('Crear una cuenta gratis'),
            ),
          ],
        ),
      ),
    );
  }
}
