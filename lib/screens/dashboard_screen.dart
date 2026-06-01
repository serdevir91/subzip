import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/file_system_provider.dart';
import '../providers/app_state_provider.dart';
import '../models/shared_file.dart';

class _TypeSummary {
  final int count;
  final int bytes;

  const _TypeSummary({required this.count, required this.bytes});
}

class DashboardScreen extends StatefulWidget {
  final Function(String path) onNavigateToFolder;
  final Function(String category) onOpenCategory;

  const DashboardScreen({
    super.key,
    required this.onNavigateToFolder,
    required this.onOpenCategory,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const MethodChannel _storageChannel = MethodChannel(
    'app.subzip/storage',
  );
  late Future<List<Map<String, dynamic>>> _diskUsageFuture;
  List<SharedFile> _cachedLargest = [];
  List<SharedFile> _cachedRecent = [];
  bool _isScanning = false;
  Map<String, _TypeSummary> _typeSummaries = const {
    'images': _TypeSummary(count: 0, bytes: 0),
    'videos': _TypeSummary(count: 0, bytes: 0),
    'audio': _TypeSummary(count: 0, bytes: 0),
    'documents': _TypeSummary(count: 0, bytes: 0),
    'apk': _TypeSummary(count: 0, bytes: 0),
  };

  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
    '.heic',
  };
  static const Set<String> _videoExtensions = {
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.webm',
    '.3gp',
  };
  static const Set<String> _audioExtensions = {
    '.mp3',
    '.wav',
    '.ogg',
    '.m4a',
    '.flac',
    '.aac',
  };
  static const Set<String> _documentExtensions = {
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
  };
  static const Set<String> _apkExtensions = {'.apk', '.xapk', '.apks'};

  @override
  void initState() {
    super.initState();
    _loadCachedFiles();
    _refreshData();
  }

  Future<void> _loadCachedFiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final largestJson = prefs.getString('dashboard_largest_files');
      final recentJson = prefs.getString('dashboard_recent_files');

      if (largestJson != null && recentJson != null) {
        final List<dynamic> largestDecoded = jsonDecode(largestJson);
        final List<dynamic> recentDecoded = jsonDecode(recentJson);

        setState(() {
          _cachedLargest = largestDecoded
              .map((x) => SharedFile.fromJson(x as Map<String, dynamic>))
              .toList();
          _cachedRecent = recentDecoded
              .map((x) => SharedFile.fromJson(x as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {}
  }

  void _refreshData() {
    final fileSystem = Provider.of<FileSystemProvider>(context, listen: false);
    setState(() {
      _diskUsageFuture = _loadDiskUsage();
      _isScanning = true;
    });
    _scanFiles(fileSystem).then((val) {
      if (mounted) {
        setState(() {
          _cachedLargest = val['largest'] as List<SharedFile>;
          _cachedRecent = val['recent'] as List<SharedFile>;
          _typeSummaries = val['summaries'] as Map<String, _TypeSummary>;
          _isScanning = false;
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> _loadDiskUsage() async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      // Fallback/Mock for non-windows platforms (except Android)
      return [
        {
          'drive': '/',
          'free': 60 * 1024 * 1024 * 1024,
          'total': 128 * 1024 * 1024 * 1024,
          'used': 68 * 1024 * 1024 * 1024,
        },
      ];
    }

    if (Platform.isAndroid) {
      try {
        final stats = await _storageChannel.invokeMapMethod<String, dynamic>(
          'getStorageStats',
        );
        if (stats != null) {
          final total = (stats['total'] as num?)?.toInt() ?? 0;
          final free = (stats['free'] as num?)?.toInt() ?? 0;
          final used =
              (stats['used'] as num?)?.toInt() ??
              (total - free).clamp(0, total);
          if (total > 0) {
            return [
              {
                'drive': stats['path'] as String? ?? '/storage/emulated/0',
                'free': free.clamp(0, total),
                'total': total,
                'used': used.clamp(0, total),
              },
            ];
          }
        }
      } catch (e) {
        debugPrint('Storage stats channel failed: $e');
      }
      return [
        {'drive': '/storage/emulated/0', 'free': 0, 'total': 0, 'used': 0},
      ];
    }

    try {
      final result = await Process.run('powershell', [
        '-Command',
        'Get-WmiObject Win32_LogicalDisk | Select-Object DeviceID, FreeSpace, Size | ConvertTo-Json',
      ]);
      if (result.exitCode == 0) {
        final decoded = jsonDecode(result.stdout);
        if (decoded is List) {
          return decoded.map((item) {
            final free = item['FreeSpace'] as int? ?? 0;
            final total = item['Size'] as int? ?? 0;
            return {
              'drive': item['DeviceID'] as String,
              'free': free,
              'total': total,
              'used': total - free,
            };
          }).toList();
        } else if (decoded is Map) {
          final free = decoded['FreeSpace'] as int? ?? 0;
          final total = decoded['Size'] as int? ?? 0;
          return [
            {
              'drive': decoded['DeviceID'] as String,
              'free': free,
              'total': total,
              'used': total - free,
            },
          ];
        }
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> _scanFiles(FileSystemProvider fileSystem) async {
    final List<SharedFile> allFiles = [];
    List<String> pathsToScan = [];

    if (Platform.isAndroid) {
      const rootDir = '/storage/emulated/0';
      final subDirs = [
        'Download',
        'Documents',
        'DCIM',
        'Pictures',
        'Movies',
        'Music',
      ];
      for (final sub in subDirs) {
        final d = Directory(p.join(rootDir, sub));
        if (d.existsSync()) {
          pathsToScan.add(d.path);
        }
      }
      if (pathsToScan.isEmpty) {
        pathsToScan.add(rootDir);
      }
    } else {
      if (Platform.isWindows) {
        final drives = fileSystem.getWindowsDrives();
        if (drives.isNotEmpty) {
          pathsToScan.addAll(drives.map((d) => d.path));
        }
      }
      if (pathsToScan.isEmpty) {
        final home =
            Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
        if (home != null) {
          final download = Directory(p.join(home, 'Downloads'));
          final documents = Directory(p.join(home, 'Documents'));
          if (download.existsSync()) pathsToScan.add(download.path);
          if (documents.existsSync()) pathsToScan.add(documents.path);
        }
      }
      if (pathsToScan.isEmpty) {
        final appDocsDir = await getApplicationDocumentsDirectory();
        pathsToScan.add(p.join(appDocsDir.path, 'SubZip'));
      }
    }

    int imageCount = 0,
        videoCount = 0,
        audioCount = 0,
        docCount = 0,
        apkCount = 0;
    int imageBytes = 0,
        videoBytes = 0,
        audioBytes = 0,
        docBytes = 0,
        apkBytes = 0;

    int totalCount = 0;
    const maxFiles = 12000;

    for (final scanPath in pathsToScan) {
      final dir = Directory(scanPath);
      if (!dir.existsSync()) continue;

      try {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (totalCount >= maxFiles) break;

          final entityPath = entity.path;
          final name = p.basename(entityPath);

          // Skip hidden files/directories and system folders
          if (name.startsWith('.') ||
              entityPath.contains('${Platform.pathSeparator}.') ||
              entityPath.contains('Android/data') ||
              entityPath.contains('Android/obb')) {
            continue;
          }

          if (entity is File) {
            try {
              final stat = entity.statSync();
              final ext = p.extension(entityPath).toLowerCase();
              allFiles.add(
                SharedFile(
                  name: name,
                  path: entityPath,
                  isDirectory: false,
                  size: stat.size,
                  dateModified: stat.modified,
                ),
              );
              if (_imageExtensions.contains(ext)) {
                imageCount++;
                imageBytes += stat.size;
              } else if (_videoExtensions.contains(ext)) {
                videoCount++;
                videoBytes += stat.size;
              } else if (_audioExtensions.contains(ext)) {
                audioCount++;
                audioBytes += stat.size;
              } else if (_documentExtensions.contains(ext)) {
                docCount++;
                docBytes += stat.size;
              } else if (_apkExtensions.contains(ext)) {
                apkCount++;
                apkBytes += stat.size;
              }
              totalCount++;
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    final List<SharedFile> largest = List.from(allFiles);
    largest.sort((a, b) => b.size.compareTo(a.size));

    final List<SharedFile> recent = List.from(allFiles);
    recent.sort((a, b) => b.dateModified.compareTo(a.dateModified));

    final result = {
      'largest': largest.take(5).toList(),
      'recent': recent.take(5).toList(),
      'summaries': <String, _TypeSummary>{
        'images': _TypeSummary(count: imageCount, bytes: imageBytes),
        'videos': _TypeSummary(count: videoCount, bytes: videoBytes),
        'audio': _TypeSummary(count: audioCount, bytes: audioBytes),
        'documents': _TypeSummary(count: docCount, bytes: docBytes),
        'apk': _TypeSummary(count: apkCount, bytes: apkBytes),
      },
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      final largestList = result['largest'] as List<SharedFile>;
      final recentList = result['recent'] as List<SharedFile>;
      final largestJson = jsonEncode(
        largestList.map((f) => f.toJson()).toList(),
      );
      final recentJson = jsonEncode(recentList.map((f) => f.toJson()).toList());
      await prefs.setString('dashboard_largest_files', largestJson);
      await prefs.setString('dashboard_recent_files', recentJson);
    } catch (_) {}

    return result;
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _resolveDownloadsPath() {
    if (Platform.isAndroid) {
      final primary = Directory('/storage/emulated/0/Download');
      if (primary.existsSync()) return primary.path;
      final secondary = Directory('/storage/emulated/0/Downloads');
      if (secondary.existsSync()) return secondary.path;
      return primary.path;
    }
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      if (home != null && home.isNotEmpty) {
        return p.join(home, 'Downloads');
      }
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, 'Downloads');
    }
    return '';
  }

  Widget _buildTypeCard({
    required BuildContext context,
    required AppStateProvider appState,
    required String label,
    required IconData icon,
    required _TypeSummary summary,
    required String categoryKey,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => widget.onOpenCategory(categoryKey),
        child: Container(
          width: 130,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? const Color(0x18FFFFFF) : Colors.grey.shade200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: appState.accentColor),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${summary.count} files',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.outline,
                ),
              ),
              Text(
                _formatSize(summary.bytes),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.outline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getFileIcon(String name) {
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.bmp':
      case '.webp':
        return Icons.image_rounded;
      case '.mp4':
      case '.mkv':
      case '.avi':
        return Icons.movie_creation_rounded;
      case '.mp3':
      case '.wav':
        return Icons.music_note_rounded;
      case '.pdf':
        return Icons.picture_as_pdf_rounded;
      case '.zip':
      case '.rar':
      case '.7z':
        return Icons.archive_rounded;
      case '.txt':
      case '.doc':
      case '.docx':
      case '.xls':
      case '.xlsx':
      case '.ppt':
      case '.pptx':
        return Icons.description_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appState = Provider.of<AppStateProvider>(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          _refreshData();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Welcome Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      appState.accentColor,
                      appState.accentColor.withOpacity(0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: appState.accentColor.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome to SubZip',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Manage, compress and convert your files offline.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'Categories',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTypeCard(
                      context: context,
                      appState: appState,
                      label: 'Photos',
                      icon: Icons.photo_library_rounded,
                      summary: _typeSummaries['images']!,
                      categoryKey: 'images',
                    ),
                    _buildTypeCard(
                      context: context,
                      appState: appState,
                      label: 'Videos',
                      icon: Icons.video_collection_rounded,
                      summary: _typeSummaries['videos']!,
                      categoryKey: 'videos',
                    ),
                    _buildTypeCard(
                      context: context,
                      appState: appState,
                      label: 'Audio',
                      icon: Icons.music_note_rounded,
                      summary: _typeSummaries['audio']!,
                      categoryKey: 'audio',
                    ),
                    _buildTypeCard(
                      context: context,
                      appState: appState,
                      label: 'Documents',
                      icon: Icons.description_rounded,
                      summary: _typeSummaries['documents']!,
                      categoryKey: 'documents',
                    ),
                    _buildTypeCard(
                      context: context,
                      appState: appState,
                      label: 'APK',
                      icon: Icons.android_rounded,
                      summary: _typeSummaries['apk']!,
                      categoryKey: 'apk',
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () =>
                            widget.onNavigateToFolder(_resolveDownloadsPath()),
                        child: Container(
                          width: 130,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E1E1E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0x18FFFFFF)
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.download_for_offline_rounded,
                                color: appState.accentColor,
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Downloads',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Quick access',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              Text(
                                'Open folder',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: appState.accentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 2. Storage Disk Usage Header
              const Text(
                'Disk Space Usage',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              // Storage Usage List
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _diskUsageFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError ||
                      !snapshot.hasData ||
                      snapshot.data!.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: Text('Could not read disk space information.'),
                        ),
                      ),
                    );
                  }
                  final drives = snapshot.data!;
                  return Column(
                    children: drives.map((d) {
                      final driveLetter = d['drive'] as String;
                      final total = d['total'] as int;
                      final free = d['free'] as int;
                      final used = d['used'] as int;
                      final percent = total > 0 ? (used / total) : 0.0;
                      final formattedUsed = _formatSize(used);
                      final formattedTotal = _formatSize(total);
                      final formattedFree = _formatSize(free);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isDark
                                ? const Color(0x0EFFFFFF)
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            // Navigate into the specific drive folder
                            final path = Platform.isWindows
                                ? '$driveLetter\\'
                                : driveLetter;
                            widget.onNavigateToFolder(path);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: appState.accentColor
                                      .withOpacity(0.12),
                                  child: Icon(
                                    Icons.storage_rounded,
                                    color: appState.accentColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              Platform.isAndroid
                                                  ? 'Internal Storage'
                                                  : 'Local Disk ($driveLetter)',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${(percent * 100).toStringAsFixed(1)}%',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: appState.accentColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: percent,
                                          backgroundColor: isDark
                                              ? const Color(0xFF2C2C2C)
                                              : Colors.grey.shade200,
                                          color: appState.accentColor,
                                          minHeight: 6,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              '$formattedUsed / $formattedTotal',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color:
                                                    theme.colorScheme.outline,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            '$formattedFree free',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: theme.colorScheme.outline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 16),

              // 3. Largest & Recent Files Sections
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isScanning && _cachedLargest.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    if (_isScanning)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            color: appState.accentColor,
                            backgroundColor: isDark
                                ? const Color(0xFF2C2C2C)
                                : Colors.grey.shade200,
                            minHeight: 3,
                          ),
                        ),
                      ),
                    // Largest Files Card Section
                    _buildFileListSection(
                      title: 'Largest Files',
                      files: _cachedLargest,
                      theme: theme,
                      isDark: isDark,
                      appState: appState,
                      emptyText: 'No large files found.',
                      showSize: true,
                    ),
                    const SizedBox(height: 24),
                    // Recent Files Card Section
                    _buildFileListSection(
                      title: 'Recently Modified Files',
                      files: _cachedRecent,
                      theme: theme,
                      isDark: isDark,
                      appState: appState,
                      emptyText: 'No recent files found.',
                      showSize: false,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileListSection({
    required String title,
    required List<SharedFile> files,
    required ThemeData theme,
    required bool isDark,
    required AppStateProvider appState,
    required String emptyText,
    required bool showSize,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (files.isEmpty)
          Card(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? const Color(0x0EFFFFFF) : Colors.grey.shade200,
              ),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20.0),
              child: Center(
                child: Text(
                  emptyText,
                  style: TextStyle(
                    color: theme.colorScheme.outline,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          )
        else
          Card(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? const Color(0x0EFFFFFF) : Colors.grey.shade200,
              ),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: files.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: isDark ? const Color(0x0EFFFFFF) : Colors.grey.shade100,
              ),
              itemBuilder: (context, index) {
                final file = files[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: appState.accentColor.withOpacity(0.08),
                    child: Icon(
                      _getFileIcon(file.name),
                      color: appState.accentColor,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    file.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    file.path,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    showSize
                        ? file.sizeFormatted
                        : file.dateFormatted.split(' ')[0],
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () async {
                    await OpenFilex.open(file.path);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
