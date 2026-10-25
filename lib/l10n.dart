import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_strings.dart';

enum AppLang {
  en('English', 'English'),
  kn('Kannada', 'ಕನ್ನಡ'),
  hi('Hindi', 'हिन्दी');

  const AppLang(this.englishName, this.nativeName);
  final String englishName;
  final String nativeName;
}

/// Current app language (saved on this phone). Every Text() in the app asks
/// [tr] for a translation of its text; text with no translation stays English.
class LanguageController extends ChangeNotifier {
  AppLang lang = AppLang.en;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString('language');
      lang = AppLang.values.firstWhere((l) => l.name == v, orElse: () => AppLang.en);
    } catch (_) {}
  }

  Future<void> set(AppLang l) async {
    lang = l;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('language', l.name);
    } catch (_) {}
  }

  String tr(String s) {
    switch (lang) {
      case AppLang.kn:
        return knStrings[s] ?? s;
      case AppLang.hi:
        return hiStrings[s] ?? s;
      case AppLang.en:
        return s;
    }
  }
}

final LanguageController language = LanguageController();

String tr(String s) => language.tr(s);
