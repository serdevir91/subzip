import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_state_provider.dart';
import '../providers/file_system_provider.dart';
import '../providers/task_provider.dart';
import '../models/shared_file.dart';
import '../services/age_signals_service.dart';
import '../services/review_service.dart';
import '../services/update_service.dart';
import 'widgets/file_tile.dart';
import 'widgets/breadcrumb_bar.dart';
import 'widgets/folder_style_dialog.dart';
import 'widgets/glass_panel.dart';
import 'widgets/app_notification_banner.dart';
import 'favorites_screen.dart';
import 'tasks_screen.dart';
import 'settings_screen.dart';
import 'zip_viewer_screen.dart';
import 'dashboard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _keyNeverShowRatePrompt = 'never_show_rate_prompt';
  static const String _keyRatePromptLaunchCount = 'rate_prompt_launch_count';
  static const String _keyFirstUseEpochMs = 'first_use_epoch_ms';
  static const String _keyLastRatePromptEpochMs = 'last_rate_prompt_epoch_ms';
  static const int _minLaunchesBeforeRatePrompt = 4;
  static const Duration _minUsageBeforeRatePrompt = Duration(minutes: 10);
  static const Duration _ratePromptCooldown = Duration(days: 14);

  int _currentNavIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  bool _showSearchFilters = false;
  bool _isPathEditing = false;
  final TextEditingController _pathController = TextEditingController();
  bool _startupPromptsHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupFlow();
    });
  }

  Future<void> _runStartupFlow() async {
    await _checkAndRequestPermissionsSequence();
    await _handleStartupPrompts();
  }

  Future<void> _checkAndRequestPermissionsSequence() async {
    if (!Platform.isAndroid) return;

    final fileSystem = Provider.of<FileSystemProvider>(context, listen: false);

    // 1. Request notification permission (Android 13+)
    final notificationStatus = await Permission.notification.status;
    if (!notificationStatus.isGranted) {
      await Permission.notification.request();
    }

    // 1.5. Request Android 13+ media permissions on first open
    await [Permission.photos, Permission.videos, Permission.audio].request();

    // 2. Request storage permission (Manage All Files)
    bool hasStoragePermission =
        await Permission.manageExternalStorage.isGranted;

    while (!hasStoragePermission) {
      if (!mounted) return;
      // Show explanation dialog
      final shouldRequest = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Permission Required'),
          content: const Text(
            'SubZip is a file manager and archive utility. It requires "All Files Access" to list, copy, compress, and convert files on your device.\n\nWithout this permission, the app cannot be used. Please grant permission to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => exit(0),
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
              child: const Text('Exit App'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      );

      if (shouldRequest == true) {
        final result = await Permission.manageExternalStorage.request();
        if (result.isGranted) {
          hasStoragePermission = true;
          break;
        }
      }

      // If they requested but it is still not granted (denied or open settings required)
      hasStoragePermission = await Permission.manageExternalStorage.isGranted;
      if (!hasStoragePermission) {
        if (!mounted) return;
        // Show blocking "Cannot be used" popup
        final openSettings = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Access Denied'),
            content: const Text(
              'The app cannot be used without storage access. To use SubZip, enable "Allow access to manage all files" in system settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => exit(0),
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
                child: const Text('Exit App'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );

        if (openSettings == true) {
          await openAppSettings();
        } else {
          exit(0);
        }
      }

      await Future.delayed(const Duration(milliseconds: 1000));
      hasStoragePermission = await Permission.manageExternalStorage.isGranted;
    }

    await fileSystem.checkAndRequestAndroidPermissions();
  }

  Future<void> _handleStartupPrompts() async {
    if (_startupPromptsHandled || !mounted) {
      return;
    }
    _startupPromptsHandled = true;

    if (!Platform.isAndroid) {
      return;
    }

    await Future.delayed(const Duration(milliseconds: 350));
    final ageGateShown = await _showAgeGateIfNeeded();
    if (!mounted || ageGateShown) return;
    final updateShown = await _showUpdateDialogIfNeeded();
    if (!mounted || updateShown) return;
    await _showRateAppDialogIfNeeded();
  }

  Future<bool> _showAgeGateIfNeeded() async {
    try {
      final ageSignals = await AgeSignalsService().checkAndCacheAgeSignals();
      if (!mounted || ageSignals == null || !ageSignals.isAccessDenied) {
        return false;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Access Not Approved'),
          content: const Text(
            'This Google account is not approved to use SubZip right now.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Age signals check failed: $e');
      return false;
    }
  }

  Future<bool> _showUpdateDialogIfNeeded() async {
    try {
      final updateService = UpdateService();
      final status = await updateService.checkForUpdate();
      if (!mounted ||
          status == null ||
          !status.storeVersionAvailable ||
          !status.canUpdate) {
        return false;
      }

      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update Available'),
          content: Text(
            'A newer version is available on Google Play.\n\nCurrent: ${status.localVersion}\nLatest: ${status.storeVersion}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Update'),
            ),
          ],
        ),
      );
      if (shouldUpdate == true) {
        final opened = await updateService.openUpdatePage(status);
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Update page could not be opened.')),
          );
        }
      }
      return true;
    } catch (e) {
      debugPrint('Update check failed: $e');
      return false;
    }
  }

  Future<void> _showRateAppDialogIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final launchCount = (prefs.getInt(_keyRatePromptLaunchCount) ?? 0) + 1;
    await prefs.setInt(_keyRatePromptLaunchCount, launchCount);

    final firstUseEpochMs =
        prefs.getInt(_keyFirstUseEpochMs) ?? now.millisecondsSinceEpoch;
    if (!prefs.containsKey(_keyFirstUseEpochMs)) {
      await prefs.setInt(_keyFirstUseEpochMs, firstUseEpochMs);
    }

    final neverShowPrompt = prefs.getBool(_keyNeverShowRatePrompt) ?? false;
    if (neverShowPrompt || !mounted) {
      return;
    }

    if (launchCount < _minLaunchesBeforeRatePrompt) {
      return;
    }

    final firstUse = DateTime.fromMillisecondsSinceEpoch(firstUseEpochMs);
    if (now.difference(firstUse) < _minUsageBeforeRatePrompt) {
      return;
    }

    final lastPromptEpochMs = prefs.getInt(_keyLastRatePromptEpochMs);
    if (lastPromptEpochMs != null) {
      final lastPrompt = DateTime.fromMillisecondsSinceEpoch(lastPromptEpochMs);
      if (now.difference(lastPrompt) < _ratePromptCooldown) {
        return;
      }
    }

    await prefs.setInt(_keyLastRatePromptEpochMs, now.millisecondsSinceEpoch);
    if (!mounted) {
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rate SubZip'),
        content: const Text(
          'If SubZip is helping you, please leave a rating and short review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'later'),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'never'),
            child: const Text('Don\'t ask again'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'rate'),
            child: const Text('Rate & Review'),
          ),
        ],
      ),
    );

    if (action == 'never') {
      await prefs.setBool(_keyNeverShowRatePrompt, true);
      return;
    }

    if (action == 'rate') {
      try {
        final reviewService = ReviewService();
        final requested = await reviewService.requestInAppReview();
        if (requested) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Review prompt requested. It can appear again later if you did not submit a review.',
                ),
                action: SnackBarAction(
                  label: 'Open Store',
                  onPressed: () {
                    reviewService.openStoreReviewPage();
                  },
                ),
              ),
            );
          }
        } else if (mounted) {
          final opened = await reviewService.openStoreReviewPage();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                opened
                    ? 'Opened Play Store review page.'
                    : 'Review is not available right now.',
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('Rate prompt failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  void _showCreateFolderDialog(
    BuildContext context,
    FileSystemProvider fileSystem,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create New Folder'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Folder Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  await fileSystem.createFolder(name);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  void _showCreateFileDialog(
    BuildContext context,
    FileSystemProvider fileSystem,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create New File'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'File Name (e.g. note.txt)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  await fileSystem.createFile(name);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  void _showRenameDialog(
    BuildContext context,
    FileSystemProvider fileSystem,
    SharedFile file,
  ) {
    final controller = TextEditingController(text: file.name);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'New Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty && name != file.name) {
                  final newPath = p.join(p.dirname(file.path), name);
                  final fileEntity = File(file.path);
                  final dirEntity = Directory(file.path);
                  if (file.isDirectory) {
                    await dirEntity.rename(newPath);
                  } else {
                    await fileEntity.rename(newPath);
                  }
                  await fileSystem.refresh();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
  }

  void _showZipDialog(
    BuildContext context,
    FileSystemProvider fileSystem,
    TaskProvider taskProvider,
    List<String> paths,
  ) {
    final controller = TextEditingController(
      text: paths.length == 1
          ? '${p.basenameWithoutExtension(paths[0])}.zip'
          : 'archive.zip',
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Compress to ZIP Archive'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Archive Filename'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final targetZip = p.join(fileSystem.currentPath, name);
                  taskProvider.startCompressTask(paths, targetZip, fileSystem);
                  Navigator.pop(context);
                  fileSystem.clearSelection();

                  Provider.of<AppStateProvider>(context, listen: false)
                      .showBannerNotification('ZIP compression task started in background.');
                }
              },
              child: const Text('Compress'),
            ),
          ],
        );
      },
    );
  }

  void _showFolderStyleDialog(
    BuildContext context,
    FileSystemProvider fileSystem,
    String folderPath,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return FolderStyleDialog(
          folderPath: folderPath,
          currentStyle: fileSystem.getFolderStyle(folderPath),
          onSave: (colorHex, iconType) {
            fileSystem.updateFolderStyle(folderPath, colorHex, iconType);
          },
          onClear: () {
            fileSystem.clearFolderStyle(folderPath);
          },
        );
      },
    );
  }

  void _handleFileTap(
    BuildContext context,
    SharedFile file,
    FileSystemProvider fileSystem,
    TaskProvider taskProvider,
  ) async {
    if (fileSystem.isSelectionMode) {
      fileSystem.toggleSelection(file.path);
      return;
    }

    if (file.isDirectory) {
      fileSystem.navigateInto(file.path);
    } else {
      final ext = p.extension(file.path).toLowerCase();
      if (ext == '.zip') {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ZIP Archive'),
            content: Text('What would you like to do with ${file.name}?'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  OpenFilex.open(file.path);
                },
                child: const Text('Open in OS'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ZipViewerScreen(
                        zipPath: file.path,
                        currentExplorerPath: fileSystem.currentPath,
                      ),
                    ),
                  );
                },
                child: const Text('Browse Contents'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  final baseName = p.basenameWithoutExtension(file.path);
                  final targetDir = p.join(fileSystem.currentPath, baseName);
                  taskProvider.startExtractTask(
                    file.path,
                    targetDir,
                    fileSystem,
                  );
                  Provider.of<AppStateProvider>(context, listen: false)
                      .showBannerNotification('ZIP extraction started in background.');
                },
                child: const Text('Extract here'),
              ),
            ],
          ),
        );
      } else {
        await OpenFilex.open(file.path);
      }
    }
  }

  void _navigatePath(String pathStr, FileSystemProvider fileSystem) async {
    final cleanPath = pathStr.trim();
    if (cleanPath.isEmpty) return;

    if (cleanPath == 'Computer' || cleanPath == 'computer') {
      fileSystem.navigateInto('Computer');
      setState(() {
        _isPathEditing = false;
      });
      return;
    }

    final dir = Directory(cleanPath);
    if (await dir.exists()) {
      fileSystem.navigateInto(cleanPath);
      setState(() {
        _isPathEditing = false;
      });
    } else {
      if (mounted) {
        Provider.of<AppStateProvider>(context, listen: false)
            .showBannerNotification('Directory does not exist: $cleanPath', isError: true);
      }
    }
  }

  Widget _buildExplorerTab(
    BuildContext context,
    FileSystemProvider fileSystem,
    TaskProvider taskProvider,
    AppStateProvider appState,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final List<SharedFile> drives = Platform.isWindows
        ? fileSystem.getWindowsDrives()
        : [];

    return Column(
      children: [
        // Search & Filter Panel
        if (!fileSystem.isSelectionMode) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: fileSystem.setSearchQuery,
                    decoration: InputDecoration(
                      hintText: 'Search files and folders...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                fileSystem.setSearchQuery('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E1E1E)
                          : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0x0EFFFFFF)
                              : Colors.grey.shade300,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0x0EFFFFFF)
                              : Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: appState.accentColor,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.filter_list_rounded,
                    color: _showSearchFilters
                        ? appState.accentColor
                        : theme.colorScheme.outline,
                  ),
                  tooltip: 'Search Filters',
                  style: IconButton.styleFrom(
                    backgroundColor: _showSearchFilters
                        ? appState.accentColor.withValues(alpha: 0.12)
                        : (isDark
                              ? const Color(0xFF1E1E1E)
                              : Colors.grey.shade100),
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _showSearchFilters = !_showSearchFilters;
                    });
                  },
                ),
              ],
            ),
          ),

          // Search Filters Collapsible Panel
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _showSearchFilters ? (Platform.isWindows ? 115 : 65) : 0,
            curve: Curves.easeInOut,
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Scope:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: fileSystem.searchScope,
                          underline: const SizedBox(),
                          borderRadius: BorderRadius.circular(12),
                          onChanged: (val) {
                            if (val != null) {
                              fileSystem.setSearchScope(val);
                            }
                          },
                          items: [
                            const DropdownMenuItem(
                              value: 'all_files',
                              child: Text(
                                'All Files (Default)',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            const DropdownMenuItem(
                              value: 'current',
                              child: Text(
                                'Current Folder Only',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            const DropdownMenuItem(
                              value: 'subfolders',
                              child: Text(
                                'Include Subfolders (Recursive)',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (Platform.isWindows) ...[
                      Row(
                        children: [
                          const Text(
                            'Target Disk:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 12),
                          DropdownButton<String>(
                            value: fileSystem.selectedSearchDrive.isEmpty
                                ? null
                                : fileSystem.selectedSearchDrive,
                            hint: const Text(
                              'Current Disk',
                              style: TextStyle(fontSize: 13),
                            ),
                            underline: const SizedBox(),
                            borderRadius: BorderRadius.circular(12),
                            onChanged: (val) {
                              fileSystem.setSelectedSearchDrive(val ?? '');
                            },
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text(
                                  'Current Disk',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                              ...drives.map(
                                (d) => DropdownMenuItem<String>(
                                  value: d.path,
                                  child: Text(
                                    d.name,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                    const Divider(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],

        // Navigation History Bar + Breadcrumbs
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              // Back Button
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                tooltip: 'Back',
                onPressed: fileSystem.canGoBack ? fileSystem.goBack : null,
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
              ),
              // Forward Button
              IconButton(
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                tooltip: 'Forward',
                onPressed: fileSystem.canGoForward
                    ? fileSystem.goForward
                    : null,
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
              ),
              // Parent Directory (Up) Button
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                tooltip: 'Go Up',
                onPressed:
                    fileSystem.currentPath != 'Computer' &&
                        fileSystem.currentPath != '/' &&
                        fileSystem.currentPath !=
                            fileSystem
                                .getWindowsDrives()
                                .firstOrNull
                                ?.path // Prevent loop if at C:\
                    ? fileSystem.navigateUp
                    : null,
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
              ),
              const SizedBox(width: 6),
              // Breadcrumbs / Editable Path Bar
              if (_isPathEditing) ...[
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Enter path...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E1E1E)
                          : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0x0EFFFFFF)
                              : Colors.grey.shade300,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0x0EFFFFFF)
                              : Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: appState.accentColor,
                          width: 2,
                        ),
                      ),
                    ),
                    onSubmitted: (value) => _navigatePath(value, fileSystem),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  tooltip: 'Copy path',
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: _pathController.text),
                    );
                    appState.showBannerNotification('Path copied to clipboard.');
                  },
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: Colors.green,
                  ),
                  tooltip: 'Go',
                  onPressed: () =>
                      _navigatePath(_pathController.text, fileSystem),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Colors.redAccent,
                  ),
                  tooltip: 'Cancel',
                  onPressed: () {
                    setState(() {
                      _isPathEditing = false;
                    });
                  },
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: GestureDetector(
                    onDoubleTap: () {
                      setState(() {
                        _isPathEditing = true;
                        _pathController.text = fileSystem.currentPath;
                      });
                    },
                    child: BreadcrumbBar(
                      currentPath: fileSystem.currentPath,
                      rootPath: Platform.isWindows
                          ? 'Computer'
                          : fileSystem.currentPath,
                      onNavigate: fileSystem.navigateInto,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  tooltip: 'Edit path',
                  onPressed: () {
                    setState(() {
                      _isPathEditing = true;
                      _pathController.text = fileSystem.currentPath;
                    });
                  },
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
                  ),
                ),
              ],
            ],
          ),
        ),

        // File Explorer Grid/List (Responsive Width & Height)
        Expanded(
          child: fileSystem.isLoading
              ? const Center(child: CircularProgressIndicator())
              : fileSystem.files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open_rounded,
                        size: 64,
                        color: theme.colorScheme.outline.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No items found.',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : appState.isGridView
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculate column counts responsively
                    int crossAxisCount = (constraints.maxWidth / 110)
                        .floor()
                        .clamp(3, 10);
                    double childAspectRatio = 0.9;

                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: childAspectRatio,
                      ),
                      itemCount: fileSystem.files.length,
                      itemBuilder: (context, index) {
                        final file = fileSystem.files[index];
                        final isSelected = fileSystem.selectedPaths.contains(
                          file.path,
                        );

                        return FileTile(
                          file: file,
                          isSelected: isSelected,
                          isSelectionMode: fileSystem.isSelectionMode,
                          folderStyle: fileSystem.getFolderStyle(file.path),
                          isFavorite: fileSystem.isFavorite(file.path),
                          isGridView: true,
                          onTap: () => _handleFileTap(
                            context,
                            file,
                            fileSystem,
                            taskProvider,
                          ),
                          onLongPress: () =>
                              fileSystem.toggleSelection(file.path),
                          onActionSelected: (action) => _handleFileAction(
                            context,
                            fileSystem,
                            taskProvider,
                            file,
                            action,
                          ),
                        );
                      },
                    );
                  },
                )
              : ListView.builder(
                  itemCount: fileSystem.files.length,
                  itemBuilder: (context, index) {
                    final file = fileSystem.files[index];
                    final isSelected = fileSystem.selectedPaths.contains(
                      file.path,
                    );

                    return FileTile(
                      file: file,
                      isSelected: isSelected,
                      isSelectionMode: fileSystem.isSelectionMode,
                      folderStyle: fileSystem.getFolderStyle(file.path),
                      isFavorite: fileSystem.isFavorite(file.path),
                      isGridView: false,
                      onTap: () => _handleFileTap(
                        context,
                        file,
                        fileSystem,
                        taskProvider,
                      ),
                      onLongPress: () => fileSystem.toggleSelection(file.path),
                      onActionSelected: (action) => _handleFileAction(
                        context,
                        fileSystem,
                        taskProvider,
                        file,
                        action,
                      ),
                    );
                  },
                ),
        ),

        // Clipboard Floating Bar
        if (fileSystem.hasClipboardItems)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: appState.accentColor.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  fileSystem.isCut ? Icons.cut_rounded : Icons.copy_rounded,
                  color: appState.accentColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${fileSystem.clipboardPaths.length} items',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: fileSystem.clearClipboard,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appState.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    if (fileSystem.isCut) {
                      if (_blockedByFavoriteProtection(
                        context,
                        fileSystem,
                        fileSystem.clipboardPaths,
                      )) {
                        return;
                      }
                      taskProvider.startMoveTask(
                        fileSystem.clipboardPaths,
                        fileSystem.currentPath,
                        fileSystem,
                      );
                    } else {
                      taskProvider.startCopyTask(
                        fileSystem.clipboardPaths,
                        fileSystem.currentPath,
                        fileSystem,
                      );
                    }
                    fileSystem.clearClipboard();
                    appState.showBannerNotification(
                      fileSystem.isCut
                          ? 'Move task started in background.'
                          : 'Copy task started in background.',
                    );
                  },
                  child: const Text(
                    'Paste',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

        // Ongoing Active Tasks Quick Indicator
        if (taskProvider.activeTasks.isNotEmpty)
          GestureDetector(
            onTap: () {
              setState(() {
                _currentNavIndex = 2; // Jump to Operations tab
              });
            },
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: GlassPanel(
                borderRadius: 16,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                borderColor: appState.accentColor.withValues(alpha: 0.3),
                fillColor: appState.accentColor.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        value: taskProvider.activeTasks.first.progress,
                        strokeWidth: 3,
                        color: appState.accentColor,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${taskProvider.activeTasks.length} running tasks: ${taskProvider.activeTasks.first.name}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: appState.accentColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: appState.accentColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _handleFileAction(
    BuildContext context,
    FileSystemProvider fileSystem,
    TaskProvider taskProvider,
    SharedFile file,
    String action,
  ) {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    switch (action) {
      case 'style':
        _showFolderStyleDialog(context, fileSystem, file.path);
        break;
      case 'favorite':
        fileSystem.toggleFavorite(file.path);
        break;
      case 'share':
        appState.sharePaths(context, [file.path]);
        break;
      case 'extract':
        final baseName = p.basenameWithoutExtension(file.path);
        final targetDir = p.join(fileSystem.currentPath, baseName);
        taskProvider.startExtractTask(file.path, targetDir, fileSystem);
        appState.showBannerNotification('Extraction task started in background.');
        break;
      case 'copy':
        fileSystem.toggleSelection(file.path);
        fileSystem.copySelected();
        break;
      case 'cut':
        if (_blockedByFavoriteProtection(context, fileSystem, [file.path])) {
          break;
        }
        fileSystem.toggleSelection(file.path);
        fileSystem.cutSelected();
        break;
      case 'rename':
        _showRenameDialog(context, fileSystem, file);
        break;
      case 'select':
        fileSystem.toggleSelection(file.path);
        break;
      case 'delete':
        if (_blockedByFavoriteProtection(context, fileSystem, [file.path])) {
          break;
        }
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(file.isDirectory ? 'Delete Folder' : 'Delete File'),
            content: Text('Are you sure you want to delete ${file.name}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () {
                  taskProvider.startDeleteTask([file.path], fileSystem);
                  Navigator.pop(context);
                  appState.showBannerNotification('Deletion task started in background.');
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
        break;
      case 'compress':
        _showZipDialog(context, fileSystem, taskProvider, [file.path]);
        break;
      case 'convert_pdf':
        final ext = p.extension(file.path).toLowerCase();
        String type = 'image_to_pdf';
        if (ext == '.docx') {
          type = 'docx_to_pdf';
        } else if (ext == '.pptx') {
          type = 'pptx_to_pdf';
        }
        final dir = p.dirname(file.path);
        final baseName = p.basenameWithoutExtension(file.path);
        final outputPath = p.join(dir, '$baseName-converted.pdf');
        taskProvider.startConversionTask(
          file.path,
          outputPath,
          type,
          fileSystem,
        );
        appState.showBannerNotification('PDF conversion task started in background.');
        break;
      case 'convert_word':
        final dir = p.dirname(file.path);
        final baseName = p.basenameWithoutExtension(file.path);
        final outputPath = p.join(dir, '$baseName-converted.docx');
        taskProvider.startConversionTask(
          file.path,
          outputPath,
          'pdf_to_docx',
          fileSystem,
        );
        appState.showBannerNotification('Word conversion task started in background.');
        break;
    }
  }

  bool _blockedByFavoriteProtection(
    BuildContext context,
    FileSystemProvider fileSystem,
    Iterable<String> paths,
  ) {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    if (!appState.protectFavoritesFromDelete) return false;

    final blockedPaths = fileSystem.protectedFavoritePathsFor(paths);
    if (blockedPaths.isEmpty) return false;

    final blockedName = p.basename(blockedPaths.first);
    final message = blockedPaths.length == 1
        ? '$blockedName is protected because it is in Favorites.'
        : '${blockedPaths.length} favorite items are protected from deletion.';
    appState.showBannerNotification(message, isError: true);
    return true;
  }

  Future<void> _addCurrentFolderCategory(
    BuildContext context,
    FileSystemProvider fileSystem,
    AppStateProvider appState,
  ) async {
    final currentPath = fileSystem.currentPath;
    if (currentPath.trim().isEmpty ||
        currentPath == 'Computer' ||
        !Directory(currentPath).existsSync()) {
      appState.showBannerNotification('Current location cannot be added.', isError: true);
      return;
    }

    final defaultName = p.basename(currentPath).trim().isEmpty
        ? currentPath
        : p.basename(currentPath);
    await appState.addFolderCategory(
      label: defaultName,
      folderPath: currentPath,
    );
    if (!mounted) return;
    appState.showBannerNotification('$defaultName added to categories.');
  }

  @override
  Widget build(BuildContext context) {
    final fileSystem = Provider.of<FileSystemProvider>(context);
    final taskProvider = Provider.of<TaskProvider>(context);
    final appState = Provider.of<AppStateProvider>(context);

    // Body content selection based on navigation
    Widget bodyContent;
    switch (_currentNavIndex) {
      case 0:
        bodyContent = DashboardScreen(
          onNavigateToFolder: (path) {
            if (path.trim().isEmpty) return;
            fileSystem.setCategoryFilter('all');
            fileSystem.navigateInto(path);
            setState(() {
              _currentNavIndex = 1; // Go to explorer tab
            });
          },
          onOpenCategory: (category) {
            _searchController.clear();
            fileSystem.openCategoryFromDashboard(category);
            setState(() {
              _currentNavIndex = 1;
            });
          },
        );
        break;
      case 1:
        bodyContent = _buildExplorerTab(
          context,
          fileSystem,
          taskProvider,
          appState,
        );
        break;
      case 2:
        bodyContent = FavoritesScreen(
          onNavigateToFolder: (path) {
            fileSystem.navigateInto(path);
            setState(() {
              _currentNavIndex = 1; // Go to explorer tab
            });
          },
        );
        break;
      case 3:
        bodyContent = TasksScreen(
          onNavigateToFolder: (path) {
            fileSystem.navigateInto(path);
            setState(() {
              _currentNavIndex = 1; // Go to explorer tab
            });
          },
        );
        break;
      default:
        bodyContent = DashboardScreen(
          onNavigateToFolder: (path) {
            if (path.trim().isEmpty) return;
            fileSystem.setCategoryFilter('all');
            fileSystem.navigateInto(path);
            setState(() {
              _currentNavIndex = 1; // Go to explorer tab
            });
          },
          onOpenCategory: (category) {
            _searchController.clear();
            fileSystem.openCategoryFromDashboard(category);
            setState(() {
              _currentNavIndex = 1;
            });
          },
        );
    }

    return Scaffold(
      appBar: fileSystem.isSelectionMode
          ? AppBar(
              backgroundColor: appState.accentColor.withValues(alpha: 0.12),
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Cancel selection',
                onPressed: fileSystem.clearSelection,
              ),
              title: Text(
                '${fileSystem.selectedPaths.length} selected',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: appState.accentColor,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all_rounded),
                  tooltip: 'Select All',
                  onPressed: fileSystem.selectAll,
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  tooltip: 'Copy',
                  onPressed: () {
                    fileSystem.copySelected();
                    appState.showBannerNotification('Items copied to clipboard.');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.cut_rounded),
                  tooltip: 'Cut',
                  onPressed: () {
                    if (_blockedByFavoriteProtection(
                      context,
                      fileSystem,
                      fileSystem.selectedPaths,
                    )) {
                      return;
                    }
                    fileSystem.cutSelected();
                    appState.showBannerNotification('Items cut to clipboard.');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.share_rounded),
                  tooltip: 'Share',
                  onPressed: () {
                    final selected = fileSystem.selectedPaths.toList();
                    fileSystem.clearSelection();
                    appState.sharePaths(context, selected);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.archive_rounded),
                  tooltip: 'Compress (ZIP)',
                  onPressed: () => _showZipDialog(
                    context,
                    fileSystem,
                    taskProvider,
                    fileSystem.selectedPaths.toList(),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_rounded,
                    color: Colors.redAccent,
                  ),
                  tooltip: 'Delete',
                  onPressed: () {
                    if (_blockedByFavoriteProtection(
                      context,
                      fileSystem,
                      fileSystem.selectedPaths,
                    )) {
                      return;
                    }
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Items'),
                        content: Text(
                          '${fileSystem.selectedPaths.length} items will be permanently deleted. Are you sure?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                            ),
                            onPressed: () {
                              taskProvider.startDeleteTask(
                                fileSystem.selectedPaths.toList(),
                                fileSystem,
                              );
                              Navigator.pop(context);
                              fileSystem.clearSelection();
                              appState.showBannerNotification('Deletion task started.');
                            },
                            child: const Text(
                              'Delete',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            )
          : AppBar(
              title: Row(
                children: [
                  Icon(
                    _currentNavIndex == 0
                        ? Icons.dashboard_rounded
                        : _currentNavIndex == 1
                        ? Icons.folder_zip_rounded
                        : _currentNavIndex == 2
                        ? Icons.star_rounded
                        : Icons.task_rounded,
                    color: appState.accentColor,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _currentNavIndex == 0
                        ? 'SubZip'
                        : _currentNavIndex == 1
                        ? 'Files'
                        : _currentNavIndex == 2
                        ? 'Favorites'
                        : 'Operations',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              actions: [
                if (_currentNavIndex == 1) ...[
                  IconButton(
                    icon: Icon(
                      appState.isGridView
                          ? Icons.view_list_rounded
                          : Icons.grid_view_rounded,
                    ),
                    tooltip: appState.isGridView ? 'List View' : 'Grid View',
                    onPressed: appState.toggleLayout,
                  ),
                  IconButton(
                    icon: const Icon(Icons.create_new_folder_rounded),
                    tooltip: 'New Folder',
                    onPressed: () =>
                        _showCreateFolderDialog(context, fileSystem),
                  ),
                  IconButton(
                    icon: const Icon(Icons.note_add_rounded),
                    tooltip: 'New File',
                    onPressed: () => _showCreateFileDialog(context, fileSystem),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_to_photos_rounded),
                    tooltip: 'Add current folder to categories',
                    onPressed: () => _addCurrentFolderCategory(
                      context,
                      fileSystem,
                      appState,
                    ),
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.settings_rounded),
                  tooltip: 'Settings',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
      body: Column(
        children: [
          const AppNotificationBanner(),
          Expanded(child: bodyContent),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentNavIndex,
        onDestinationSelected: (index) {
          final fileSystem = Provider.of<FileSystemProvider>(
            context,
            listen: false,
          );
          if (index == 1) {
            _searchController.clear();
            fileSystem.resetExplorerToDefault(resetPath: true);
          }
          setState(() {
            _currentNavIndex = index;
          });
        },
        indicatorColor: appState.accentColor.withValues(alpha: 0.2),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.folder_rounded),
            label: 'Files',
          ),
          const NavigationDestination(
            icon: Icon(Icons.star_rounded),
            label: 'Favorites',
          ),
          NavigationDestination(
            icon: Badge(
              label: Text(taskProvider.activeTasks.length.toString()),
              isLabelVisible: taskProvider.activeTasks.isNotEmpty,
              backgroundColor: appState.accentColor,
              child: const Icon(Icons.task_rounded),
            ),
            label: 'Operations',
          ),
        ],
      ),
    );
  }
}
