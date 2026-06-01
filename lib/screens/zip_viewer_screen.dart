import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../providers/file_system_provider.dart';
import '../providers/app_state_provider.dart';

class ZipViewerScreen extends StatefulWidget {
  final String zipPath;
  final String currentExplorerPath;

  const ZipViewerScreen({
    super.key,
    required this.zipPath,
    required this.currentExplorerPath,
  });

  @override
  State<ZipViewerScreen> createState() => _ZipViewerScreenState();
}

class _ZipViewerScreenState extends State<ZipViewerScreen> {
  late Future<List<ArchiveFile>> _zipFilesFuture;

  @override
  void initState() {
    super.initState();
    _zipFilesFuture = _loadZipFiles();
  }

  Future<List<ArchiveFile>> _loadZipFiles() async {
    final file = File(widget.zipPath);
    if (!await file.exists()) {
      throw FileSystemException('ZIP file not found', widget.zipPath);
    }
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    return archive.files;
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  IconData _getFileIcon(String name, bool isDirectory) {
    if (isDirectory) return Icons.folder_rounded;
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

  void _showFileOptions(BuildContext context, ArchiveFile archiveFile, FileSystemProvider fileSystem) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(p.basename(archiveFile.name)),
        content: const Text('Would you like to extract this file to the current folder or open a temporary copy?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await _openTemporaryFile(archiveFile);
            },
            child: const Text('Open (Temp)'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await _extractSingleFile(archiveFile, fileSystem);
            },
            child: const Text('Extract'),
          ),
        ],
      ),
    );
  }

  Future<void> _extractSingleFile(ArchiveFile archiveFile, FileSystemProvider fileSystem) async {
    try {
      final targetPath = p.join(widget.currentExplorerPath, archiveFile.name);
      final outFile = File(targetPath);
      
      if (!outFile.parent.existsSync()) {
        outFile.parent.createSync(recursive: true);
      }
      
      final content = archiveFile.content as List<int>;
      await outFile.writeAsBytes(content);
      
      // Refresh explorer
      await fileSystem.refresh();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Extracted ${p.basename(archiveFile.name)} successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Extraction failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _openTemporaryFile(ArchiveFile archiveFile) async {
    try {
      final tempDir = Directory.systemTemp.createTempSync('supzip_');
      final targetPath = p.join(tempDir.path, p.basename(archiveFile.name));
      final outFile = File(targetPath);
      
      final content = archiveFile.content as List<int>;
      await outFile.writeAsBytes(content);
      
      await OpenFilex.open(targetPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileSystem = Provider.of<FileSystemProvider>(context, listen: false);
    final appState = Provider.of<AppStateProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(p.basename(widget.zipPath), style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<List<ArchiveFile>>(
        future: _zipFilesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading ZIP contents:\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }
          final files = snapshot.data ?? [];
          if (files.isEmpty) {
            return const Center(child: Text('ZIP archive is empty.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final archiveFile = files[index];
              final isDir = archiveFile.isDirectory || archiveFile.name.endsWith('/');
              final icon = _getFileIcon(archiveFile.name, isDir);
              final iconColor = isDir
                  ? appState.accentColor
                  : (isDark ? Colors.grey.shade400 : Colors.grey.shade700);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0x0EFFFFFF) : Colors.grey.shade200,
                  ),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(icon, color: iconColor),
                  title: Text(
                    archiveFile.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: isDir
                      ? null
                      : Text(_formatSize(archiveFile.size), style: const TextStyle(fontSize: 11)),
                  trailing: isDir
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.download_rounded),
                          tooltip: 'Extract file',
                          onPressed: () => _showFileOptions(context, archiveFile, fileSystem),
                        ),
                  onTap: isDir
                      ? null
                      : () => _showFileOptions(context, archiveFile, fileSystem),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
