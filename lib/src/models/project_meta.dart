/// The `project.json` format tag.
const projectFormatV1 = 'project_v1';

/// A resource entry in the project index (`project.json` → `resources[]`):
/// the family of an imported image and the last-used background-removal
/// tolerance.
class ResourceMeta {
  /// File name without extension.
  String id;

  /// `'texture'` or `'sprite'`.
  String family;

  /// Last-used background removal tolerance (0..100).
  double tolerance;

  ResourceMeta({
    required this.id,
    required this.family,
    this.tolerance = 30,
  });

  Map<String, Object> toJson() =>
      {'id': id, 'family': family, 'tolerance': tolerance};

  factory ResourceMeta.fromJson(Object? json) {
    final m = (json as Map?) ?? {};
    final tol = m['tolerance'];
    return ResourceMeta(
      id: (m['id'] as String?) ?? '',
      family: (m['family'] as String?) ?? 'texture',
      tolerance: tol is num ? tol.toDouble() : 30,
    );
  }
}
