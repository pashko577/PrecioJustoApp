/// Validaciones de formularios. Devuelven `null` si el valor es válido
/// (compatible con `TextFormField.validator`).
class Validators {
  Validators._();

  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static const int minPasswordLength = 8;
  static const int maxNameLength = 80;

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa tu correo.';
    if (!_emailRe.hasMatch(v)) return 'El correo no es válido.';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Ingresa una contraseña.';
    if (v.length < minPasswordLength) return 'Usa al menos $minPasswordLength caracteres.';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Incluye al menos una letra y un número.';
    }
    return null;
  }

  /// Para iniciar sesión solo se exige que no esté vacía
  /// (las cuentas antiguas podrían no cumplir reglas nuevas).
  static String? loginPassword(String? value) =>
      (value ?? '').isEmpty ? 'Ingresa tu contraseña.' : null;

  static String? Function(String?) confirmPassword(String Function() original) =>
      (value) => value != original() ? 'Las contraseñas no coinciden.' : null;

  static String? displayName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa tu nombre.';
    if (v.length < 2) return 'El nombre es muy corto.';
    if (v.length > maxNameLength) return 'Máximo $maxNameLength caracteres.';
    return null;
  }
}
