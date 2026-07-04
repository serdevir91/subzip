import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shared_file.dart';
import '../models/folder_style.dart';
import '../models/file_category.dart';
import '../services/storage_service.dart';

class FileSystemProvider extends ChangeNotifier {
  static const String _keyFavorites = 'favorites';
  static const String _keyFolderStyles = 'folder_styles';
  static const String _keyShowHiddenFiles = 'show_hidden_files';

  final StorageService _storageService;
  late SharedPreferences _prefs;

  String _currentPath = '';
  List<SharedFile> _files = [];
  bool _isLoading = false;
  String _searchQuery = '';

  // Navigation Stacks
  final List<String> _backStack = [];
  final List<String> _forwardStack = [];

  // Search Filters
  String _searchScope =
      'all_files'; // 'all_files', 'current', 'subfolders', 'all_drives'
  String _selectedSearchDrive = ''; // For Windows: e.g. 'C:\'
  String _categoryFilter =
      'all'; // 'all', 'images', 'videos', 'audio', 'documents', 'apk'

  // Selection
  final Set<String> _selectedPaths = {};
  bool _isSelectionMode = false;

  // Clipboard
  List<String> _clipboardPaths = [];
  bool _isCut = false;

  // Favorites
  final Set<String> _favoritePaths = {};
  bool _showHiddenFiles = false;

  // Custom Folder Styles
  final Map<String, FolderStyle> _folderStyles = {};
  int _refreshEpoch = 0;
  Timer? _searchDebounceTimer;
  bool _isDashboardCategoryMode = false;

  // Getters
  String get currentPath => _currentPath;
  List<SharedFile> get files => _files;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;

  // Navigation History Getters
  bool get canGoBack => _backStack.isNotEmpty;
  bool get canGoForward => _forwardStack.isNotEmpty;

  // Search Filter Getters
  String get searchScope => _searchScope;
  String get selectedSearchDrive => _selectedSearchDrive;
  String get categoryFilter => _categoryFilter;

  // Selection Getters
  Set<String> get selectedPaths => _selectedPaths;
  bool get isSelectionMode => _isSelectionMode;

  // Clipboard Getters
  List<String> get clipboardPaths => _clipboardPaths;
  bool get isCut => _isCut;
  bool get hasClipboardItems => _clipboardPaths.isNotEmpty;

  // Favorites Getters
  Set<String> get favoritePaths => _favoritePaths;
  bool get showHiddenFiles => _showHiddenFiles;

  // Folder Styles Getter
  Map<String, FolderStyle> get folderStyles => _folderStyles;

  List<SharedFile> getWindowsDrives() => _storageService.getWindowsDrives();

  FileSystemProvider({required StorageService storageService})
    : _storageService = storageService;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    // Set initial path to storage root
    _currentPath = _storageService.rootPath;

    // Load Favorites
    final favList = _prefs.getStringList(_keyFavorites);
    if (favList != null) {
      _favoritePaths.addAll(favList);
    }

    _showHiddenFiles = _prefs.getBool(_keyShowHiddenFiles) ?? false;

    // Load Folder Styles
    final stylesJson = _prefs.getString(_keyFolderStyles);
    if (stylesJson != null) {
      try {
        final Map<String, dynamic> decoded =
            jsonDecode(stylesJson) as Map<String, dynamic>;
        decoded.forEach((path, val) {
          _folderStyles[path] = FolderStyle.fromJson(
            val as Map<String, dynamic>,
          );
        });
      } catch (e) {
        debugPrint('Error loading folder styles: $e');
      }
    }

