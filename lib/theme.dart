import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppColors {
  static const primary = Color(0xFF2563EB);
  static const bg = Color(0xFFF4F7FD);
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFE11D48);
  static const orange = Color(0xFFF59E0B);
  static const purple = Color(0xFF7C3AED);
  static const border = Color(0xFFE2E8F0);
  static const tint = Color(0xFFEAF1FF);

  /// Colours that change between light and dark mode. Use this in widgets
  /// (instead of AppColors.text / bg / tint / border) so dark mode works.
  static Palette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _darkPalette : _lightPalette;
}

class Palette {
  final Color bg, card, text, border, tint, segment;
  const Palette({
    required this.bg,
    required this.card,
    required this.text,
    required this.border,
    required this.tint,
    required this.segment,
  });
}

const _lightPalette = Palette(
  bg: Color(0xFFF4F7FD),
  card: Colors.white,
  text: Color(0xFF0F172A),
  border: Color(0xFFE2E8F0),
  tint: Color(0xFFEAF1FF),
  segment: Color(0xFFEAEFF8),
);

const _darkPalette = Palette(
  bg: Color(0xFF0B1220),
  card: Color(0xFF151E2E),
  text: Color(0xFFE6EBF5),
  border: Color(0xFF263247),
  tint: Color(0xFF1B2A4A),
  segment: Color(0xFF1E2A3F),
);

/// Remembers Light / Dark / System on this phone.
class ThemeController extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString('themeMode');
      mode = ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => ThemeMode.system);
    } catch (_) {}
  }

  Future<void> set(ThemeMode m) async {
    mode = m;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('themeMode', m.name);
    } catch (_) {}
  }
}

final ThemeController themeController = ThemeController();

ThemeData buildTheme({bool dark = false}) {
  final p = dark ? _darkPalette : _lightPalette;
  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: AppColors.primary,
      surface: p.card,
    ),
    scaffoldBackgroundColor: p.bg,
  );

  OutlineInputBorder border([Color? c]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c ?? p.border),
      );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: p.text,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(),
      enabledBorder: border(),
      focusedBorder: border(AppColors.primary),
      errorBorder: border(AppColors.red),
      focusedErrorBorder: border(AppColors.red),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: p.card,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.muted,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 11),
    ),
  );
}
