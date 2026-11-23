// ARCHIVO PROVISIONAL para desarrollo con emuladores (proyecto "demo-precio-justo").
//
// Cuando exista el proyecto real de Firebase, ejecutar en mobile_app/:
//   dart pub global activate flutterfire_cli
//   flutterfire configure
// Ese comando REEMPLAZA este archivo con la configuración real.
//
// Nota: estos valores no son secretos; la seguridad la dan las reglas de Firestore.

import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const FirebaseOptions currentPlatform = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:android:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-precio-justo',
  );
}
