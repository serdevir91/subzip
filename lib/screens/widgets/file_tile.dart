import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/shared_file.dart';
import '../../models/folder_style.dart';
import '../../services/thumbnail_service.dart';

class FileTile extends StatelessWidget {
  final SharedFile file;
  final bool isSelected;
  final bool isSelectionMode;
  final FolderStyle? folderStyle;
  final bool isFavorite;
  final bool isGridView;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Function(String action) onActionSelected;

  const FileTile({
    super.key,
    required this.file,
    required this.isSelected,
    required this.isSelectionMode,
    this.folderStyle,
    required this.isFavorite,
    required this.isGridView,
    required this.onTap,
    required this.onLongPress,
    required this.onActionSelected,
  });

  IconData _getFileIcon() {
    if (Platform.isWindows && file.path.endsWith(':\\')) {
      return Icons.storage_rounded;
    }

    if (file.isDirectory) {
      if (folderStyle != null) {
        switch (folderStyle!.iconType) {
          case 'secure':
            return Icons.folder_shared_rounded;
          case 'media':
            return Icons.folder_zip_rounded;
          case 'code':
            return Icons.source_rounded;
          case 'document':
            return Icons.topic_rounded;
          case 'music':
            return Icons.music_note_rounded;
          case 'game':
            return Icons.sports_esports_rounded;
          case 'download':
            return Icons.download_rounded;
          default:
            return Icons.folder_rounded;
        }
      }
      return Icons.folder_rounded;
    }

    final ext = p.extension(file.path).toLowerCase();
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
      case '.mov':
      case '.webm':
        return Icons.movie_creation_rounded;
      case '.mp3':
      case '.wav':
      case '.ogg':
      case '.m4a':
      case '.flac':
        return Icons.music_note_rounded;
      case '.pdf':
        return Icons.picture_as_pdf_rounded;
      case '.zip':
      case '.rar':
      case '.tar':
      case '.gz':
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

  Color _getIconColor(ThemeData theme) {
    if (Platform.isWindows && file.path.endsWith(':\\')) {
      return theme.colorScheme.primary;
    }

    if (file.isDirectory) {
      if (folderStyle != null) {
        final hex = folderStyle!.colorHex.replaceAll('#', '');
        return Color(int.parse('FF$hex', radix: 16));
      }
      return theme.colorScheme.primary;
    }

    final ext = p.extension(file.path).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.webp':
        return Colors.blue.shade400;
      case '.mp4':
      case '.mkv':
      case '.avi':
        return Colors.red.shade400;
      case '.mp3':
      case '.wav':
        return Colors.purple.shade400;
      case '.pdf':
        return Colors.orange.shade800;
      case '.zip':
      case '.rar':
      case '.7z':
        return Colors.teal.shade400;
      case '.txt':
      case '.docx':
      case '.xlsx':
        return Colors.green.shade400;
      default:
        return theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    }
  }

