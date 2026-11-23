import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/notifications/notifications.dart';
import '../services/push_service.dart';
import 'router.dart';
import 'theme.dart';

class CompraMejorApp extends ConsumerWidget {
  const CompraMejorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Registra/desregistra el celular para push según la sesión (no hace nada en emuladores ni web).
    ref.watch(pushServiceProvider);
    return MaterialApp.router(
      title: 'CompraMejor',
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
