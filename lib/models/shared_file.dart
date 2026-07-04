import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

class SharedFile {
  final String name;
  final String path;
  final int size;
  final DateTime dateModified;
  final bool isDirectory;

  SharedFile({
    required this.name,
    required this.path,
    required this.size,
    required this.dateModified,
    required this.isDirectory,
  });

  factory SharedFile.fromFileSystemEntity(FileSystemEntity entity) {
    final stat = entity.statSync();
    return SharedFile(
      name: p.basename(entity.path),
      path: entity.path,
      size: entity is Directory ? 0 : stat.size,
      dateModified: stat.modified,
      isDirectory: entity is Directory,
    );
  }

  factory SharedFile.fromPathLite({
    required String path,
    required bool isDirectory,
  }) {
    return SharedFile(
      name: p.basename(path),
      path: path,
      size: 0,
      dateModified: DateTime.now(),
      isDirectory: isDirectory,
    );
  }

  String get sizeFormatted {
    if (isDirectory) return '';
    if (size <= 0) return '0 B';
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    double bytes = size.toDouble();
    int suffixIndex = 0;
    while (bytes >= 1024 && suffixIndex < suffixes.length - 1) {
      bytes /= 1024;
      suffixIndex++;
    }
    return '${bytes.toStringAsFixed(1)} ${suffixes[suffixIndex]}';
  }

  String get dateFormatted {
    return DateFormat('dd.MM.yyyy HH:mm').format(dateModified);
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'size': size,
      'dateModified': dateModified.toIso8601String(),
      'isDirectory': isDirectory,
    };
  }

  factory SharedFile.fromJson(Map<String, dynamic> json) {
    return SharedFile(
      name: json['name'] as String,
      path: json['path'] as String,
      size: json['size'] as int,
      dateModified: DateTime.parse(json['dateModified'] as String),
      isDirectory: json['isDirectory'] as bool,
    );
  }
}
