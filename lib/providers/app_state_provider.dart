import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_category.dart';

class AppStateProvider extends ChangeNotifier {
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyAccentColor = 'accent_color';
  static const String _keyIsGridView = 'is_grid_view';
  static const String _keyShowHiddenFiles = 'show_hidden_files';
  static const String _keyProtectFavoritesFromDelete =
      'protect_favorites_from_delete';
  static const String _keyShowWelcomeCard = 'show_welcome_card';
  static const String _keyLargestExpanded = 'dashboard_largest_expanded';
  static const String _keyRecentExpanded = 'dashboard_recent_expanded';
  static const String _keyCustomCategories = 'custom_categories';

  late SharedPreferences _prefs;

  ThemeMode _themeMode = ThemeMode.dark;
  String _accentColorName = 'Orange'; // Default is Orange
  bool _isGridView = false; // Default is list view
  bool _showHiddenFiles = false;
  bool _protectFavoritesFromDelete = true;
  bool _showWelcomeCard = true;
  bool _largestExpanded = false;
  bool _recentExpanded = false;
  final List<FileCategory> _customCategories = [];

  ThemeMode get themeMode => _themeMode;
  String get accentColorName => _accentColorName;
  bool get isGridView => _isGridView;
  bool get showHiddenFiles => _showHiddenFiles;
  bool get protectFavoritesFromDelete => _protectFavoritesFromDelete;
  bool get showWelcomeCard => _showWelcomeCard;
  bool get largestExpanded => _largestExpanded;
  bool get recentExpanded => _recentExpanded;
  List<FileCategory> get customCategories =>
      List.unmodifiable(_customCategories);

  String? _bannerMessage;
  bool _bannerIsError = false;
  Timer? _bannerTimer;

  String? get bannerMessage => _bannerMessage;
  bool get bannerIsError => _bannerIsError;
  List<FileCategory> get allCategories => [
    ...FileCategory.builtInCategories,
    ..._customCategories,
  ];

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

  Color get accentColor =>
      accentColors[_accentColorName] ?? const Color(0xFFFF6D00);

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

    _showHiddenFiles = _prefs.getBool(_keyShowHiddenFiles) ?? false;
    _protectFavoritesFromDelete =
        _prefs.getBool(_keyProtectFavoritesFromDelete) ?? true;
    _showWelcomeCard = _prefs.getBool(_keyShowWelcomeCard) ?? true;
    _largestExpanded = _prefs.getBool(_keyLargestExpanded) ?? false;
    _recentExpanded = _prefs.getBool(_keyRecentExpanded) ?? false;

    final categoriesJson = _prefs.getString(_keyCustomCategories);
    if (categoriesJson != null) {
      try {
        final decoded = jsonDecode(categoriesJson) as List<dynamic>;
        _customCategories
          ..clear()
          ..addAll(
            decoded
                .map(
                  (item) => FileCategory.fromJson(item as Map<String, dynamic>),
                )
                .where((category) => category.type == FileCategoryType.folder),
          );
      } catch (e) {
        debugPrint('Error loading custom categories: $e');
      }
    }

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

  Future<void> setShowHiddenFiles(bool value) async {
    _showHiddenFiles = value;
    await _prefs.setBool(_keyShowHiddenFiles, value);
    notifyListeners();
  }

  Future<void> setProtectFavoritesFromDelete(bool value) async {
    _protectFavoritesFromDelete = value;
    await _prefs.setBool(_keyProtectFavoritesFromDelete, value);
    notifyListeners();
  }

  Future<void> setShowWelcomeCard(bool value) async {
    _showWelcomeCard = value;
    await _prefs.setBool(_keyShowWelcomeCard, value);
    notifyListeners();
  }

  Future<void> setLargestExpanded(bool value) async {
    _largestExpanded = value;
    await _prefs.setBool(_keyLargestExpanded, value);
    notifyListeners();
  }

  Future<void> setRecentExpanded(bool value) async {
    _recentExpanded = value;
    await _prefs.setBool(_keyRecentExpanded, value);
    notifyListeners();
  }

