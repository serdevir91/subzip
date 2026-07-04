import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

enum FileCategoryType { extension, folder }

class FileCategory {
  final String id;
  final String label;
  final FileCategoryType type;
  final String iconName;
  final List<String> extensions;
  final String? folderPath;
  final bool editable;

  const FileCategory({
    required this.id,
    required this.label,
    required this.type,
    required this.iconName,
    this.extensions = const [],
    this.folderPath,
    this.editable = false,
  });

  bool matchesPath(String path, {required bool isDirectory}) {
    if (type == FileCategoryType.folder) {
      final folder = folderPath;
      if (folder == null || folder.trim().isEmpty) return false;
      return _isSameOrChildPath(path, folder);
    }

    if (isDirectory) return false;
    return extensions.contains(p.extension(path).toLowerCase());
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'type': type.name,
      'iconName': iconName,
      'extensions': extensions,
      'folderPath': folderPath,
      'editable': editable,
    };
  }

  factory FileCategory.fromJson(Map<String, dynamic> json) {
    return FileCategory(
      id: json['id'] as String,
      label: json['label'] as String,
      type: FileCategoryType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => FileCategoryType.folder,
      ),
      iconName: json['iconName'] as String? ?? 'folder',
      extensions:
          (json['extensions'] as List<dynamic>?)?.cast<String>() ?? const [],
      folderPath: json['folderPath'] as String?,
      editable: json['editable'] as bool? ?? true,
    );
  }

  FileCategory copyWith({
    String? id,
    String? label,
    FileCategoryType? type,
    String? iconName,
    List<String>? extensions,
    String? folderPath,
    bool? editable,
  }) {
    return FileCategory(
      id: id ?? this.id,
      label: label ?? this.label,
      type: type ?? this.type,
      iconName: iconName ?? this.iconName,
      extensions: extensions ?? this.extensions,
      folderPath: folderPath ?? this.folderPath,
      editable: editable ?? this.editable,
    );
  }

  static const builtInCategories = <FileCategory>[
    FileCategory(
      id: 'images',
      label: 'Photos',
      type: FileCategoryType.extension,
      iconName: 'photos',
      extensions: ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic'],
    ),
    FileCategory(
      id: 'videos',
      label: 'Videos',
      type: FileCategoryType.extension,
      iconName: 'videos',
      extensions: ['.mp4', '.mkv', '.avi', '.mov', '.webm', '.3gp'],
    ),
    FileCategory(
      id: 'audio',
      label: 'Audio',
      type: FileCategoryType.extension,
      iconName: 'audio',
      extensions: ['.mp3', '.wav', '.ogg', '.m4a', '.flac', '.aac'],
    ),
    FileCategory(
      id: 'documents',
      label: 'Documents',
      type: FileCategoryType.extension,
      iconName: 'documents',
      extensions: [
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
      ],
    ),
    FileCategory(
      id: 'apk',
      label: 'APK',
      type: FileCategoryType.extension,
      iconName: 'apk',
      extensions: ['.apk', '.xapk', '.apks'],
    ),
  ];

  static FileCategory? builtInById(String id) {
    for (final category in builtInCategories) {
      if (category.id == id) return category;
    }
    return null;
  }

  static IconData iconFor(String iconName) {
    switch (iconName) {
      case 'photos':
        return Icons.photo_library_rounded;
      case 'videos':
        return Icons.video_collection_rounded;
      case 'audio':
        return Icons.music_note_rounded;
      case 'documents':
        return Icons.description_rounded;
      case 'apk':
        return Icons.android_rounded;
      case 'download':
        return Icons.download_for_offline_rounded;
      default:
        return Icons.folder_rounded;
    }
  }

  static bool _isSameOrChildPath(String path, String parentPath) {
    final normalizedPath = p.normalize(path);
    final normalizedParent = p.normalize(parentPath);
    if (Platform.isWindows) {
      final lowerPath = normalizedPath.toLowerCase();
      final lowerParent = normalizedParent.toLowerCase();
      return lowerPath == lowerParent || p.isWithin(lowerParent, lowerPath);
    }
    return normalizedPath == normalizedParent ||
        p.isWithin(normalizedParent, normalizedPath);
  }
}
