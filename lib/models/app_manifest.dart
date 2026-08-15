import 'dart:convert';

/// Metadata for a single Good Vibes app, read from its `manifest.json`.
class AppManifest {
  final String id;
  final String name;
  final String description;
  final String version;

  /// Relative path (from the app dir) to an icon file, or null.
  final String? icon;

  /// Entry HTML file, default `index.html`.
  final String entry;

  const AppManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    this.icon,
    this.entry = 'index.html',
  });

  factory AppManifest.fromJson(Map<String, dynamic> json) {
    return AppManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      description: json['description'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      icon: json['icon'] as String?,
      entry: json['entry'] as String? ?? 'index.html',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'version': version,
        if (icon != null) 'icon': icon,
        'entry': entry,
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}
