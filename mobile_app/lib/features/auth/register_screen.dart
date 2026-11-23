import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_errors.dart';
import 'auth_providers.dart';
import 'validators.dart';
import 'widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _acceptedTerms = false;
  bool _showTermsError = false;
  bool _busy = false;
  String? _error;
  late final _policyTap = TapGestureRecognizer()..onTap = _showPolicyPending;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    _policyTap.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState!.validate();
    setState(() => _showTermsError = !_acceptedTerms);
    if (!valid || !_acceptedTerms) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).register(
            displayName: _name.text,
            email: _email.text,
            password: _password.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Cuenta creada! Te enviamos un correo para verificar tu dirección.')),
        );
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showPolicyPending() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Términos y privacidad'),
        content: const Text(
          'CompraMejor solo guarda tu correo, tu nombre y tus preferencias para prestarte el servicio '
          '(favoritos y alertas de precio). Los datos se alojan en servidores de Google (Firebase) fuera del Perú. '
          'Puedes eliminar tu cuenta y tus datos en cualquier momento desde tu perfil.\n\n'
          'El documento completo se publicará antes del lanzamiento.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AuthScaffold(
      title: 'Crea tu cuenta',
      subtitle: 'Es gratis. Solo te pediremos lo necesario.',
      children: [
        if (_error != null) ErrorBanner(_error!),
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('register-name'),
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  validator: Validators.displayName,
                  decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('register-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: Validators.email,
                  decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.email_outlined)),
                ),
                const SizedBox(height: 16),
                PasswordField(
                  key: const Key('register-password'),
                  controller: _password,
                  validator: Validators.password,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: 4),
                Text(
                  'Mínimo ${Validators.minPasswordLength} caracteres, con letras y números.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                PasswordField(
                  key: const Key('register-confirm'),
                  controller: _confirm,
                  label: 'Repite la contraseña',
                  validator: Validators.confirmPassword(() => _password.text),
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const Key('register-terms'),
          value: _acceptedTerms,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => setState(() {
            _acceptedTerms = v ?? false;
            if (_acceptedTerms) _showTermsError = false;
          }),
          title: Text.rich(
            TextSpan(
              text: 'Acepto los ',
              children: [
                TextSpan(
                  text: 'términos y la política de privacidad',
                  style: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
                  recognizer: _policyTap,
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
          subtitle: _showTermsError
              ? Text('Debes aceptar para continuar.', style: TextStyle(color: theme.colorScheme.error))
              : null,
        ),
        const SizedBox(height: 8),
        BusyButton(label: 'Crear cuenta', busy: _busy, onPressed: _submit),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('¿Ya tienes cuenta?'),
            TextButton(
              onPressed: () {
                final from = GoRouterState.of(context).uri.queryParameters['from'];
                context.pushReplacement(
                  from == null ? '/login' : Uri(path: '/login', queryParameters: {'from': from}).toString(),
                );
              },
              child: const Text('Inicia sesión'),
            ),
          ],
        ),
      ],
    );
  }
}
