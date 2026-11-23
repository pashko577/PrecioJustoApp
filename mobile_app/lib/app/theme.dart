import 'package:flutter/material.dart';

/// Colores de la identidad CompraMejor (opción 3). Cada color tiene un solo significado:
/// marino = texto y estructura, azul = acción, magenta = descuento, turquesa = más barato,
/// ámbar = alerta o precio por confirmar.
abstract final class AppColors {
  static const ink = Color(0xFF0B1F4D);
  static const ink2 = Color(0xFF1E3A8A);
  static const blue = Color(0xFF2563EB);
  static const magenta = Color(0xFFE11D8E);
  static const magentaInk = Color(0xFFBE185D);
  static const amber = Color(0xFFF59E0B);
  static const amberInk = Color(0xFF92400E);
  static const teal = Color(0xFF14B8A6);
  static const tealInk = Color(0xFF0F766E);

  // Tonos suaves (fondos de chips, badges y fichas).
  static const lav = Color(0xFFEDE9FE);
  static const pink = Color(0xFFFCE7F3);
  static const cream = Color(0xFFFEF3C7);
  static const mint = Color(0xFFDCFCE7);
  static const sky = Color(0xFFDBEAFE);

  static const bg = Color(0xFFF4F6FB);
  static const surface = Colors.white;
  static const line = Color(0xFFE3E7F1);
  static const muted = Color(0xFF5B6478);

  /// Fondos suaves en rotación (categorías).
  static const tones = [lav, sky, pink, mint, cream];
}

abstract final class AppRadius {
  static const xl = 28.0;
  static const lg = 20.0;
  static const md = 14.0;
  static const sm = 10.0;
}

/// Números de ancho fijo para que los precios no «bailen» al cambiar.
const tabularFigures = [FontFeature.tabularFigures()];

ThemeData buildTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.blue,
    onPrimary: Colors.white,
    primaryContainer: AppColors.sky,
    onPrimaryContainer: AppColors.ink,
    secondary: AppColors.ink,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.lav,
    onSecondaryContainer: AppColors.ink,
    tertiary: AppColors.magenta,
    onTertiary: Colors.white,
    error: Color(0xFFB42318),
    onError: Colors.white,
    errorContainer: Color(0xFFFEE4E2),
    onErrorContainer: Color(0xFF7A271A),
    surface: AppColors.bg,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Colors.white,
    surfaceContainerHigh: Colors.white,
    surfaceContainerHighest: AppColors.line,
    outline: Color(0xFFC7CDDC),
    outlineVariant: AppColors.line,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Poppins');
  final text = base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));
  const buttonText = TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.15),
      headlineSmall: text.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: text.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, height: 1.35),
      titleMedium: text.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: text.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 15),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
      bodySmall: text.bodySmall?.copyWith(fontSize: 12, color: AppColors.muted, height: 1.4),
      labelLarge: text.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      labelMedium: text.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.muted),
      labelSmall: text.labelSmall?.copyWith(fontSize: 11, color: AppColors.muted),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: rounded,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.line),
        backgroundColor: AppColors.surface,
        shape: rounded,
        textStyle: buttonText.copyWith(fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.blue, textStyle: buttonText.copyWith(fontSize: 13)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.ink,
      checkmarkColor: Colors.white,
      side: const BorderSide(color: AppColors.line),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : AppColors.ink,
        ),
      ),
      secondaryLabelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.ink),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.blue : const Color(0xFFC7CDDC),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      contentTextStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.white),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.blue),
  );
}
