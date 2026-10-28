import 'package:flutter/material.dart';

/// Светлая «премиальная» тема приложения.
///
/// Цвета документов (чертёж, смета, PDF) живут отдельно и не зависят от
/// темы: здесь меняется только оболочка приложения. Тёплый фон, графитовый
/// текст и медный акцент дают ощущение мастерской, а не стандартной
/// Material-формы.
const Color appInk = Color(0xFF18222D);
const Color appCopper = Color(0xFFB86B3D);
const Color appCream = Color(0xFFF4EFE7);
const Color appPaper = Color(0xFFFFFCF8);
const Color appMuted = Color(0xFF6F746F);
const Color appLine = Color(0xFFE3D9CC);

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: appCopper,
    brightness: Brightness.light,
  ).copyWith(
    primary: appInk,
    onPrimary: Colors.white,
    secondary: appCopper,
    onSecondary: Colors.white,
    surface: appPaper,
    onSurface: appInk,
    surfaceContainerHighest: const Color(0xFFEDE5DA),
    outline: appLine,
    outlineVariant: const Color(0xFFEFE8DE),
    error: const Color(0xFFB03A3A),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: appCream,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: appInk,
      displayColor: appInk,
      fontFamily: null,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: appPaper,
      foregroundColor: appInk,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: appInk,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: appLine,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: appLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: appLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: appCopper, width: 1.4),
      ),
      labelStyle: const TextStyle(color: appMuted, fontSize: 12),
      hintStyle: const TextStyle(color: Color(0xFF9A9E98), fontSize: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: appInk,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: appInk,
        side: const BorderSide(color: appLine),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: appCopper,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFF2E2D5),
      side: const BorderSide(color: appLine),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(color: appInk, fontSize: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: appInk,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: appPaper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        color: appInk,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: appPaper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: appInk,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 11),
    ),
  );
}
