import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import '../providers/file_system_provider.dart';
import '../models/shared_file.dart';
import 'widgets/file_tile.dart';

class FavoritesScreen extends StatelessWidget {
  final Function(String path) onNavigateToFolder;

  const FavoritesScreen({
    super.key,
    required this.onNavigateToFolder,
  });

  List<SharedFile> _resolveFavorites(FileSystemProvider fileSystem, Set<String> paths) {
    final List<SharedFile> resolved = [];
    final List<String> toRemove = [];
    for (final path in paths) {
      try {
        final file = File(path);
        final dir = Directory(path);
        
        if (dir.existsSync()) {
          resolved.add(SharedFile.fromFileSystemEntity(dir));
        } else if (file.existsSync()) {
          resolved.add(SharedFile.fromFileSystemEntity(file));
        } else {
          // File/dir has been deleted — mark for removal
          toRemove.add(path);
        }
      } catch (_) {
        toRemove.add(path);
      }
    }
    // Clean up deleted favorites
    for (final path in toRemove) {
      fileSystem.toggleFavorite(path);
    }
    return resolved;
  }

  @override
  Widget build(BuildContext context) {
    final fileSystem = Provider.of<FileSystemProvider>(context);
    final theme = Theme.of(context);

    final favoriteFiles = _resolveFavorites(fileSystem, fileSystem.favoritePaths);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: favoriteFiles.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.star_outline_rounded,
                    size: 64,
                    color: theme.colorScheme.outline.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No favorites added yet.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You can star files and folders from their context menu.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: favoriteFiles.length,
              itemBuilder: (context, index) {
                final file = favoriteFiles[index];
                
                return FileTile(
                  file: file,
                  isSelected: false,
                  isSelectionMode: false,
                  folderStyle: fileSystem.getFolderStyle(file.path),
                  isFavorite: true,
                  isGridView: false,
                  onTap: () async {
                    if (file.isDirectory) {
                      onNavigateToFolder(file.path);
                    } else {
                      await OpenFilex.open(file.path);
                    }
                  },
                  onLongPress: () {},
                  onActionSelected: (action) async {
                    if (action == 'favorite') {
                      await fileSystem.toggleFavorite(file.path);
                    } else if (action == 'copy') {
                      fileSystem.toggleSelection(file.path);
                      fileSystem.copySelected();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied. Navigate to destination folder to paste.')),
                      );
                    } else if (action == 'cut') {
                      fileSystem.toggleSelection(file.path);
                      fileSystem.cutSelected();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cut. Navigate to destination folder to paste.')),
                      );
                    } else if (action == 'delete') {
                      await fileSystem.toggleFavorite(file.path);
                      final f = File(file.path);
                      final d = Directory(file.path);
                      if (f.existsSync()) {
                        await f.delete();
                      } else if (d.existsSync()) {
                        await d.delete(recursive: true);
                      }
                      fileSystem.refresh();
                    }
                  },
                );
              },
            ),
    );
  }
}
