import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_errors.dart';
import 'auth_providers.dart';
import 'validators.dart';
import 'widgets.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return AuthScaffold(
        title: 'Revisa tu correo',
        subtitle: 'Si existe una cuenta con ${_email.text.trim()}, te enviamos un enlace para crear una nueva '
            'contraseña. Revisa también la carpeta de spam.',
        children: [
          const Icon(Icons.mark_email_read_outlined, size: 72),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Volver a iniciar sesión'),
          ),
        ],
      );
    }

    return AuthScaffold(
      title: 'Recupera tu contraseña',
      subtitle: 'Te enviaremos un enlace para crear una nueva.',
      children: [
        if (_error != null) ErrorBanner(_error!),
        Form(
          key: _formKey,
          child: TextFormField(
            key: const Key('forgot-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: Validators.email,
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.email_outlined)),
          ),
        ),
        const SizedBox(height: 24),
        BusyButton(label: 'Enviar enlace', busy: _busy, onPressed: _submit),
      ],
    );
  }
}
