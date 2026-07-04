import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart';

class ThumbnailService {
  static final Map<String, Future<Uint8List?>> _videoCache = {};

  static const Set<String> imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
  };

  static const Set<String> videoExtensions = {
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.webm',
    '.3gp',
  };

  static bool isImagePath(String path) {
    return imageExtensions.contains(p.extension(path).toLowerCase());
  }

  static bool isVideoPath(String path) {
    return videoExtensions.contains(p.extension(path).toLowerCase());
  }

  static Future<Uint8List?> videoThumbnail(String path) {
    return _videoCache.putIfAbsent(path, () async {
      if (!Platform.isAndroid && !Platform.isIOS) return null;
      try {
        return await VideoThumbnail.thumbnailData(
          video: path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 160,
          quality: 50,
        );
      } catch (e) {
        debugPrint('Video thumbnail failed for $path: $e');
        return null;
      }
    });
  }
}