  Widget _buildPreview({
    required ThemeData theme,
    required IconData iconData,
    required Color iconColor,
    required double size,
  }) {
    if (!file.isDirectory &&
        !file.path.endsWith(':\\') &&
        ThumbnailService.isImagePath(file.path) &&
        File(file.path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(file.path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Icon(iconData, color: iconColor, size: size * 0.72),
        ),
      );
    }

    if (!file.isDirectory &&
        !file.path.endsWith(':\\') &&
        ThumbnailService.isVideoPath(file.path)) {
      return FutureBuilder(
        future: ThumbnailService.videoThumbnail(file.path),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return Icon(iconData, color: iconColor, size: size * 0.72);
          }
          return Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  bytes,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
              ),
              Container(
                width: size * 0.34,
                height: size * 0.34,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: size * 0.26,
                ),
              ),
            ],
          );
        },
      );
    }

    return Icon(iconData, color: iconColor, size: size * 0.72);
  }

  void _showRightClickMenu(BuildContext context, TapUpDetails details) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(details.globalPosition, details.globalPosition),
      Offset.zero & overlay.size,
    );

    final ext = p.extension(file.path).toLowerCase();
    final isZip = ext == '.zip';
    final canConvertToPdf = [
      '.docx',
      '.pptx',
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
    ].contains(ext);
    final canConvertToWord = ext == '.pdf';

    showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        if (file.isDirectory)
          const PopupMenuItem(
            value: 'style',
            child: Row(
              children: [
                Icon(Icons.palette_rounded, size: 20),
                SizedBox(width: 8),
                Text('Edit Appearance'),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'favorite',
          child: Row(
            children: [
              Icon(
                isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(isFavorite ? 'Remove Favorite' : 'Add Favorite'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (isZip)
          const PopupMenuItem(
            value: 'extract',
            child: Row(
              children: [
                Icon(Icons.unarchive_rounded, size: 20),
                SizedBox(width: 8),
                Text('Extract Here'),
              ],
            ),
          ),
        if (!file.isDirectory) ...[
          const PopupMenuItem(
            value: 'compress',
            child: Row(
              children: [
                Icon(Icons.archive_rounded, size: 20),
                SizedBox(width: 8),
                Text('Compress (ZIP)'),
              ],
            ),
          ),
          if (canConvertToPdf)
            const PopupMenuItem(
              value: 'convert_pdf',
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Convert to PDF'),
                ],
              ),
            ),
          if (canConvertToWord)
            const PopupMenuItem(
              value: 'convert_word',
              child: Row(
                children: [
                  Icon(Icons.description_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Convert to Word'),
                ],
              ),
            ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              Icon(Icons.share_rounded, size: 20),
              SizedBox(width: 8),
              Text('Share'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 20),
              SizedBox(width: 8),
              Text('Copy'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'cut',
          child: Row(
            children: [
              Icon(Icons.cut_rounded, size: 20),
              SizedBox(width: 8),
              Text('Cut'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 20),
              SizedBox(width: 8),
              Text('Rename'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'select',
          child: Row(
            children: [
              Icon(Icons.check_box_outlined, size: 20),
              SizedBox(width: 8),
              Text('Select'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
                size: 20,
              ),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        onActionSelected(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconColor = _getIconColor(theme);
    final iconData = _getFileIcon();

    // Grid View Card Layout
    if (isGridView) {
      return GestureDetector(
        onSecondaryTapUp: (details) => _showRightClickMenu(context, details),
        child: Card(
          color: isSelected
              ? theme.colorScheme.primary.withValues(
                  alpha: isDark ? 0.15 : 0.08,
                )
              : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
          elevation: isSelected ? 4 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isSelected
                  ? theme.colorScheme.primary
                  : (isDark ? const Color(0x1BFFFFFF) : Colors.grey.shade200),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              children: [
                // Favorite Star Indicator
                if (isFavorite)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Icon(
                      Icons.star_rounded,
                      color: Colors.amber.shade600,
                      size: 18,
                    ),
                  ),
                // Selection Checkbox
                if (isSelectionMode)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) => onTap(),
                      shape: const CircleBorder(),
                      activeColor: theme.colorScheme.primary,
                    ),
                  )
                else
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _buildPopupMenuButton(context),
                  ),

                // Main Icon & Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Center(
                          child: _buildPreview(
                            theme: theme,
                            iconData: iconData,
                            iconColor: iconColor,
                            size: 64,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        file.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        file.isDirectory ? 'Folder' : file.sizeFormatted,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // List View Tile Layout
    return GestureDetector(
      onSecondaryTapUp: (details) => _showRightClickMenu(context, details),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(
                  alpha: isDark ? 0.15 : 0.08,
                )
              : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : (isDark ? const Color(0x0EFFFFFF) : Colors.grey.shade200),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          onTap: onTap,
          onLongPress: onLongPress,
          leading: isSelectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => onTap(),
                  shape: const CircleBorder(),
                  activeColor: theme.colorScheme.primary,
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    _buildPreview(
                      theme: theme,
                      iconData: iconData,
                      iconColor: iconColor,
                      size: 44,
                    ),
                    if (isFavorite)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black : Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.star_rounded,
                            color: Colors.amber.shade600,
                            size: 14,
                          ),
                        ),
                      ),
                  ],
                ),
          title: Text(
            file.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            file.isDirectory
                ? 'Folder'
                : '${file.sizeFormatted} • ${file.dateFormatted}',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
          ),
          trailing: isSelectionMode ? null : _buildPopupMenuButton(context),
        ),
      ),
    );
  }

  Widget _buildPopupMenuButton(BuildContext context) {
    final theme = Theme.of(context);
    final ext = p.extension(file.path).toLowerCase();
    final isZip = ext == '.zip';
    final canConvertToPdf = [
      '.docx',
      '.pptx',
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
    ].contains(ext);
    final canConvertToWord = ext == '.pdf';

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: theme.colorScheme.outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: onActionSelected,
      itemBuilder: (context) => [
        if (file.isDirectory)
          const PopupMenuItem(
            value: 'style',
            child: Row(
              children: [
                Icon(Icons.palette_rounded, size: 20),
                SizedBox(width: 8),
                Text('Edit Appearance'),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'favorite',
          child: Row(
            children: [
              Icon(
                isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(isFavorite ? 'Remove Favorite' : 'Add Favorite'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (isZip)
          const PopupMenuItem(
            value: 'extract',
            child: Row(
              children: [
                Icon(Icons.unarchive_rounded, size: 20),
                SizedBox(width: 8),
                Text('Extract Here'),
              ],
            ),
          ),
        if (!file.isDirectory) ...[
          const PopupMenuItem(
            value: 'compress',
            child: Row(
              children: [
                Icon(Icons.archive_rounded, size: 20),
                SizedBox(width: 8),
                Text('Compress (ZIP)'),
              ],
            ),
          ),
          if (canConvertToPdf)
            const PopupMenuItem(
              value: 'convert_pdf',
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Convert to PDF'),
                ],
              ),
            ),
          if (canConvertToWord)
            const PopupMenuItem(
              value: 'convert_word',
              child: Row(
                children: [
                  Icon(Icons.description_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Convert to Word'),
                ],
              ),
            ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              Icon(Icons.share_rounded, size: 20),
              SizedBox(width: 8),
              Text('Share'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 20),
              SizedBox(width: 8),
              Text('Copy'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'cut',
          child: Row(
            children: [
              Icon(Icons.cut_rounded, size: 20),
              SizedBox(width: 8),
              Text('Cut'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 20),
              SizedBox(width: 8),
              Text('Rename'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'select',
          child: Row(
            children: [
              Icon(Icons.check_box_outlined, size: 20),
              SizedBox(width: 8),
              Text('Select'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
                size: 20,
              ),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    );
  }
}
