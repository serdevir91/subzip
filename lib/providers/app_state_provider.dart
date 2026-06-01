import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppStateProvider extends ChangeNotifier {
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyAccentColor = 'accent_color';
  static const String _keyIsGridView = 'is_grid_view';

  late SharedPreferences _prefs;

  ThemeMode _themeMode = ThemeMode.dark;
  String _accentColorName = 'Orange'; // Default is Orange
  bool _isGridView = false; // Default is list view

  ThemeMode get themeMode => _themeMode;
  String get accentColorName => _accentColorName;
  bool get isGridView => _isGridView;

  final Map<String, Color> accentColors = {
    'Orange': const Color(0xFFFF6D00),
    'Blue': const Color(0xFF2196F3),
    'Green': const Color(0xFF4CAF50),
    'Purple': const Color(0xFF9C27B0),
    'Red': const Color(0xFFE91E63),
    'Teal': const Color(0xFF009688),
    'Cyan': const Color(0xFF00BCD4),
    'Amber': const Color(0xFFFFB300),
  };

  Color get accentColor => accentColors[_accentColorName] ?? const Color(0xFFFF6D00);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    
    // Load theme
    final themeIndex = _prefs.getInt(_keyThemeMode);
    if (themeIndex != null) {
      _themeMode = ThemeMode.values[themeIndex];
    }

    // Load accent color
    final accentName = _prefs.getString(_keyAccentColor);
    if (accentName != null && accentColors.containsKey(accentName)) {
      _accentColorName = accentName;
    }

    // Load layout
    _isGridView = _prefs.getBool(_keyIsGridView) ?? false;
    
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setInt(_keyThemeMode, mode.index);
    notifyListeners();
  }

  Future<void> setAccentColor(String name) async {
    if (accentColors.containsKey(name)) {
      _accentColorName = name;
      await _prefs.setString(_keyAccentColor, name);
      notifyListeners();
    }
  }

  Future<void> toggleLayout() async {
    _isGridView = !_isGridView;
    await _prefs.setBool(_keyIsGridView, _isGridView);
    notifyListeners();
  }
}
