import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_category.dart';
import '../providers/app_state_provider.dart';
import '../providers/file_system_provider.dart';
import '../services/review_service.dart';
import '../services/update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _keyHasRatedSubzip = 'has_rated_subzip';
  static const String _keyNeverShowRatePrompt = 'never_show_rate_prompt';
  static const String _keyRatePromptLaunchCount = 'rate_prompt_launch_count';
  static const String _keyFirstUseEpochMs = 'first_use_epoch_ms';
  static const String _keyLastRatePromptEpochMs = 'last_rate_prompt_epoch_ms';
  static const int _minLaunchesBeforeRatePrompt = 4;
  static const Duration _minUsageBeforeRatePrompt = Duration(minutes: 10);

  late Future<PackageInfo> _packageInfoFuture;
  bool _isCheckingUpdate = false;
  bool _isRequestingReview = false;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final fileSystem = Provider.of<FileSystemProvider>(context, listen: false);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _section(
            title: 'Appearance',
            children: [
              RadioGroup<ThemeMode>(
                groupValue: appState.themeMode,
                onChanged: (mode) {
                  if (mode != null) {
                    appState.setThemeMode(mode);
                  }
                },
                child: Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: const Text('Dark Mode (AMOLED Siyah)'),
                      value: ThemeMode.dark,
                      activeColor: appState.accentColor,
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text('Light Mode'),
                      value: ThemeMode.light,
                      activeColor: appState.accentColor,
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text('System Default'),
                      value: ThemeMode.system,
                      activeColor: appState.accentColor,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: appState.accentColors.entries.map((entry) {
                    final isSelected = entry.key == appState.accentColorName;
                    return Tooltip(
                      message: entry.key,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => appState.setAccentColor(entry.key),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: entry.value,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                    color: theme.colorScheme.onSurface,
                                    width: 3,
                                  )
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          _section(
            title: 'File Browser',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.visibility_rounded),
                title: const Text('Show hidden files'),
                subtitle: const Text(
                  'Dot-prefixed files and folders stay hidden when off',
                ),
                value: appState.showHiddenFiles,
                onChanged: (value) async {
                  await appState.setShowHiddenFiles(value);
                  await fileSystem.setShowHiddenFiles(value);
                },
              ),
            ],
          ),
          _section(
            title: 'Dashboard',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.waving_hand_rounded),
                title: const Text('Show welcome card'),
                subtitle: const Text('Restore the welcome panel on Home'),
                value: appState.showWelcomeCard,
                onChanged: appState.setShowWelcomeCard,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.format_size_rounded),
                title: const Text('Expand Largest Files'),
                subtitle: const Text('Remember panel state on Home'),
                value: appState.largestExpanded,
                onChanged: appState.setLargestExpanded,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.history_rounded),
                title: const Text('Expand Recently Modified'),
                subtitle: const Text('Remember panel state on Home'),
                value: appState.recentExpanded,
                onChanged: appState.setRecentExpanded,
              ),
            ],
          ),
          _section(
            title: 'Categories',
            children: [
              ...FileCategory.builtInCategories.map(
                (category) => ListTile(
                  leading: Icon(FileCategory.iconFor(category.iconName)),
                  title: Text(category.label),
                  subtitle: Text('${category.extensions.length} file types'),
                ),
              ),
              const Divider(height: 1),
              if (appState.customCategories.isEmpty)
                const ListTile(
                  leading: Icon(Icons.folder_open_rounded),
                  title: Text('No custom folder categories'),
                  subtitle: Text(
                    'Add folders such as Downloads for quick access',
                  ),
                )
              else
                ...appState.customCategories.asMap().entries.map((entry) {
                  final index = entry.key;
                  final category = entry.value;
                  return ListTile(
                    leading: const Icon(Icons.folder_rounded),
                    title: Text(category.label),
                    subtitle: Text(
                      category.folderPath ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward_rounded),
                          tooltip: 'Move up',
                          onPressed: index == 0
                              ? null
                              : () => appState.moveFolderCategory(
                                  index,
                                  index - 1,
                                ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_rounded),
                          tooltip: 'Edit',
                          onPressed: () =>
                              _showCategoryDialog(category: category),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          tooltip: 'Delete',
                          onPressed: () =>
                              appState.removeFolderCategory(category.id),
                        ),
                      ],
                    ),
                  );
                }),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () => _showCategoryDialog(),
                  icon: const Icon(Icons.create_new_folder_rounded),
                  label: const Text('Add Folder Category'),
                ),
              ),
            ],
          ),
          _section(
            title: 'Safety',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.lock_rounded),
                title: const Text('Protect favorites from delete'),
                subtitle: const Text(
                  'Favorite files and folders cannot be deleted or moved',
                ),
                value: appState.protectFavoritesFromDelete,
                onChanged: appState.setProtectFavoritesFromDelete,
              ),
            ],
          ),
          _section(
            title: 'Updates',
            children: [
              ListTile(
                leading: const Icon(Icons.system_update_rounded),
                title: const Text('Check for Updates'),
                subtitle: const Text(
                  'Check latest version and open update page if needed',
                ),
                trailing: _isCheckingUpdate
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right_rounded),
                onTap: _isCheckingUpdate ? null : _checkForUpdates,
              ),
            ],
          ),
          _section(
            title: 'Rate & Review',
            children: [
              ListTile(
                leading: const Icon(Icons.rate_review_rounded),
                title: const Text('Rate and Comment'),
                subtitle: const Text(
                  'Open native review, with Play Store fallback if needed',
                ),
                trailing: _isRequestingReview
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right_rounded),
                onTap: _isRequestingReview ? null : _requestReview,
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Write Comment'),
                subtitle: const Text('Open the Play Store review page'),
                onTap: _isRequestingReview ? null : _openStoreReview,
              ),
              ListTile(
                leading: const Icon(Icons.notifications_active_rounded),
                title: const Text('Allow future review popups'),
                subtitle: const Text(
                  'Useful if you skipped the review prompt before',
                ),
                onTap: _resetReviewPrompt,
              ),
            ],
          ),
          _section(
            title: 'About',
            children: [
              FutureBuilder<PackageInfo>(
                future: _packageInfoFuture,
                builder: (context, snapshot) {
                  final versionText = snapshot.hasData
                      ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
                      : 'Loading...';
                  return ListTile(
                    leading: const Icon(Icons.folder_zip_rounded),
                    title: const Text('SubZip'),
                    subtitle: Text(
                      'Version $versionText\nAdvanced file manager and ZIP archive utility.',
                    ),
                    isThreeLine: true,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section({required String title, required List<Widget> children}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: isDark ? const Color(0x0EFFFFFF) : Colors.grey.shade200,
              ),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Future<void> _showCategoryDialog({FileCategory? category}) async {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final pathController = TextEditingController(
      text: category?.folderPath ?? '',
    );
    final labelController = TextEditingController(text: category?.label ?? '');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickFolder() async {
            final selectedPath = await FilePicker.getDirectoryPath();
            if (selectedPath == null || selectedPath.trim().isEmpty) return;
            pathController.text = selectedPath;
            if (labelController.text.trim().isEmpty) {
              labelController.text = p.basename(selectedPath);
            }
            setDialogState(() {});
          }

          return AlertDialog(
            title: Text(
              category == null ? 'Add Folder Category' : 'Edit Category',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(labelText: 'Category name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pathController,
                  decoration: const InputDecoration(labelText: 'Folder path'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: pickFolder,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Choose Folder'),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final label = labelController.text.trim();
                  final folderPath = pathController.text.trim();
                  if (label.isEmpty || folderPath.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Name and path are required.'),
                      ),
                    );
                    return;
                  }
                  if (!Directory(folderPath).existsSync()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Folder does not exist.')),
                    );
                    return;
                  }
                  if (category == null) {
                    await appState.addFolderCategory(
                      label: label,
                      folderPath: folderPath,
                    );
                  } else {
                    await appState.updateFolderCategory(
                      category.id,
                      label: label,
                      folderPath: folderPath,
                    );
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    if (_isCheckingUpdate || !mounted) return;
    setState(() {
      _isCheckingUpdate = true;
    });

    try {
      final updateService = UpdateService();
      final status = await updateService.checkForUpdate();
      if (!mounted) return;

      if (status == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Update check is unavailable right now.'),
          ),
        );
      } else if (!status.storeVersionAvailable) {
        final shouldOpen = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Play Store Check'),
            content: Text(
              'Installed version: ${status.localVersion}\n\nThe latest Play Store version could not be read right now. You can still open the store page to check manually.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Open Store'),
              ),
            ],
          ),
        );

        if (shouldOpen == true) {
          final opened = await updateService.openUpdatePage(status);
          if (!opened && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Update page could not be opened.')),
            );
          }
        }
      } else if (status.canUpdate) {
        final shouldOpen = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Update Available'),
            content: Text(
              'Current: ${status.localVersion}\nLatest: ${status.storeVersion}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Update'),
              ),
            ],
          ),
        );

        if (shouldOpen == true) {
          final opened = await updateService.openUpdatePage(status);
          if (!opened && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Update page could not be opened.')),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Latest version installed: ${status.localVersion}'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update check failed. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
        });
      }
    }
  }

  Future<void> _requestReview() async {
    if (_isRequestingReview || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isRequestingReview = true;
    });

    try {
      final reviewService = ReviewService();
      final requested = await reviewService.requestInAppReview();
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _keyLastRatePromptEpochMs,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (requested) {
        messenger.showSnackBar(
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
      } else {
        final opened = await reviewService.openStoreReviewPage();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              opened
                  ? 'Opened Play Store review page.'
                  : 'Review is not available right now.',
            ),
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Review prompt failed. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingReview = false;
        });
      }
    }
  }

  Future<void> _openStoreReview() async {
    if (_isRequestingReview || !mounted) return;
    setState(() {
      _isRequestingReview = true;
    });

    try {
      final opened = await ReviewService().openStoreReviewPage();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Opened Play Store review page.'
                : 'Review page is not available right now.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingReview = false;
        });
      }
    }
  }

  Future<void> _resetReviewPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasRatedSubzip, false);
    await prefs.setBool(_keyNeverShowRatePrompt, false);
    await prefs.remove(_keyLastRatePromptEpochMs);
    await prefs.setInt(
      _keyRatePromptLaunchCount,
      _minLaunchesBeforeRatePrompt - 1,
    );
    await prefs.setInt(
      _keyFirstUseEpochMs,
      DateTime.now()
          .subtract(_minUsageBeforeRatePrompt)
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Future review popups are enabled and cooldown was reset.',
        ),
      ),
    );
  }
}
