import 'package:flutter/material.dart';

abstract final class AppColors {
  static const orange = Color(0xFFF4511E);
  static const orangeDark = Color(0xFFC93C13);
  static const orangeSoft = Color(0xFFFFEEE7);
  static const cream = Color(0xFFFFF4EE);
  static const creamLight = Color(0xFFFFFAF7);
  static const canvas = Color(0xFFFFFDFC);
  static const ink = Color(0xFF243047);
  static const muted = Color(0xFF667085);
  static const border = Color(0xFFF0DDD4);
  static const panel = Color(0xFFF7F3F1);
  static const success = Color(0xFF16835D);
  static const danger = Color(0xFFC93A2B);
  static const info = Color(0xFF2563B8);
  static const infoSoft = Color(0xFFEFF6FF);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.orange,
    onPrimary: Colors.white,
    primaryContainer: AppColors.orangeSoft,
    onPrimaryContainer: AppColors.ink,
    secondary: AppColors.info,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.infoSoft,
    onSecondaryContainer: AppColors.info,
    tertiary: AppColors.success,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFDFF3EA),
    onTertiaryContainer: Color(0xFF0C4A36),
    error: AppColors.danger,
    onError: Colors.white,
    surface: Colors.white,
    onSurface: AppColors.ink,
    outline: AppColors.border,
    outlineVariant: Color(0xFFF7E9E2),
  );
  const radius = BorderRadius.all(Radius.circular(14));
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Segoe UI',
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    textTheme: const TextTheme(
      displayMedium: TextStyle(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
      headlineLarge: TextStyle(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
        letterSpacing: -.8,
      ),
      headlineMedium: TextStyle(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
        letterSpacing: -.5,
      ),
      headlineSmall: TextStyle(
        color: AppColors.ink,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(color: AppColors.ink, height: 1.45),
      bodyMedium: TextStyle(color: AppColors.muted, height: 1.4),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 72,
      shape: Border(bottom: BorderSide(color: AppColors.border)),
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: .5,
      ),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.orange, width: 1.6),
      ),
      labelStyle: TextStyle(color: AppColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        side: const BorderSide(color: AppColors.border),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.creamLight,
      selectedColor: AppColors.orangeSoft,
      side: BorderSide(color: AppColors.border),
      shape: StadiumBorder(),
      labelStyle: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}