  Future<void> addFolderCategory({
    required String label,
    required String folderPath,
  }) async {
    final trimmedLabel = label.trim();
    final trimmedPath = folderPath.trim();
    if (trimmedLabel.isEmpty || trimmedPath.isEmpty) return;

    final id = 'folder_${DateTime.now().microsecondsSinceEpoch}';
    _customCategories.add(
      FileCategory(
        id: id,
        label: trimmedLabel,
        type: FileCategoryType.folder,
        iconName: 'folder',
        folderPath: trimmedPath,
        editable: true,
      ),
    );
    await _saveCustomCategories();
    notifyListeners();
  }

  Future<void> updateFolderCategory(
    String id, {
    required String label,
    required String folderPath,
  }) async {
    final index = _customCategories.indexWhere((category) => category.id == id);
    if (index == -1) return;

    final trimmedLabel = label.trim();
    final trimmedPath = folderPath.trim();
    if (trimmedLabel.isEmpty || trimmedPath.isEmpty) return;

    _customCategories[index] = _customCategories[index].copyWith(
      label: trimmedLabel,
      folderPath: trimmedPath,
    );
    await _saveCustomCategories();
    notifyListeners();
  }

  Future<void> removeFolderCategory(String id) async {
    _customCategories.removeWhere((category) => category.id == id);
    await _saveCustomCategories();
    notifyListeners();
  }

  Future<void> moveFolderCategory(int oldIndex, int newIndex) async {
    if (_customCategories.length < 2) return;
    if (oldIndex < 0 || oldIndex >= _customCategories.length) return;
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) targetIndex -= 1;
    targetIndex = targetIndex.clamp(0, _customCategories.length - 1);
    final category = _customCategories.removeAt(oldIndex);
    _customCategories.insert(targetIndex, category);
    await _saveCustomCategories();
    notifyListeners();
  }

  Future<void> _saveCustomCategories() async {
    await _prefs.setString(
      _keyCustomCategories,
      jsonEncode(
        _customCategories.map((category) => category.toJson()).toList(),
      ),
    );
  }

  void showBannerNotification(String message, {bool isError = false}) {
    _bannerTimer?.cancel();
    _bannerMessage = message;
    _bannerIsError = isError;
    notifyListeners();

    _bannerTimer = Timer(const Duration(seconds: 4), () {
      _bannerMessage = null;
      notifyListeners();
    });
  }

  void dismissBannerNotification() {
    _bannerTimer?.cancel();
    _bannerMessage = null;
    notifyListeners();
  }

  Future<String> _compressFolderToTemp(String folderPath) async {
    final tempDir = Directory.systemTemp;
    final folderName = p.basename(folderPath);
    final targetZipPath = p.join(tempDir.path, '${folderName}_shared.zip');
    
    final encoder = ZipFileEncoder();
    encoder.create(targetZipPath, level: 1);
    
    final dir = Directory(folderPath);
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: dir.parent.path);
        encoder.addFile(entity, relativePath.replaceAll(Platform.pathSeparator, '/'));
      }
    }
    encoder.close();
    return targetZipPath;
  }

  Future<void> sharePaths(BuildContext context, List<String> paths) async {
    if (paths.isEmpty) return;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(
              child: Text('Preparing items for sharing...'),
            ),
          ],
        ),
      ),
    );

    try {
      final List<XFile> filesToShare = [];
      final List<File> tempFilesToDelete = [];

      for (final path in paths) {
        final type = FileSystemEntity.typeSync(path);
        if (type == FileSystemEntityType.file) {
          filesToShare.add(XFile(path));
        } else if (type == FileSystemEntityType.directory) {
          final tempZipPath = await _compressFolderToTemp(path);
          filesToShare.add(XFile(tempZipPath));
          tempFilesToDelete.add(File(tempZipPath));
        }
      }

      // Pop progress dialog
      if (context.mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (filesToShare.isNotEmpty) {
        if (!context.mounted) return;
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        final Rect? sharePositionOrigin = box != null
            ? (box.localToGlobal(Offset.zero) & box.size)
            : null;

        await SharePlus.instance.share(
          ShareParams(
            files: filesToShare,
            sharePositionOrigin: sharePositionOrigin,
          ),
        );
      }

      // Cleanup temp files after delay
      Future.delayed(const Duration(seconds: 30), () {
        for (final file in tempFilesToDelete) {
          if (file.existsSync()) {
            try {
              file.deleteSync();
            } catch (_) {}
          }
        }
      });
    } catch (e) {
      // Pop progress dialog on error
      if (context.mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      showBannerNotification('Failed to share items: $e', isError: true);
    }
  }
}