    await refresh();
  }

  Future<void> refresh() async {
    final refreshEpoch = ++_refreshEpoch;
    _isLoading = true;
    notifyListeners();

    List<SharedFile> nextFiles = [];
    try {
      final hasSearchOrCategory =
          _searchQuery.trim().isNotEmpty || _categoryFilter != 'all';
      final useDashboardCategoryRoots =
          _isDashboardCategoryMode &&
          _categoryFilter != 'all' &&
          _searchQuery.trim().isEmpty;
      final shouldRunScopedSearch =
          useDashboardCategoryRoots ||
          (hasSearchOrCategory &&
              (_searchScope == 'all_files' ||
                  _searchScope == 'subfolders' ||
                  (_searchScope == 'all_drives' && Platform.isWindows)));

      if (shouldRunScopedSearch) {
        final roots = useDashboardCategoryRoots
            ? _resolveDashboardCategoryRoots()
            : _resolveSearchRoots();
        final includeDirectories = _categoryFilter == 'all';
        nextFiles = await _runScopedSearch(
          roots: roots,
          query: _searchQuery,
          includeDirectories: includeDirectories,
          categoryFilter: _categoryFilter,
          refreshEpoch: refreshEpoch,
          maxResults: useDashboardCategoryRoots ? 900 : 1500,
          maxScanDuration: useDashboardCategoryRoots
              ? const Duration(seconds: 5)
              : const Duration(seconds: 8),
        );
      } else {
        // Normal list loading
        List<SharedFile> rawList = [];
        if (Platform.isWindows && _currentPath == 'Computer') {
          rawList = _storageService.getWindowsDrives();
        } else {
          rawList = _storageService.listFiles(_currentPath);
        }

        if (!_showHiddenFiles) {
          rawList = rawList.where((file) => !_isHiddenPath(file.path)).toList();
        }

        // Apply local filter if query is not empty and scope is current
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          nextFiles = rawList
              .where(
                (file) =>
                    file.name.toLowerCase().contains(query) ||
                    file.path.toLowerCase().contains(query),
              )
              .toList();
        } else {
          nextFiles = rawList;
        }
      }

      if (_categoryFilter != 'all') {
        nextFiles = nextFiles
            .where((file) => _matchesCategory(file, _categoryFilter))
            .toList();
      }

      _sortFilesWithFoldersFirst(nextFiles);
    } catch (e) {
      debugPrint('Error loading files: $e');
      nextFiles = [];
    }

    if (refreshEpoch != _refreshEpoch) {
      return;
    }

    _files = nextFiles;
    _isLoading = false;
    notifyListeners();
  }

  List<String> _resolveSearchRoots() {
    if (_searchScope == 'subfolders') {
      if (_currentPath == 'Computer') {
        return Platform.isWindows
            ? [_resolveWindowsDefaultSearchRoot()]
            : [_storageService.rootPath];
      }
      return [_currentPath];
    }

    if (Platform.isWindows) {
      if (_selectedSearchDrive.isNotEmpty) {
        return [_selectedSearchDrive];
      }
      return [_resolveWindowsDefaultSearchRoot()];
    }

    return [_storageService.rootPath];
  }

  Future<List<SharedFile>> _runScopedSearch({
    required List<String> roots,
    required String query,
    required bool includeDirectories,
    required String categoryFilter,
    required int refreshEpoch,
    required int maxResults,
    required Duration maxScanDuration,
  }) async {
    final List<SharedFile> fileResults = [];
    final List<SharedFile> directoryResults = [];
    final normalizedQuery = query.toLowerCase();
    final startedAt = DateTime.now();
    var scannedCount = 0;

    for (final rootPath in roots) {
      final dir = Directory(rootPath);
      if (!dir.existsSync()) continue;

      try {
        await for (final entity
            in dir
                .list(recursive: true, followLinks: false)
                .handleError((_) {})) {
          if (refreshEpoch != _refreshEpoch) {
            return [];
          }

          scannedCount++;
          if (scannedCount % 250 == 0) {
            await Future<void>.delayed(Duration.zero);
          }

          if (DateTime.now().difference(startedAt) >= maxScanDuration) {
            break;
          }

          final entityPath = entity.path;
          final name = p.basename(entityPath).toLowerCase();
          final isDirectory = entity is Directory;
          if (!_showHiddenFiles && _isHiddenPath(entityPath)) {
            continue;
          }

          if (!_matchesSearchQueryRaw(name, entityPath, normalizedQuery)) {
            continue;
          }

          if (isDirectory) {
            if (includeDirectories) {
              directoryResults.add(
                SharedFile.fromPathLite(path: entityPath, isDirectory: true),
              );
            }
          } else {
            final fileItem = SharedFile.fromPathLite(
              path: entityPath,
              isDirectory: false,
            );
            if (categoryFilter == 'all' ||
                _matchesCategory(fileItem, categoryFilter)) {
              fileResults.add(fileItem);
            }
          }

          if (fileResults.length + directoryResults.length >= maxResults) {
            break;
          }
        }
      } catch (_) {}

      if (fileResults.length + directoryResults.length >= maxResults) {
        break;
      }
    }

    _sortFilesWithFoldersFirst(fileResults);
    _sortFilesWithFoldersFirst(directoryResults);
    return [...fileResults, ...directoryResults];
  }

  bool _matchesSearchQueryRaw(
    String nameLower,
    String pathRaw,
    String normalizedQuery,
  ) {
    if (normalizedQuery.isEmpty) {
      return true;
    }
    return nameLower.contains(normalizedQuery) ||
        pathRaw.toLowerCase().contains(normalizedQuery);
  }

  bool _isHiddenPath(String path) {
    final segments = p
        .split(p.normalize(path))
        .where((segment) => segment.isNotEmpty)
        .toList();
    return segments.any((segment) => segment.startsWith('.'));
  }

  void _sortFilesWithFoldersFirst(List<SharedFile> items) {
    items.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  // History Navigation Methods
  void goBack() {
    if (canGoBack) {
      _forwardStack.add(_currentPath);
      _currentPath = _backStack.removeLast();
      _searchQuery = '';
      clearSelection();
      refresh();
    }
  }

  void goForward() {
    if (canGoForward) {
      _backStack.add(_currentPath);
      _currentPath = _forwardStack.removeLast();
      _searchQuery = '';
      clearSelection();
      refresh();
    }
  }

  void navigateInto(String folderPath) {
    if (folderPath == _currentPath) return;

    if (_currentPath.isNotEmpty) {
      _backStack.add(_currentPath);
      _forwardStack.clear(); // Clear forward stack on new navigation
    }

    _currentPath = folderPath;
    _searchQuery = '';
    _categoryFilter = 'all';
    _searchScope = 'current';
    _selectedSearchDrive = '';
    _isDashboardCategoryMode = false;
    clearSelection();
    refresh();
  }

  void navigateUp() {
    if (Platform.isWindows) {
      if (_currentPath == 'Computer') {
        return;
      }
      final parentDir = Directory(_currentPath).parent;
      if (parentDir.path == _currentPath) {
        navigateInto('Computer');
        return;
      }
      navigateInto(parentDir.path);
      return;
    }

    if (_currentPath == _storageService.rootPath) {
      return;
    }
    final parentDir = Directory(_currentPath).parent;
    navigateInto(parentDir.path);
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    if (query.trim().isNotEmpty) {
      _isDashboardCategoryMode = false;
    }

    _searchDebounceTimer?.cancel();
    if (query.trim().isEmpty) {
      refresh();
      return;
    }

    _searchDebounceTimer = Timer(const Duration(milliseconds: 350), refresh);
  }

  void setSearchScope(String scope) {
    _searchScope = scope;
    _isDashboardCategoryMode = false;
    refresh();
  }

  void setCategoryFilter(String category) {
    _categoryFilter = category;
    if (category == 'all') {
      _isDashboardCategoryMode = false;
    }
    refresh();
  }

  void openCategoryFromDashboard(String category) {
    final targetPath = Platform.isWindows
        ? _resolveWindowsDefaultSearchRoot()
        : (Platform.isAndroid ? '/storage/emulated/0' : '/');

    _searchQuery = '';
    _categoryFilter = category;
    _searchScope = 'subfolders';
    _isDashboardCategoryMode = true;
    if (Platform.isWindows) {
      _selectedSearchDrive = _extractWindowsDrive(targetPath);
    } else {
      _selectedSearchDrive = '';
    }

    if (targetPath != _currentPath) {
      if (_currentPath.isNotEmpty) {
        _backStack.add(_currentPath);
        _forwardStack.clear();
      }
      _currentPath = targetPath;
    }

    _selectedPaths.clear();
    _isSelectionMode = false;
    refresh();
  }

  void resetExplorerToDefault({bool resetPath = false}) {
    _searchDebounceTimer?.cancel();
    _searchQuery = '';
    _categoryFilter = 'all';
    _searchScope = 'all_files';
    _selectedSearchDrive = '';
    _isDashboardCategoryMode = false;

    if (resetPath) {
      _currentPath = Platform.isWindows
          ? _resolveWindowsDefaultSearchRoot()
          : _storageService.rootPath;
      _backStack.clear();
      _forwardStack.clear();
    }

    _selectedPaths.clear();
    _isSelectionMode = false;
    refresh();
  }

  void setSelectedSearchDrive(String drive) {
    _selectedSearchDrive = drive;
    _isDashboardCategoryMode = false;
    if (_searchQuery.trim().isNotEmpty || _categoryFilter != 'all') {
      refresh();
    }
  }

  String _resolveWindowsDefaultSearchRoot() {
    final home = Platform.environment['USERPROFILE'];
    if (home != null && home.trim().isNotEmpty) {
      return home;
    }

    final drives = _storageService.getWindowsDrives();
    if (drives.isNotEmpty) {
      return drives.first.path;
    }
    return 'C:\\';
  }

  List<String> _resolveDashboardCategoryRoots() {
    if (Platform.isWindows) {
      final home = _resolveWindowsDefaultSearchRoot();
      final roots = <String>{
        home,
        p.join(home, 'Desktop'),
        p.join(home, 'Downloads'),
        p.join(home, 'Documents'),
        p.join(home, 'Pictures'),
        p.join(home, 'Videos'),
        p.join(home, 'Music'),
      };
      return roots.where((path) => Directory(path).existsSync()).toList();
    }

    if (Platform.isAndroid) {
      const roots = <String>[
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Documents',
        '/storage/emulated/0/Movies',
        '/storage/emulated/0/Music',
      ];
      final existingRoots = roots
          .where((path) => Directory(path).existsSync())
          .toList();
      if (existingRoots.isNotEmpty) {
        return existingRoots;
      }
    }

    return [_storageService.rootPath];
  }

  String _extractWindowsDrive(String path) {
    if (path.length >= 3 && path[1] == ':' && path[2] == '\\') {
      return path.substring(0, 3);
    }
    return '';
  }

  bool _matchesCategory(SharedFile file, String category) {
    final fileCategory = FileCategory.builtInById(category);
    if (fileCategory == null) return true;
    return fileCategory.matchesPath(file.path, isDirectory: file.isDirectory);
  }

  // Folder Customization Methods
  FolderStyle? getFolderStyle(String path) {
    return _folderStyles[path];
  }

  Future<void> updateFolderStyle(
    String path,
    String colorHex,
    String iconType,
  ) async {
    _folderStyles[path] = FolderStyle(colorHex: colorHex, iconType: iconType);
    await _saveFolderStyles();
    notifyListeners();
  }

  Future<void> clearFolderStyle(String path) async {
    if (_folderStyles.containsKey(path)) {
      _folderStyles.remove(path);
      await _saveFolderStyles();
      notifyListeners();
    }
  }

  Future<void> _saveFolderStyles() async {
    final Map<String, dynamic> serialized = {};
    _folderStyles.forEach((key, val) {
      serialized[key] = val.toJson();
    });
    await _prefs.setString(_keyFolderStyles, jsonEncode(serialized));
  }

  // Selection Mode Methods
  void toggleSelection(String path) {
    if (_selectedPaths.contains(path)) {
      _selectedPaths.remove(path);
    } else {
      _selectedPaths.add(path);
    }

    _isSelectionMode = _selectedPaths.isNotEmpty;
    notifyListeners();
  }

  void selectAll() {
    for (final file in files) {
      _selectedPaths.add(file.path);
    }
    _isSelectionMode = true;
    notifyListeners();
  }

  void clearSelection() {
    _selectedPaths.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  // Clipboard Methods
  void copySelected() {
    _clipboardPaths = List.from(_selectedPaths);
    _isCut = false;
    clearSelection();
  }

  void cutSelected() {
    _clipboardPaths = List.from(_selectedPaths);
    _isCut = true;
    clearSelection();
  }

  void clearClipboard() {
    _clipboardPaths.clear();
    _isCut = false;
    notifyListeners();
  }

  // Favorites Methods
  bool isFavorite(String path) {
    return _favoritePaths.contains(path);
  }

  Future<void> toggleFavorite(String path) async {
    if (_favoritePaths.contains(path)) {
      _favoritePaths.remove(path);
    } else {
      _favoritePaths.add(path);
    }
    notifyListeners();
    await _prefs.setStringList(_keyFavorites, _favoritePaths.toList());
  }

  Future<void> setShowHiddenFiles(bool value) async {
    _showHiddenFiles = value;
    await _prefs.setBool(_keyShowHiddenFiles, value);
    await refresh();
  }

  List<String> protectedFavoritePathsFor(Iterable<String> paths) {
    final blocked = <String>{};
    for (final targetPath in paths) {
      for (final favoritePath in _favoritePaths) {
        if (_isSameOrChildPath(favoritePath, targetPath)) {
          blocked.add(favoritePath);
        }
      }
    }
    return blocked.toList()..sort();
  }

  bool _isSameOrChildPath(String path, String parentPath) {
    final normalizedPath = p.normalize(path);
    final normalizedParent = p.normalize(parentPath);
    if (Platform.isWindows) {
      final lowerPath = normalizedPath.toLowerCase();
      final lowerParent = normalizedParent.toLowerCase();
      return lowerPath == lowerParent || p.isWithin(lowerParent, lowerPath);
    }
    return normalizedPath == normalizedParent ||
        p.isWithin(normalizedParent, normalizedPath);
  }

  // Create folder/file helper
  Future<void> createFolder(String folderName) async {
    await _storageService.createFolder(_currentPath, folderName);
    await refresh();
  }

  Future<void> createFile(String fileName) async {
    await _storageService.createFile(_currentPath, fileName);
    await refresh();
  }

  Future<void> checkAndRequestAndroidPermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        final result = await Permission.manageExternalStorage.request();
        if (result.isGranted) {
          await _storageService.refreshRootDirectory();
          _currentPath = _storageService.rootPath;
          await refresh();
        }
      } else {
        await _storageService.refreshRootDirectory();
        if (_currentPath.isEmpty ||
            _currentPath == '/' ||
            !_currentPath.startsWith('/storage/emulated/0')) {
          _currentPath = _storageService.rootPath;
          await refresh();
        }
      }
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    super.dispose();
  }
}
