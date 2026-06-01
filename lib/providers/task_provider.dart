import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/background_task.dart';
import '../services/storage_service.dart';
import '../services/archive_service.dart';
import 'file_system_provider.dart';
import '../services/conversion_service.dart';
import '../services/notification_service.dart';

class TaskProvider extends ChangeNotifier {
  final StorageService _storageService;
  final ArchiveService _archiveService;
  final List<BackgroundTask> _tasks = [];
  final _uuid = const Uuid();
  final _conversionService = ConversionService();

  List<BackgroundTask> get tasks => _tasks;
  
  List<BackgroundTask> get activeTasks =>
      _tasks.where((t) => t.status == TaskStatus.running || t.status == TaskStatus.paused).toList();

  TaskProvider({
    required StorageService storageService,
    required ArchiveService archiveService,
  })  : _storageService = storageService,
        _archiveService = archiveService;

  void _updateTaskNotification(BackgroundTask task) {
    final notificationId = task.id.hashCode;
    final progressPercent = (task.progress * 100).toInt();
    
    if (task.status == TaskStatus.running || task.status == TaskStatus.paused) {
      String body = task.currentMessage.isNotEmpty 
          ? task.currentMessage 
          : 'Progress: $progressPercent%';
      NotificationService().showProgressNotification(
        id: notificationId,
        title: task.name,
        body: body,
        progress: progressPercent,
        maxProgress: 100,
      );
    } else if (task.status == TaskStatus.completed) {
      NotificationService().showCompleteNotification(
        id: notificationId,
        title: 'Completed: ${task.name}',
        body: 'File operation completed successfully.',
      );
    } else if (task.status == TaskStatus.failed) {
      NotificationService().showCompleteNotification(
        id: notificationId,
        title: 'Error: ${task.name}',
        body: task.errorMessage ?? 'An error occurred.',
      );
    } else if (task.status == TaskStatus.cancelled) {
      NotificationService().cancelNotification(notificationId);
    }
  }

  void pauseTask(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.pause();
    _updateTaskNotification(task);
    notifyListeners();
  }

  void resumeTask(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.resume();
    _updateTaskNotification(task);
    notifyListeners();
  }

  void cancelTask(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.cancel();
    _updateTaskNotification(task);
    notifyListeners();
  }

  void clearCompletedTasks() {
    _tasks.removeWhere((t) =>
        t.status == TaskStatus.completed ||
        t.status == TaskStatus.cancelled ||
        t.status == TaskStatus.failed);
    notifyListeners();
  }

  // Start a Copy Task
  void startCopyTask(
    List<String> srcPaths,
    String destDirPath,
    FileSystemProvider fileSystem,
  ) {
    final srcPathsCopy = List<String>.from(srcPaths); // Fix concurrent modification
    final id = _uuid.v4();
    final name = srcPathsCopy.length == 1
        ? 'Copying ${srcPathsCopy[0].split(Platform.pathSeparator).last}'
        : 'Copying ${srcPathsCopy.length} items';

    final task = BackgroundTask(
      id: id,
      name: name,
      type: TaskType.copy,
      targetPaths: [destDirPath],
    );

    _tasks.add(task);
    _updateTaskNotification(task);
    notifyListeners();

    _storageService.copyItems(srcPathsCopy, destDirPath, task, () {
      _updateTaskNotification(task);
      notifyListeners();
    }).then((_) {
      fileSystem.refresh();
      _updateTaskNotification(task);
      notifyListeners();
    }).catchError((e) {
      task.status = TaskStatus.failed;
      task.errorMessage = e.toString();
      fileSystem.refresh();
      _updateTaskNotification(task);
      notifyListeners();
    });
  }

  // Start a Move Task
  void startMoveTask(
    List<String> srcPaths,
    String destDirPath,
    FileSystemProvider fileSystem,
  ) {
    final srcPathsCopy = List<String>.from(srcPaths); // Fix concurrent modification
    final id = _uuid.v4();
    final name = srcPathsCopy.length == 1
        ? 'Moving ${srcPathsCopy[0].split(Platform.pathSeparator).last}'
        : 'Moving ${srcPathsCopy.length} items';

    final task = BackgroundTask(
      id: id,
      name: name,
      type: TaskType.move,
      targetPaths: [destDirPath],
    );

    _tasks.add(task);
    _updateTaskNotification(task);
    notifyListeners();

    _storageService.moveItems(srcPathsCopy, destDirPath, task, () {
      _updateTaskNotification(task);
      notifyListeners();
    }).then((_) {
      fileSystem.refresh();
      _updateTaskNotification(task);
      notifyListeners();
    }).catchError((e) {
      task.status = TaskStatus.failed;
      task.errorMessage = e.toString();
      fileSystem.refresh();
      _updateTaskNotification(task);
      notifyListeners();
    });
  }

