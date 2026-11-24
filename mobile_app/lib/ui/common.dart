import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/image_url.dart';

/// Foto del producto publicada por la tienda (`imageUrl`). Las fotos vienen sobre blanco:
/// se funden con el fondo (`multiply`) para que no se vea un recuadro. Sin foto, o si no
/// carga, se muestra un ícono neutro.
class ProductImage extends StatelessWidget {
  const ProductImage({super.key, required this.url, this.background = AppColors.bg, this.padding = 10});

  final String? url;
  final Color background;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final placeholder = Center(
      child: Icon(Icons.inventory_2_outlined, size: 32, color: AppColors.muted.withValues(alpha: 0.6)),
    );
    return ColoredBox(
      color: background,
      child: url == null || url!.isEmpty
          ? placeholder
          : Padding(
              padding: EdgeInsets.all(padding),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Se pide la foto al tamaño en que se ve (y en WebP si la tienda lo permite),
                  // se guarda en disco y se decodifica a ese tamaño: menos datos y menos memoria.
                  final side = [constraints.maxWidth, constraints.maxHeight]
                      .where((v) => v.isFinite)
                      .fold<double>(0, (a, b) => a > b ? a : b);
                  final px = imageBucket(side == 0 ? 160 : side, MediaQuery.devicePixelRatioOf(context));
                  return CachedNetworkImage(
                    imageUrl: sizedImageUrl(url!, px),
                    httpHeaders: isVtexImage(url!) ? const {'Accept': 'image/webp,image/*'} : null,
                    memCacheWidth: px,
                    fit: BoxFit.contain,
                    color: background,
                    colorBlendMode: BlendMode.multiply,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (_, _) => const SizedBox.shrink(),
                    errorWidget: (_, _, _) => placeholder,
                  );
                },
              ),
            ),
    );
  }
}

/// Pantalla o sección vacía: dice qué pasa y qué hacer.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: AppColors.sky, shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: AppColors.ink),
            ),
            const SizedBox(height: 14),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Título de sección con acción opcional a la derecha.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 17))),
            if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ),
      );
}

/// Etiqueta pequeña tipo píldora (descuento, estado de alerta, etc.).
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.background, required this.foreground, this.icon});

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 13, color: foreground), const SizedBox(width: 4)],
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: foreground, height: 1.3)),
          ],
        ),
      );
}

/// Bloque blanco redondeado (fichas de detalle, listas de preferencias).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.border});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: border,
        ),
        child: child,
      );
}
