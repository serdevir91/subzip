import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/background_task.dart';

class ArchiveService {
  // Compress selected files/directories to a target ZIP file
  Future<void> compress(
    List<String> sourcePaths,
    String targetZipPath,
    BackgroundTask task,
    VoidCallback onUpdate, {
    int compressionLevel = 1, // 1 is BEST_SPEED, 9 is BEST_COMPRESSION
  }) async {
    final encoder = ZipFileEncoder();
    
    try {
      task.currentMessage = 'Scanning files...';
      onUpdate();

      // Gather all files to compress with their relative zip paths
      final List<_ZipEntry> entries = [];
      for (final srcPath in sourcePaths) {
        final entityType = FileSystemEntity.typeSync(srcPath);
        if (entityType == FileSystemEntityType.file) {
          entries.add(_ZipEntry(
            systemPath: srcPath,
            zipPath: p.basename(srcPath),
          ));
        } else if (entityType == FileSystemEntityType.directory) {
          final dir = Directory(srcPath);
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) {
              // Calculate relative path under the parent directory
              final relativePath = p.relative(entity.path, from: dir.parent.path);
              entries.add(_ZipEntry(
                systemPath: entity.path,
                zipPath: relativePath.replaceAll(Platform.pathSeparator, '/'),
              ));
            }
          }
        }
      }

      task.totalFiles = entries.length;
      task.processedFiles = 0;
      task.progress = 0.0;
      onUpdate();

      if (entries.isEmpty) {
        task.status = TaskStatus.failed;
        task.errorMessage = 'No files found to compress.';
        onUpdate();
        return;
      }

      // Create the ZIP encoder
      encoder.create(targetZipPath, level: compressionLevel);

      for (final entry in entries) {
        // Check for pause/cancel
        await task.checkPause();
        if (task.cancelRequested) {
          break;
        }

        task.currentMessage = 'Compressing ${p.basename(entry.systemPath)}';
        onUpdate();

        final file = File(entry.systemPath);
        if (file.existsSync()) {
          encoder.addFile(file, entry.zipPath);
        }

        task.processedFiles++;
        if (task.totalFiles > 0) {
          task.progress = task.processedFiles / task.totalFiles;
        }
        onUpdate();

        // Yield execution to keep the UI smooth
        await Future.delayed(Duration.zero);
      }

      encoder.close();

      if (task.cancelRequested) {
        // Clean up partial zip
        final zipFile = File(targetZipPath);
        if (zipFile.existsSync()) {
          try {
            zipFile.deleteSync();
          } catch (_) {}
        }
        task.status = TaskStatus.cancelled;
      } else {
        task.status = TaskStatus.completed;
        task.progress = 1.0;
      }
      onUpdate();
    } catch (e) {
      try {
        encoder.close();
      } catch (_) {}
      
      final zipFile = File(targetZipPath);
      if (zipFile.existsSync()) {
        try {
          zipFile.deleteSync();
        } catch (_) {}
      }
      
      task.status = TaskStatus.failed;
      task.errorMessage = e.toString();
      onUpdate();
    }
  }

  // Extract a ZIP archive to a destination directory
  Future<void> extract(
    String zipPath,
    String destDirPath,
    BackgroundTask task,
    VoidCallback onUpdate,
  ) async {
    try {
      task.currentMessage = 'Reading archive...';
      onUpdate();

      final file = File(zipPath);
      if (!file.existsSync()) {
        task.status = TaskStatus.failed;
        task.errorMessage = 'Archive file not found.';
        onUpdate();
        return;
      }

      // Read ZIP bytes (note: for huge files this reads all to memory, which is standard in archive pkg)
      final bytes = await file.readAsBytes();
      
      task.currentMessage = 'Extracting archive...';
      onUpdate();
      
      final archive = ZipDecoder().decodeBytes(bytes);

      task.totalFiles = archive.length;
      task.processedFiles = 0;
      task.progress = 0.0;
      onUpdate();

      final destDir = Directory(destDirPath);
      if (!destDir.existsSync()) {
        destDir.createSync(recursive: true);
      }

      for (final archiveFile in archive) {
        // Check for pause/cancel
        await task.checkPause();
        if (task.cancelRequested) {
          break;
        }

        task.currentMessage = 'Extracting ${archiveFile.name}';
        onUpdate();

        final targetPath = p.join(destDirPath, archiveFile.name);

        if (archiveFile.isDirectory) {
          final dir = Directory(targetPath);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
        } else {
          final outFile = File(targetPath);
          if (!outFile.parent.existsSync()) {
            outFile.parent.createSync(recursive: true);
          }
          
          final content = archiveFile.content as List<int>;
          await outFile.writeAsBytes(content);
        }

        task.processedFiles++;
        if (task.totalFiles > 0) {
          task.progress = task.processedFiles / task.totalFiles;
        }
        onUpdate();

        // Yield execution to keep the UI smooth
        await Future.delayed(Duration.zero);
      }

      if (task.cancelRequested) {
        task.status = TaskStatus.cancelled;
        // Optional: clean up partially extracted files if desired,
        // but typically in file managers, partial files are left or user cleans up.
      } else {
        task.status = TaskStatus.completed;
        task.progress = 1.0;
      }
      onUpdate();
    } catch (e) {
      task.status = TaskStatus.failed;
      task.errorMessage = e.toString();
      onUpdate();
    }
  }
}

class _ZipEntry {
  final String systemPath;
  final String zipPath;

  _ZipEntry({
    required this.systemPath,
    required this.zipPath,
  });
}