  // Start a Delete Task
  void startDeleteTask(
    List<String> paths,
    FileSystemProvider fileSystem,
  ) {
    final pathsCopy = List<String>.from(paths); // Fix concurrent modification
    final id = _uuid.v4();
    final name = pathsCopy.length == 1
        ? 'Deleting ${pathsCopy[0].split(Platform.pathSeparator).last}'
        : 'Deleting ${pathsCopy.length} items';

    final task = BackgroundTask(
      id: id,
      name: name,
      type: TaskType.delete,
      targetPaths: const [],
    );

    _tasks.add(task);
    _updateTaskNotification(task);
    notifyListeners();

    _storageService.deleteItems(pathsCopy, task, () {
      _updateTaskNotification(task);
      notifyListeners();
    }).then((_) {
      fileSystem.refresh();
      _updateTaskNotification(task);
      notifyListeners();
    }).catchError((e) {
      task.status = TaskStatus.failed;
      task.errorMessage = e.toString();
      fileSystem.refresh();
      _updateTaskNotification(task);
      notifyListeners();
    });
  }

  // Start a Zip Compression Task
  void startCompressTask(
    List<String> srcPaths,
    String targetZipPath,
    FileSystemProvider fileSystem, {
    int compressionLevel = 1, // BEST_SPEED
  }) {
    final srcPathsCopy = List<String>.from(srcPaths); // Fix concurrent modification
    final id = _uuid.v4();
    final name = 'Compressing to ${targetZipPath.split(Platform.pathSeparator).last}';

    final task = BackgroundTask(
      id: id,
      name: name,
      type: TaskType.zip,
      targetPaths: [targetZipPath],
    );

    _tasks.add(task);
    _updateTaskNotification(task);
    notifyListeners();

    _archiveService
        .compress(srcPathsCopy, targetZipPath, task, () {
          _updateTaskNotification(task);
          notifyListeners();
        }, compressionLevel: compressionLevel)
        .then((_) {
      fileSystem.refresh();
      _updateTaskNotification(task);
      notifyListeners();
    }).catchError((e) {
      task.status = TaskStatus.failed;
      task.errorMessage = e.toString();
      fileSystem.refresh();
      _updateTaskNotification(task);
      notifyListeners();
    });
  }

  // Start a Zip Extraction Task
  void startExtractTask(
    String zipPath,
    String destDirPath,
    FileSystemProvider fileSystem,
  ) {
    final id = _uuid.v4();
    final name = 'Extracting ${zipPath.split(Platform.pathSeparator).last}';

    final task = BackgroundTask(
      id: id,
      name: name,
      type: TaskType.unzip,
      targetPaths: [destDirPath],
    );

    _tasks.add(task);
    _updateTaskNotification(task);
    notifyListeners();

    _archiveService.extract(zipPath, destDirPath, task, () {
      _updateTaskNotification(task);
      notifyListeners();
    }).then((_) {
      fileSystem.refresh();
      _updateTaskNotification(task);
      notifyListeners();
    }).catchError((e) {
      task.status = TaskStatus.failed;
      task.errorMessage = e.toString();
      fileSystem.refresh();
      _updateTaskNotification(task);
      notifyListeners();
    });
  }

  void startConversionTask(
    String srcPath,
    String destPath,
    String type,
    FileSystemProvider fileSystem,
  ) {
    final id = _uuid.v4();
    final filename = srcPath.split(Platform.pathSeparator).last;
    final name = 'Converting $filename';

    final task = BackgroundTask(
      id: id,
      name: name,
      type: type == 'pdf_to_docx' ? TaskType.move : TaskType.zip,
      targetPaths: [destPath],
    );

    _tasks.add(task);
    _updateTaskNotification(task);
    notifyListeners();

    Future<void> conversionFuture;
    if (type == 'image_to_pdf') {
      conversionFuture = _conversionService.convertImageToPdf(srcPath, destPath, task, () {
        _updateTaskNotification(task);
        notifyListeners();
      });
    } else if (type == 'docx_to_pdf') {
      conversionFuture = _conversionService.convertDocxToPdf(srcPath, destPath, task, () {
        _updateTaskNotification(task);
        notifyListeners();
      });
    } else if (type == 'pptx_to_pdf') {
      conversionFuture = _conversionService.convertPptxToPdf(srcPath, destPath, task, () {
        _updateTaskNotification(task);
        notifyListeners();
      });
    } else if (type == 'pdf_to_docx') {
      conversionFuture = _conversionService.convertPdfToDocx(srcPath, destPath, task, () {
        _updateTaskNotification(task);
        notifyListeners();
      });
    } else {
      conversionFuture = Future.error('Unknown conversion type');
    }

    conversionFuture.then((_) {
      fileSystem.refresh();
      _updateTaskNotification(task);
      notifyListeners();
    }).catchError((e) {
      task.status = TaskStatus.failed;
      task.errorMessage = e.toString();
      fileSystem.refresh();
      _updateTaskNotification(task);
      notifyListeners();
    });
  }
}
