import 'package:firebase_auth/firebase_auth.dart';

/// Error de autenticación con un mensaje listo para mostrar al usuario.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Traduce los códigos de Firebase Auth a mensajes en español.
AuthFailure mapAuthError(Object error) {
  if (error is AuthFailure) return error;
  if (error is FirebaseAuthException) {
    final message = switch (error.code) {
      'invalid-email' => 'El correo no es válido.',
      'user-disabled' => 'Esta cuenta está desactivada.',
      'user-not-found' || 'wrong-password' || 'invalid-credential' || 'INVALID_LOGIN_CREDENTIALS' =>
        'Correo o contraseña incorrectos.',
      'email-already-in-use' => 'Ese correo ya está registrado. Inicia sesión o recupera tu contraseña.',
      'weak-password' => 'La contraseña es muy débil.',
      'too-many-requests' => 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.',
      'network-request-failed' => 'Sin conexión. Revisa tu internet.',
      'requires-recent-login' => 'Por seguridad, vuelve a ingresar tu contraseña.',
      'operation-not-allowed' => 'Este método de inicio de sesión no está habilitado.',
      'missing-email' => 'Ingresa tu correo.',
      _ => 'Ocurrió un error inesperado (${error.code}). Inténtalo de nuevo.',
    };
    return AuthFailure(message, code: error.code);
  }
  return const AuthFailure('Ocurrió un error inesperado. Inténtalo de nuevo.');
}
