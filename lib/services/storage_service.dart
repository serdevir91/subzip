import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shared_file.dart';
import '../models/background_task.dart';

class StorageService {
  late SharedPreferences _prefs;
  late Directory _rootDir;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _rootDir = await _resolveRootDirectory();
    if (!_rootDir.existsSync()) {
      _rootDir.createSync(recursive: true);
    }
  }

  Future<Directory> _resolveRootDirectory() async {
    if (Platform.isAndroid) {
      final hasAllFilesAccess = await Permission.manageExternalStorage.isGranted;
      if (hasAllFilesAccess) {
        return Directory('/storage/emulated/0');
      }
    }
    final appDocsDir = await getApplicationDocumentsDirectory();
    return Directory(p.join(appDocsDir.path, 'SupZip'));
  }

  String get rootPath {
    final customPath = _prefs.getString('download_path');
    if (customPath != null && customPath.isNotEmpty) {
      final dir = Directory(customPath);
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {}
      }
      return dir.path;
    }
    return _rootDir.path;
  }

  Future<void> setDownloadPath(String path) async {
    await _prefs.setString('download_path', path);
  }

  Future<void> refreshRootDirectory() async {
    final nextRoot = await _resolveRootDirectory();
    if (nextRoot.path != _rootDir.path) {
      _rootDir = nextRoot;
      if (!_rootDir.existsSync()) {
        _rootDir.createSync(recursive: true);
      }
    }
  }

  List<SharedFile> getWindowsDrives() {
    List<SharedFile> drives = [];
    if (!Platform.isWindows) return drives;
    for (var letter = 65; letter <= 90; letter++) {
      final drivePath = '${String.fromCharCode(letter)}:\\';
      final dir = Directory(drivePath);
      try {
        if (dir.existsSync()) {
          drives.add(SharedFile(
            name: 'Local Disk (${String.fromCharCode(letter)}:)',
            path: drivePath,
            isDirectory: true,
            size: 0,
            dateModified: DateTime.now(),
          ));
        }
      } catch (_) {}
    }
    return drives;
  }

  List<SharedFile> listFiles(String folderPath) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return [];

    try {
      return dir
          .listSync()
          .map((entity) => SharedFile.fromFileSystemEntity(entity))
          .toList()
        ..sort((a, b) {
          if (a.isDirectory && !b.isDirectory) return -1;
          if (!a.isDirectory && b.isDirectory) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    } catch (e) {
      debugPrint('Error listing files: $e');
      return [];
    }
  }

  Future<Directory> createFolder(String parentPath, String folderName) async {
    final newDir = Directory(p.join(parentPath, folderName));
    if (!newDir.existsSync()) {
      await newDir.create(recursive: true);
    }
    return newDir;
  }

  Future<File> createFile(String parentPath, String fileName) async {
    final newFile = File(p.join(parentPath, fileName));
    if (!newFile.existsSync()) {
      await newFile.create(recursive: true);
    }
    return newFile;
  }

  // Count files for background tasks
  Future<int> _countFilesRecursive(List<String> paths) async {
    int total = 0;
    for (final path in paths) {
      if (await FileSystemEntity.isDirectory(path)) {
        final dir = Directory(path);
        try {
          await for (final _ in dir.list(recursive: true)) {
            total++;
          }
        } catch (_) {}
      } else {
        total++;
      }
    }
    return total;
  }

  // Recursive copy with task progress, pause and cancel support
  Future<void> copyItems(
    List<String> srcPaths,
    String destDirPath,
    BackgroundTask task,
    VoidCallback onUpdate,
  ) async {
    task.currentMessage = 'Counting files...';
    onUpdate();
    
    int total = await _countFilesRecursive(srcPaths);
    task.totalFiles = total;
    task.processedFiles = 0;
    task.progress = 0.0;
    onUpdate();

    for (final srcPath in srcPaths) {
      if (task.cancelRequested) break;
      
      final isDir = await FileSystemEntity.isDirectory(srcPath);
      final name = p.basename(srcPath);
      final destPath = p.join(destDirPath, name);

      if (isDir) {
        await _copyDirRecursive(Directory(srcPath), Directory(destPath), task, onUpdate);
      } else {
        await _copyFile(File(srcPath), File(destPath), task, onUpdate);
      }
    }

    if (task.cancelRequested) {
      task.status = TaskStatus.cancelled;
    } else {
      task.status = TaskStatus.completed;
      task.progress = 1.0;
    }
    onUpdate();
  }

  Future<void> _copyFile(
    File srcFile,
    File destFile,
    BackgroundTask task,
    VoidCallback onUpdate,
  ) async {
    await task.checkPause();
    if (task.cancelRequested) return;

    task.currentMessage = 'Copying ${srcFile.path.split(Platform.pathSeparator).last}';
    onUpdate();

    // Ensure parent directory exists
    if (!destFile.parent.existsSync()) {
      destFile.parent.createSync(recursive: true);
    }

    // Perform copy
    await srcFile.copy(destFile.path);

    task.processedFiles++;
    if (task.totalFiles > 0) {
      task.progress = task.processedFiles / task.totalFiles;
    }
    onUpdate();
    await Future.delayed(Duration.zero); // yield to prevent UI freeze
  }

  Future<void> _copyDirRecursive(
    Directory srcDir,
    Directory destDir,
    BackgroundTask task,
    VoidCallback onUpdate,
  ) async {
    await task.checkPause();
    if (task.cancelRequested) return;

    if (!destDir.existsSync()) {
      destDir.createSync(recursive: true);
    }

    List<FileSystemEntity> entities = [];
    try {
      entities = srcDir.listSync();
    } catch (_) {}

    for (final entity in entities) {
      if (task.cancelRequested) return;

      final name = p.basename(entity.path);
      final destPath = p.join(destDir.path, name);

      if (entity is Directory) {
        await _copyDirRecursive(entity, Directory(destPath), task, onUpdate);
      } else if (entity is File) {
        await _copyFile(entity, File(destPath), task, onUpdate);
      }
    }
  }

  // Recursive delete with task progress, pause and cancel support
  Future<void> deleteItems(
    List<String> paths,
    BackgroundTask task,
    VoidCallback onUpdate,
  ) async {
    task.currentMessage = 'Counting files...';
    onUpdate();

    int total = await _countFilesRecursive(paths);
    task.totalFiles = total;
    task.processedFiles = 0;
    task.progress = 0.0;
    onUpdate();

    for (final path in paths) {
      if (task.cancelRequested) break;

      final isDir = await FileSystemEntity.isDirectory(path);
      if (isDir) {
        await _deleteDirRecursive(Directory(path), task, onUpdate);
      } else {
        await _deleteFile(File(path), task, onUpdate);
      }
    }

    if (task.cancelRequested) {
      task.status = TaskStatus.cancelled;
    } else {
      task.status = TaskStatus.completed;
      task.progress = 1.0;
    }
    onUpdate();
  }

  Future<void> _deleteFile(
    File file,
    BackgroundTask task,
    VoidCallback onUpdate,
  ) async {
    await task.checkPause();
    if (task.cancelRequested) return;

    task.currentMessage = 'Deleting ${file.path.split(Platform.pathSeparator).last}';
    onUpdate();

    if (file.existsSync()) {
      await file.delete();
    }

    task.processedFiles++;
    if (task.totalFiles > 0) {
      task.progress = task.processedFiles / task.totalFiles;
    }
    onUpdate();
    await Future.delayed(Duration.zero);
  }

  Future<void> _deleteDirRecursive(
    Directory dir,
    BackgroundTask task,
    VoidCallback onUpdate,
  ) async {
    await task.checkPause();
    if (task.cancelRequested) return;

    List<FileSystemEntity> entities = [];
    try {
      entities = dir.listSync();
    } catch (_) {}

    for (final entity in entities) {
      if (task.cancelRequested) return;

      if (entity is Directory) {
        await _deleteDirRecursive(entity, task, onUpdate);
      } else if (entity is File) {
        await _deleteFile(entity, task, onUpdate);
      }
    }

    // Delete the now empty directory
    if (dir.existsSync()) {
      await dir.delete();
    }
  }

  // Move items (copy then delete)
  Future<void> moveItems(
    List<String> srcPaths,
    String destDirPath,
    BackgroundTask task,
    VoidCallback onUpdate,
  ) async {
    // We can implement move as: copy all files then delete them, which is safe,
    // or try renaming if they are on the same partition.
    // However, to track progress correctly and support cross-partition move,
    // implementing as copy then delete is standard and robust.
    task.currentMessage = 'Counting files...';
    onUpdate();

    int total = await _countFilesRecursive(srcPaths);
    // Double because copy and delete both count
    task.totalFiles = total * 2;
    task.processedFiles = 0;
    task.progress = 0.0;
    onUpdate();

    // 1. Copy Phase
    List<String> copiedPaths = [];
    for (final srcPath in srcPaths) {
      if (task.cancelRequested) break;
      final isDir = await FileSystemEntity.isDirectory(srcPath);
      final name = p.basename(srcPath);
      final destPath = p.join(destDirPath, name);

      if (isDir) {
        await _copyDirRecursive(Directory(srcPath), Directory(destPath), task, onUpdate);
      } else {
        await _copyFile(File(srcPath), File(destPath), task, onUpdate);
      }
      copiedPaths.add(srcPath);
    }

    // 2. Delete Phase (only if copy wasn't cancelled)
    if (!task.cancelRequested) {
      for (final srcPath in srcPaths) {
        if (task.cancelRequested) break;
        final isDir = await FileSystemEntity.isDirectory(srcPath);
        if (isDir) {
          await _deleteDirRecursive(Directory(srcPath), task, onUpdate);
        } else {
          await _deleteFile(File(srcPath), task, onUpdate);
        }
      }
    } else {
      // Clean up partially copied files if cancelled
      for (final srcPath in srcPaths) {
        final name = p.basename(srcPath);
        final destPath = p.join(destDirPath, name);
        final file = File(destPath);
        if (file.existsSync()) {
          try { file.deleteSync(); } catch (_) {}
        }
        final dir = Directory(destPath);
        if (dir.existsSync()) {
          try { dir.deleteSync(recursive: true); } catch (_) {}
        }
      }
    }

    if (task.cancelRequested) {
      task.status = TaskStatus.cancelled;
    } else {
      task.status = TaskStatus.completed;
      task.progress = 1.0;
    }
    onUpdate();
  }
}
