import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:new_version_plus/new_version_plus.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/app_state_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<PackageInfo> _packageInfoFuture;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        children: [
          // Theme settings
          _buildSectionHeader(context, 'Appearance & Theme'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? const Color(0x0EFFFFFF) : Colors.grey.shade200,
              ),
            ),
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('Dark Mode (AMOLED Siyah)'),
                  value: ThemeMode.dark,
                  groupValue: appState.themeMode,
                  activeColor: appState.accentColor,
                  onChanged: (mode) {
                    if (mode != null) appState.setThemeMode(mode);
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Light Mode'),
                  value: ThemeMode.light,
                  groupValue: appState.themeMode,
                  activeColor: appState.accentColor,
                  onChanged: (mode) {
                    if (mode != null) appState.setThemeMode(mode);
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('System Default'),
                  value: ThemeMode.system,
                  groupValue: appState.themeMode,
                  activeColor: appState.accentColor,
                  onChanged: (mode) {
                    if (mode != null) appState.setThemeMode(mode);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Accent Color (Horizontal & Modern)
          _buildSectionHeader(context, 'Color Palette'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? const Color(0x0EFFFFFF) : Colors.grey.shade200,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select app accent color (folders and button accents):',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 50,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: appState.accentColors.keys.length,
                      itemBuilder: (context, index) {
                        final name = appState.accentColors.keys.elementAt(
                          index,
                        );
                        final color = appState.accentColors[name]!;
                        final isSelected = appState.accentColorName == name;

                        return GestureDetector(
                          onTap: () => appState.setAccentColor(name),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      width: 3,
                                    )
                                  : null,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: color.withOpacity(0.4),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          _buildSectionHeader(context, 'Update & Review'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? const Color(0x0EFFFFFF) : Colors.grey.shade200,
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.system_update_rounded),
                  title: const Text('Check for Updates'),
                  subtitle: const Text('Check latest version on Google Play'),
                  trailing: _isCheckingUpdate
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: _isCheckingUpdate ? null : _checkForUpdates,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.rate_review_rounded),
                  title: const Text('Rate and Comment'),
                  subtitle: const Text('Request in-app review prompt'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _requestInAppReview,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: const Text('Write Comment'),
                  subtitle: const Text('Open Google Play listing directly'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openStoreListing,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // About app
          _buildSectionHeader(context, 'About'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? const Color(0x0EFFFFFF) : Colors.grey.shade200,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: FutureBuilder<PackageInfo>(
                future: _packageInfoFuture,
                builder: (context, snapshot) {
                  final versionText = snapshot.hasData
                      ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
                      : 'Loading...';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SubZip',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Version $versionText'),
                      const SizedBox(height: 12),
                      const Text(
                        'SubZip is an advanced file manager and ZIP archive application. It features customized folders, multi-selection, and a real-time progress monitor panel.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                          height: 1.4,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    if (_isCheckingUpdate || !mounted) return;
    setState(() {
      _isCheckingUpdate = true;
    });

    try {
      final updater = NewVersionPlus(
        androidId: 'www.subzip.app',
        androidPlayStoreCountry: 'TR',
      );
      final status = await updater.getVersionStatus();
      if (!mounted) return;

      if (status == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update check could not be completed.')),
        );
      } else if (status.canUpdate) {
        final shouldOpenStore = await showDialog<bool>(
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
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Open Store'),
              ),
            ],
          ),
        );

        if (shouldOpenStore == true) {
          await updater.launchAppStore(status.appStoreLink);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are using the latest version.')),
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

  Future<void> _requestInAppReview() async {
    try {
      final inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
      } else {
        await _openStoreListing();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review dialog could not be opened.')),
      );
    }
  }

  Future<void> _openStoreListing() async {
    try {
      final inAppReview = InAppReview.instance;
      if (Platform.isIOS) {
        await inAppReview.openStoreListing(appStoreId: 'www.subzip.app');
      } else {
        await inAppReview.openStoreListing();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Store listing could not be opened.')),
      );
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
