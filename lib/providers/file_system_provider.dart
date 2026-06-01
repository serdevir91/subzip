import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shared_file.dart';
import '../models/folder_style.dart';
import '../services/storage_service.dart';

class FileSystemProvider extends ChangeNotifier {
  static const String _keyFavorites = 'favorites';
  static const String _keyFolderStyles = 'folder_styles';

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

  // Custom Folder Styles
  final Map<String, FolderStyle> _folderStyles = {};

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
    _isLoading = true;
    notifyListeners();

    try {
      final hasSearchOrCategory =
          _searchQuery.trim().isNotEmpty || _categoryFilter != 'all';
      final shouldRunScopedSearch =
          hasSearchOrCategory &&
          (_searchScope == 'all_files' ||
              _searchScope == 'subfolders' ||
              (_searchScope == 'all_drives' && Platform.isWindows));

      if (shouldRunScopedSearch) {
        final roots = _resolveSearchRoots();
        final includeDirectories = _categoryFilter == 'all';
        _files = await _runScopedSearch(
          roots: roots,
          query: _searchQuery,
          includeDirectories: includeDirectories,
          categoryFilter: _categoryFilter,
        );
      } else {
        // Normal list loading
        List<SharedFile> rawList = [];
        if (Platform.isWindows && _currentPath == 'Computer') {
          rawList = _storageService.getWindowsDrives();
        } else {
          rawList = _storageService.listFiles(_currentPath);
        }

        // Apply local filter if query is not empty and scope is current
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          _files = rawList
              .where(
                (file) =>
                    file.name.toLowerCase().contains(query) ||
                    file.path.toLowerCase().contains(query),
              )
              .toList();
        } else {
          _files = rawList;
        }
      }

      if (_categoryFilter != 'all') {
        _files = _files
            .where((file) => _matchesCategory(file, _categoryFilter))
            .toList();
      }

      _sortFilesWithFoldersFirst(_files);
    } catch (e) {
      debugPrint('Error loading files: $e');
      _files = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  List<String> _resolveSearchRoots() {
    if (_searchScope == 'subfolders') {
      if (_currentPath == 'Computer') {
        return _storageService.getWindowsDrives().map((d) => d.path).toList();
      }
      return [_currentPath];
    }

    if (Platform.isWindows) {
      if (_selectedSearchDrive.isNotEmpty) {
        return [_selectedSearchDrive];
      }
      return _storageService.getWindowsDrives().map((d) => d.path).toList();
    }

    return [_storageService.rootPath];
  }

  Future<List<SharedFile>> _runScopedSearch({
    required List<String> roots,
    required String query,
    required bool includeDirectories,
    required String categoryFilter,
  }) async {
    final List<SharedFile> fileResults = [];
    final List<SharedFile> directoryResults = [];
    final normalizedQuery = query.toLowerCase();
    const maxResults = 1500;

    for (final rootPath in roots) {
      final dir = Directory(rootPath);
      if (!dir.existsSync()) continue;

      try {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          final item = SharedFile.fromFileSystemEntity(entity);

          if (!_matchesSearchQuery(item, normalizedQuery)) {
            continue;
          }

          if (item.isDirectory) {
            if (includeDirectories) {
              directoryResults.add(item);
            }
          } else {
            if (categoryFilter == 'all' ||
                _matchesCategory(item, categoryFilter)) {
              fileResults.add(item);
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

  bool _matchesSearchQuery(SharedFile item, String normalizedQuery) {
    if (normalizedQuery.isEmpty) {
      return true;
    }
    final name = item.name.toLowerCase();
    final itemPath = item.path.toLowerCase();
    return name.contains(normalizedQuery) || itemPath.contains(normalizedQuery);
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
    refresh();
  }

  void setSearchScope(String scope) {
    _searchScope = scope;
    refresh();
  }

  void setCategoryFilter(String category) {
    _categoryFilter = category;
    refresh();
  }

  void setSelectedSearchDrive(String drive) {
    _selectedSearchDrive = drive;
    if (_selectedSearchDrive.isNotEmpty) {
      navigateInto(_selectedSearchDrive);
    }
  }

  bool _matchesCategory(SharedFile file, String category) {
    if (file.isDirectory) return false;
    final ext = p.extension(file.path).toLowerCase();

    switch (category) {
      case 'images':
        return const {
          '.jpg',
          '.jpeg',
          '.png',
          '.gif',
          '.bmp',
          '.webp',
          '.heic',
        }.contains(ext);
      case 'videos':
        return const {
          '.mp4',
          '.mkv',
          '.avi',
          '.mov',
          '.webm',
          '.3gp',
        }.contains(ext);
      case 'audio':
        return const {
          '.mp3',
          '.wav',
          '.ogg',
          '.m4a',
          '.flac',
          '.aac',
        }.contains(ext);
      case 'documents':
        return const {
          '.pdf',
          '.doc',
          '.docx',
          '.xls',
          '.xlsx',
          '.ppt',
          '.pptx',
          '.txt',
          '.rtf',
          '.csv',
        }.contains(ext);
      case 'apk':
        return const {'.apk', '.xapk', '.apks'}.contains(ext);
      default:
        return true;
    }
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
}
