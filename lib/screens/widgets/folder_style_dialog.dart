import 'package:flutter/material.dart';
import '../../models/folder_style.dart';

class FolderStyleDialog extends StatefulWidget {
  final String folderPath;
  final FolderStyle? currentStyle;
  final Function(String colorHex, String iconType) onSave;
  final VoidCallback onClear;

  const FolderStyleDialog({
    super.key,
    required this.folderPath,
    this.currentStyle,
    required this.onSave,
    required this.onClear,
  });

  @override
  State<FolderStyleDialog> createState() => _FolderStyleDialogState();
}

class _FolderStyleDialogState extends State<FolderStyleDialog> {
  late String _selectedColorHex;
  late String _selectedIconType;

  final List<Map<String, dynamic>> _colors = [
    {'name': 'Orange (Default)', 'hex': '#FFA500', 'color': Colors.orange},
    {'name': 'Blue', 'hex': '#2196F3', 'color': Colors.blue},
    {'name': 'Green', 'hex': '#4CAF50', 'color': Colors.green},
    {'name': 'Red', 'hex': '#F44336', 'color': Colors.red},
    {'name': 'Purple', 'hex': '#9C27B0', 'color': Colors.purple},
    {'name': 'Teal', 'hex': '#009688', 'color': Colors.teal},
    {'name': 'Pink', 'hex': '#E91E63', 'color': Colors.pink},
    {'name': 'Cyan', 'hex': '#00BCD4', 'color': Colors.cyan},
  ];

  final List<Map<String, dynamic>> _icons = [
    {'type': 'default', 'label': 'Default', 'icon': Icons.folder_rounded},
    {'type': 'secure', 'label': 'Secure', 'icon': Icons.folder_shared_rounded},
    {'type': 'media', 'label': 'Media', 'icon': Icons.folder_zip_rounded},
    {'type': 'code', 'label': 'Code/Dev', 'icon': Icons.source_rounded},
    {'type': 'document', 'label': 'Document', 'icon': Icons.topic_rounded},
    {'type': 'music', 'label': 'Music', 'icon': Icons.music_note_rounded},
    {'type': 'game', 'label': 'Game', 'icon': Icons.sports_esports_rounded},
    {'type': 'download', 'label': 'Download', 'icon': Icons.download_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _selectedColorHex = widget.currentStyle?.colorHex ?? '#FFA500';
    _selectedIconType = widget.currentStyle?.iconType ?? 'default';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark ? const Color(0x1BFFFFFF) : Colors.transparent,
          width: 1.0,
        ),
      ),
      title: const Text(
        'Customize Folder Style',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Folder Color',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 60,
              width: double.maxFinite,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _colors.length,
                itemBuilder: (context, index) {
                  final colorItem = _colors[index];
                  final hex = colorItem['hex'] as String;
                  final color = colorItem['color'] as Color;
                  final isSelected = _selectedColorHex == hex;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedColorHex = hex;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color: isDark ? Colors.white : Colors.black87,
                                width: 3.0,
                              )
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withOpacity(0.5),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                )
                              ]
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 32),
            const Text(
              'Folder Type / Icon',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.0,
              ),
              itemCount: _icons.length,
              itemBuilder: (context, index) {
                final iconItem = _icons[index];
                final type = iconItem['type'] as String;
                final iconData = iconItem['icon'] as IconData;
                final label = iconItem['label'] as String;
                final isSelected = _selectedIconType == type;

                // Color derived from selection
                final baseColor = _colors.firstWhere(
                  (c) => c['hex'] == _selectedColorHex,
                  orElse: () => _colors[0],
                )['color'] as Color;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedIconType = type;
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? baseColor.withOpacity(0.15)
                          : (isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? baseColor : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          iconData,
                          color: isSelected ? baseColor : (isDark ? Colors.grey : Colors.grey.shade600),
                          size: 28,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? baseColor
                                : (isDark ? Colors.white70 : Colors.black87),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        if (widget.currentStyle != null)
          TextButton(
            onPressed: () {
              widget.onClear();
              Navigator.pop(context);
            },
            child: const Text(
              'Reset',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _colors.firstWhere(
              (c) => c['hex'] == _selectedColorHex,
              orElse: () => _colors[0],
            )['color'] as Color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () {
            widget.onSave(_selectedColorHex, _selectedIconType);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
