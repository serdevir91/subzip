import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import '../providers/task_provider.dart';
import '../models/background_task.dart';

class TasksScreen extends StatelessWidget {
  final Function(String path)? onNavigateToFolder;

  const TasksScreen({super.key, this.onNavigateToFolder});

  IconData _getTaskIcon(TaskType type) {
    switch (type) {
      case TaskType.copy:
        return Icons.copy_rounded;
      case TaskType.move:
        return Icons.drive_file_move_rounded;
      case TaskType.delete:
        return Icons.delete_forever_rounded;
      case TaskType.zip:
        return Icons.archive_rounded;
      case TaskType.unzip:
        return Icons.unarchive_rounded;
    }
  }

  Color _getStatusColor(TaskStatus status, Color accentColor) {
    switch (status) {
      case TaskStatus.running:
        return accentColor;
      case TaskStatus.paused:
        return Colors.amber.shade700;
      case TaskStatus.completed:
        return Colors.green.shade600;
      case TaskStatus.cancelled:
        return Colors.grey.shade600;
      case TaskStatus.failed:
        return Colors.red.shade600;
    }
  }

  String _getStatusText(TaskStatus status) {
    switch (status) {
      case TaskStatus.running:
        return 'Running';
      case TaskStatus.paused:
        return 'Paused';
      case TaskStatus.completed:
        return 'Completed';
      case TaskStatus.cancelled:
        return 'Cancelled';
      case TaskStatus.failed:
        return 'Failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context);
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Background Operations',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Remove Completed Tasks',
            onPressed: () {
              taskProvider.clearCompletedTasks();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Completed tasks cleared.')),
              );
            },
          ),
        ],
      ),
      body: taskProvider.tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.task_rounded,
                    size: 64,
                    color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No active operations.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Copy, move, zip, unzip, and delete operations show up here.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: taskProvider.tasks.length,
              itemBuilder: (context, index) {
                final task = taskProvider.tasks[index];
                final statusColor = _getStatusColor(task.status, accentColor);
                final percentage = (task.progress * 100).toInt();

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
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
                    onTap:
                        task.status == TaskStatus.completed &&
                            task.targetPaths.isNotEmpty
                        ? () async {
                            final path = task.targetPaths.first;
                            final isDir = Directory(path).existsSync();
                            final isFile = File(path).existsSync();

                            if (isDir) {
                              onNavigateToFolder?.call(path);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Navigating to: $path')),
                              );
                            } else if (isFile) {
                              await OpenFilex.open(path);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Target file or folder no longer exists.',
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: statusColor.withValues(
                                  alpha: 0.15,
                                ),
                                child: Icon(
                                  _getTaskIcon(task.type),
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            _getStatusText(task.status),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: statusColor,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (task.totalFiles > 0)
                                          Text(
                                            '${task.processedFiles}/${task.totalFiles} files',
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
                              if (task.status == TaskStatus.running ||
                                  task.status == TaskStatus.paused)
                                Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        task.status == TaskStatus.paused
                                            ? Icons.play_arrow_rounded
                                            : Icons.pause_rounded,
                                        color: statusColor,
                                      ),
                                      onPressed: () {
                                        if (task.status == TaskStatus.paused) {
                                          taskProvider.resumeTask(task.id);
                                        } else {
                                          taskProvider.pauseTask(task.id);
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.cancel_rounded,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () =>
                                          taskProvider.cancelTask(task.id),
                                    ),
                                  ],
                                )
                              else if (task.status == TaskStatus.completed)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.green,
                                )
                              else if (task.status == TaskStatus.cancelled)
                                const Icon(
                                  Icons.cancel_rounded,
                                  color: Colors.grey,
                                )
                              else if (task.status == TaskStatus.failed)
                                const Icon(
                                  Icons.error_rounded,
                                  color: Colors.redAccent,
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Progress Bar
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: task.progress,
                                    backgroundColor: isDark
                                        ? const Color(0xFF2C2C2C)
                                        : Colors.grey.shade200,
                                    color: statusColor,
                                    minHeight: 6,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '$percentage%',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                          if (task.currentMessage.isNotEmpty &&
                              (task.status == TaskStatus.running ||
                                  task.status == TaskStatus.paused)) ...[
                            const SizedBox(height: 8),
                            Text(
                              task.currentMessage,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.outline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (task.status == TaskStatus.failed &&
                              task.errorMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Error Detail: ${task.errorMessage}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.redAccent,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
