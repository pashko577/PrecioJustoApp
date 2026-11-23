import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_bootstrap.dart';

/// Clave global para mostrar avisos (SnackBar) desde fuera de un `BuildContext`,
/// por ejemplo cuando llega una notificación con la app abierta.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// ¿Este entorno puede recibir notificaciones push?
/// - En emuladores no: FCM no tiene emulador y el proyecto demo no emite tokens.
/// - En web no (requiere clave VAPID y service worker; se agregará si se publica la versión web).
bool get pushSupported =>
    !useEmulators &&
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Registra el dispositivo del usuario para notificaciones push (RF-12).
///
/// El token se guarda en `users/{uid}/devices/{token}` (el motor lo usa para enviar).
/// Al cerrar sesión se borra, para no seguir enviando avisos a este celular.
class PushService {
  PushService(this._db, this._messaging);

  final FirebaseFirestore _db;
  final FirebaseMessaging _messaging;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _foreground;
  String? _uid;
  String? _token;

  static String platformName() =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  DocumentReference<Map<String, dynamic>> _device(String uid, String token) =>
      _db.collection('users').doc(uid).collection('devices').doc(token);

  Future<void> _saveToken(String uid, String token) async {
    _token = token;
    await _device(uid, token).set({
      'platform': platformName(),
      'pushToken': token,
      'status': 'ACTIVE',
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
  }

  /// Llamar al iniciar sesión. Pide permiso (Android 13+ / iOS) y guarda el token.
  Future<void> register(String uid) async {
    if (!pushSupported || _uid == uid) return;
    _uid = uid;
    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;
    // getToken/onTokenRefresh están obsoletos en firebase_messaging 17 en favor de register() +
    // onRegistered, que entregan un Firebase Installation ID para "direct-send". El motor envía con
    // firebase-admin (Python) usando tokens FCM clásicos, el mecanismo probado; migrar cuando
    // firebase-admin soporte enviar a FIDs y verificarlo en un dispositivo real.
    // ignore: deprecated_member_use
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(uid, token);
    await _refresh?.cancel();
    // ignore: deprecated_member_use
    _refresh = _messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
    await _foreground?.cancel();
    // Con la app abierta, el sistema no muestra la notificación: se muestra un aviso.
    _foreground = FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null) return;
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text([n.title, n.body].whereType<String>().join('\n')),
        ),
      );
    });
  }

  /// Llamar al cerrar sesión: este celular deja de recibir los avisos de esa cuenta.
  Future<void> unregister() async {
    final uid = _uid, token = _token;
    _uid = null;
    _token = null;
    await _refresh?.cancel();
    await _foreground?.cancel();
    if (uid != null && token != null) {
      try {
        await _device(uid, token).delete();
      } catch (_) {
        // Sin sesión ya no hay permiso: el motor marcará el token como inválido al fallar.
      }
    }
  }
}
