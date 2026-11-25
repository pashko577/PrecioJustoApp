import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import 'auth_errors.dart';
import 'auth_providers.dart';
import 'validators.dart';
import 'widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signIn(email: _email.text, password: _password.text);
      if (mounted) leaveAuthFlow(context);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Conserva el destino original (`?from=`) al ir a registro.
  String _withFrom(String path) {
    final from = GoRouterState.of(context).uri.queryParameters['from'];
    return from == null ? path : Uri(path: path, queryParameters: {'from': from}).toString();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Inicia sesión',
      subtitle: 'Guarda favoritos y recibe alertas cuando baje el precio.',
      children: [
        if (_error != null) ErrorBanner(_error!),
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('login-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: Validators.email,
                  decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.email_outlined)),
                ),
                const SizedBox(height: 16),
                PasswordField(
                  key: const Key('login-password'),
                  controller: _password,
                  validator: Validators.loginPassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.push(
              Uri(path: '/forgot-password', queryParameters: {
                if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
              }).toString(),
            ),
            child: const Text('¿Olvidaste tu contraseña?'),
          ),
        ),
        const SizedBox(height: 8),
        BusyButton(label: 'Ingresar', busy: _busy, onPressed: _submit),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('¿No tienes cuenta?'),
            TextButton(
              onPressed: () => context.pushReplacement(_withFrom('/register')),
              child: const Text('Crear cuenta'),
            ),
          ],
        ),
        // Google Sign-In: pendiente (requiere correo de soporte del proyecto).
      ],
    );
  }
}
