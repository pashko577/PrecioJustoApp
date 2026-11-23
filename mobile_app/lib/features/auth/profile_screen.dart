import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../models/user_profile.dart';
import 'auth_errors.dart';
import 'auth_providers.dart';
import 'validators.dart';
import 'widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final profile = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('No se pudo cargar tu perfil.\n$e', textAlign: TextAlign.center)),
        data: (p) => p == null || user == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    children: [
                      _Header(profile: p),
                      if (!user.emailVerified) const _VerifyEmailBanner(),
                      const Divider(height: 32),
                      _SectionTitle('Datos'),
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Nombre'),
                        subtitle: Text(p.displayName),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _editName(context, ref, p.displayName),
                      ),
                      ListTile(
                        leading: const Icon(Icons.email_outlined),
                        title: const Text('Correo'),
                        subtitle: Text(p.email),
                        trailing: user.emailVerified
                            ? const Tooltip(message: 'Verificado', child: Icon(Icons.verified, color: Colors.green))
                            : null,
                      ),
                      const Divider(height: 32),
                      _SectionTitle('Notificaciones'),
                      _PrefsSection(prefs: p.notificationPrefs),
                      const Divider(height: 32),
                      ListTile(
                        leading: const Icon(Icons.logout),
                        title: const Text('Cerrar sesión'),
                        onTap: () async {
                          // Primero al inicio (público); así la protección de rutas no envía al login.
                          ref.read(routerProvider).go('/');
                          await ref.read(authRepositoryProvider).signOut();
                        },
                      ),
                      ListTile(
                        key: const Key('delete-account'),
                        leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
                        title: Text('Eliminar mi cuenta',
                            style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        subtitle: const Text('Borra tu cuenta, favoritos y alertas de forma permanente.'),
                        onTap: () => showDialog<void>(context: context, builder: (_) => const DeleteAccountDialog()),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final formKey = GlobalKey<FormState>();
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar nombre'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            validator: Validators.displayName,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName == current) return;
    try {
      await ref.read(authRepositoryProvider).updateDisplayName(newName);
    } on AuthFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = profile.displayName.isNotEmpty ? profile.displayName[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          CircleAvatar(radius: 32, child: Text(initial, style: theme.textTheme.headlineSmall)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.displayName, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Chip(
                  label: Text(profile.isPremium ? 'Premium' : 'Plan gratuito'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _VerifyEmailBanner extends ConsumerStatefulWidget {
  const _VerifyEmailBanner();

  @override
  ConsumerState<_VerifyEmailBanner> createState() => _VerifyEmailBannerState();
}

class _VerifyEmailBannerState extends ConsumerState<_VerifyEmailBanner> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(okMessage)));
    } on AuthFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(authRepositoryProvider);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Verifica tu correo para recibir alertas de precio.'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(repo.sendEmailVerification, 'Te reenviamos el correo.'),
                  child: const Text('Reenviar correo'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await repo.reloadUser();
                            ref.invalidate(authStateProvider);
                          }, 'Estado actualizado.'),
                  child: const Text('Ya lo verifiqué'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrefsSection extends ConsumerWidget {
  const _PrefsSection({required this.prefs});

  final NotificationPrefs prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void save(NotificationPrefs updated) => ref.read(authRepositoryProvider).updateNotificationPrefs(updated);

    return Column(
      children: [
        SwitchListTile(
          title: const Text('Notificaciones push'),
          value: prefs.push,
          onChanged: (v) => save(prefs.copyWith(push: v)),
        ),
        SwitchListTile(
          title: const Text('Alertas de precio'),
          value: prefs.priceAlerts,
          onChanged: prefs.push ? (v) => save(prefs.copyWith(priceAlerts: v)) : null,
        ),
        SwitchListTile(
          title: const Text('Producto disponible nuevamente'),
          value: prefs.backInStock,
          onChanged: prefs.push ? (v) => save(prefs.copyWith(backInStock: v)) : null,
        ),
        SwitchListTile(
          title: const Text('Resumen semanal'),
          value: prefs.weeklySummary,
          onChanged: prefs.push ? (v) => save(prefs.copyWith(weeklySummary: v)) : null,
        ),
      ],
    );
  }
}

/// Confirmación de eliminación de cuenta: pide la contraseña (reautenticación).
class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  ConsumerState<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Ingresa tu contraseña.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final router = ref.read(routerProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authRepositoryProvider).deleteAccount(password: _password.text);
      // Al reemplazar las páginas se cierra también este diálogo.
      router.go('/');
      messenger.showSnackBar(const SnackBar(content: Text('Tu cuenta y tus datos fueron eliminados.')));
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('¿Eliminar tu cuenta?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Se borrarán tu cuenta, favoritos, listas y alertas. Esta acción no se puede deshacer.'),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(_error!),
          PasswordField(
            key: const Key('delete-password'),
            controller: _password,
            label: 'Confirma con tu contraseña',
            onSubmitted: (_) => _delete(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('delete-confirm'),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: _busy ? null : _delete,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Eliminar'),
        ),
      ],
    );
  }
}
