class FolderStyle {
  final String colorHex;
  final String iconType;

  FolderStyle({
    required this.colorHex,
    required this.iconType,
  });

  Map<String, dynamic> toJson() {
    return {
      'colorHex': colorHex,
      'iconType': iconType,
    };
  }

  factory FolderStyle.fromJson(Map<String, dynamic> json) {
    return FolderStyle(
      colorHex: json['colorHex'] as String? ?? '#FFA500',
      iconType: json['iconType'] as String? ?? 'default',
    );
  }
}
