import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Usa los emuladores locales salvo que se compile con `--dart-define=USE_EMULATORS=false`.
const bool useEmulators = bool.fromEnvironment('USE_EMULATORS', defaultValue: true);

/// Host de los emuladores. El emulador de Android ve la PC como 10.0.2.2.
/// En un celular físico, pasar la IP de la PC: `--dart-define=EMULATOR_HOST=192.168.1.50`
/// (y levantar los emuladores con host 0.0.0.0).
String get emulatorHost {
  const override = String.fromEnvironment('EMULATOR_HOST');
  if (override.isNotEmpty) return override;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return '10.0.2.2';
  return '127.0.0.1';
}

const int firestoreEmulatorPort = 8085;
const int authEmulatorPort = 9099;

Future<void> initFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (useEmulators) {
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, firestoreEmulatorPort);
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, authEmulatorPort);
    debugPrint('PRECIO JUSTO: usando emuladores en $emulatorHost');
  }
}
