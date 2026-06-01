import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class BreadcrumbBar extends StatelessWidget {
  final String currentPath;
  final String rootPath;
  final Function(String path) onNavigate;

  const BreadcrumbBar({
    super.key,
    required this.currentPath,
    required this.rootPath,
    required this.onNavigate,
  });

  List<Widget> _buildCrumbs(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    if (Platform.isWindows) {
      if (currentPath == 'Computer') {
        return [
          Icon(Icons.computer_rounded, size: 16, color: accentColor),
          const SizedBox(width: 4),
          Text(
            'This PC',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ];
      }

      final parts = currentPath
          .split(Platform.pathSeparator)
          .where((s) => s.isNotEmpty)
          .toList();
      
      final drive = currentPath.substring(0, 3); // e.g. "C:\"
      final isDriveLast = parts.isEmpty || (parts.length == 1 && parts[0].endsWith(':'));

      List<Widget> crumbs = [
        GestureDetector(
          onTap: () => onNavigate('Computer'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.computer_rounded, size: 16, color: accentColor),
              const SizedBox(width: 4),
              Text(
                'This PC',
                style: TextStyle(color: accentColor, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 16, color: theme.colorScheme.outline),
        GestureDetector(
          onTap: isDriveLast ? null : () => onNavigate(drive),
          child: Text(
            drive,
            style: TextStyle(
              color: isDriveLast ? theme.colorScheme.onSurface : accentColor,
              fontWeight: isDriveLast ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ];

      var accumPath = drive;
      for (int i = 0; i < parts.length; i++) {
        if (i == 0 && parts[i].endsWith(':')) continue;
        crumbs.add(Icon(Icons.chevron_right_rounded, size: 16, color: theme.colorScheme.outline));
        accumPath = p.join(accumPath, parts[i]);
        final currentAccumPath = accumPath;
        final isLast = i == parts.length - 1;

        crumbs.add(
          Flexible(
            child: GestureDetector(
              onTap: isLast ? null : () => onNavigate(currentAccumPath),
              child: Text(
                parts[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isLast ? FontWeight.bold : FontWeight.w500,
                  color: isLast ? theme.colorScheme.onSurface : accentColor,
                ),
              ),
            ),
          ),
        );
      }
      return crumbs;
    }

    // Android/Linux Path Handling
    if (currentPath == rootPath) {
      return [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_shared_rounded, size: 16, color: accentColor),
            const SizedBox(width: 4),
            Text(
              'Storage Root',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ];
    }

    final relative = currentPath.replaceFirst(rootPath, '');
    final parts = relative
        .split(Platform.pathSeparator)
        .where((s) => s.isNotEmpty)
        .toList();

    List<Widget> crumbs = [
      GestureDetector(
        onTap: () => onNavigate(rootPath),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_shared_rounded, size: 16, color: accentColor),
            const SizedBox(width: 4),
            Text(
              'Root Directory',
              style: TextStyle(color: accentColor, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    ];

    var accumPath = rootPath;
    for (int i = 0; i < parts.length; i++) {
      crumbs.add(Icon(Icons.chevron_right_rounded, size: 16, color: theme.colorScheme.outline));
      accumPath = p.join(accumPath, parts[i]);
      final currentAccumPath = accumPath;
      final isLast = i == parts.length - 1;

      crumbs.add(
        Flexible(
          child: GestureDetector(
            onTap: isLast ? null : () => onNavigate(currentAccumPath),
            child: Text(
              parts[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isLast ? FontWeight.bold : FontWeight.w500,
                color: isLast ? theme.colorScheme.onSurface : accentColor,
              ),
            ),
          ),
        ),
      );
    }

    return crumbs;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161616) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0x0EFFFFFF) : Colors.grey.shade300,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _buildCrumbs(context),
        ),
      ),
    );
  }
}
