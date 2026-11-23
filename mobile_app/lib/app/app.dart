import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/catalog/home_screen.dart';
import '../features/catalog/product_screen.dart';

final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'product/:id',
          builder: (_, state) => ProductScreen(productId: state.pathParameters['id']!),
        ),
      ],
    ),
  ],
);

class PrecioJustoApp extends StatelessWidget {
  const PrecioJustoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PRECIO JUSTO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F7B5F)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
