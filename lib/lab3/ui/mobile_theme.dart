import 'package:flutter/material.dart';

import '../../ui/theme.dart';

abstract final class MobileTokens {
  static const background = Color(0xFFFFF7F3);
  static const border = Color(0xFFD9DEE7);
  static const radius = BorderRadius.all(Radius.circular(16));
  static const gap = 16.0;
}

ThemeData mobileTheme() {
  final base = buildAppTheme();
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.orangeDark,
      outline: AppColors.muted,
      secondary: AppColors.orangeDark,
      secondaryContainer: AppColors.orangeSoft,
      onSecondaryContainer: AppColors.orangeDark,
    ),
    scaffoldBackgroundColor: MobileTokens.background,
    textTheme: ThemeData(fontFamily: 'Roboto').textTheme
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
        .copyWith(
          bodyMedium: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 16,
            height: 1.5,
            color: AppColors.ink,
          ),
          bodySmall: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            height: 1.4,
            color: AppColors.muted,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.orangeDark,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      toolbarHeight: 64,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        backgroundColor: AppColors.orangeDark,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        minimumSize: const Size(0, 52),
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.muted),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size(48, 48)),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontFamily: 'Roboto', fontSize: 14),
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 14,
        color: Colors.white,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: MobileTokens.radius,
        side: BorderSide(color: MobileTokens.border),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.muted),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.orangeSoft,
      height: 76,
    ),
  );
}
