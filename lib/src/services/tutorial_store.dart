import 'package:shared_preferences/shared_preferences.dart';

class TutorialStore {
  TutorialStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  static const _welcomeKey = 'tutorial_welcome_seen';
  static const _pagesKey = 'tutorial_pages_seen';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync? _resolvePreferences() {
    if (_preferences != null) return _preferences;
    try {
      return _preferences = SharedPreferencesAsync();
    } catch (_) {
      return null;
    }
  }

  Future<bool?> loadWelcomeSeen() async {
    final preferences = _resolvePreferences();
    if (preferences == null) return null;
    try {
      return await preferences.getBool(_welcomeKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveWelcomeSeen() async {
    final preferences = _resolvePreferences();
    if (preferences == null) return;
    try {
      await preferences.setBool(_welcomeKey, true);
    } catch (_) {}
  }

  Future<Set<String>?> loadPagesSeen() async {
    final preferences = _resolvePreferences();
    if (preferences == null) return null;
    try {
      final values = await preferences.getStringList(_pagesKey);
      return values?.toSet();
    } catch (_) {
      return null;
    }
  }

  Future<void> savePagesSeen(Set<String> pageIds) async {
    final preferences = _resolvePreferences();
    if (preferences == null) return;
    try {
      final sorted = pageIds.toList()..sort();
      await preferences.setStringList(_pagesKey, sorted);
    } catch (_) {}
  }
}
