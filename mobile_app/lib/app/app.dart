import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/notifications/notifications.dart';
import '../services/push_service.dart';
import 'router.dart';

class PrecioJustoApp extends ConsumerWidget {
  const PrecioJustoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Registra/desregistra el celular para push según la sesión (no hace nada en emuladores ni web).
    ref.watch(pushServiceProvider);
    return MaterialApp.router(
      title: 'PRECIO JUSTO',
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

ThemeData buildTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F7B5F)),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
