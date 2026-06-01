import 'dart:async';

enum TaskStatus { running, paused, completed, cancelled, failed }
enum TaskType { copy, move, delete, zip, unzip }

class BackgroundTask {
  final String id;
  final String name;
  final TaskType type;
  final List<String> targetPaths;
  
  TaskStatus status;
  double progress; // 0.0 to 1.0
  int totalFiles;
  int processedFiles;
  String currentMessage;
  String? errorMessage;

  bool pauseRequested = false;
  bool cancelRequested = false;

  // A completer to await when paused
  Completer<void>? _pauseCompleter;

  BackgroundTask({
    required this.id,
    required this.name,
    required this.type,
    this.targetPaths = const [],
    this.status = TaskStatus.running,
    this.progress = 0.0,
    this.totalFiles = 0,
    this.processedFiles = 0,
    this.currentMessage = '',
    this.errorMessage,
  });

  // Call this inside the worker loop to pause if requested
  Future<void> checkPause() async {
    if (pauseRequested && status == TaskStatus.running) {
      status = TaskStatus.paused;
      _pauseCompleter = Completer<void>();
      await _pauseCompleter!.future;
    }
  }

  void pause() {
    if (status == TaskStatus.running) {
      pauseRequested = true;
      status = TaskStatus.paused;
    }
  }

  void resume() {
    if (status == TaskStatus.paused) {
      pauseRequested = false;
      status = TaskStatus.running;
      _pauseCompleter?.complete();
      _pauseCompleter = null;
    }
  }

  void cancel() {
    cancelRequested = true;
    status = TaskStatus.cancelled;
    _pauseCompleter?.complete(); // Break out of pause if we cancel
    _pauseCompleter = null;
  }
}
