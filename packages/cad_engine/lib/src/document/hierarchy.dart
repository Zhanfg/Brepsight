enum EngineeringNodeKind {
  document,
  assembly,
  part,
  body,
  solid,
  shell,
  mesh,
  drawing,
  resultSet,
  toolpath,
  unknown,
}

class EngineeringTransform {
  const EngineeringTransform({required this.matrix4x4});

  /// Column-major 4x4 transform. Keeping this neutral avoids leaking OCCT,
  /// FreeCAD, Rhino or glTF transform types into Flutter.
  final List<double> matrix4x4;

  static const identity = EngineeringTransform(
    matrix4x4: <double>[
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ],
  );

  factory EngineeringTransform.fromMap(Map<Object?, Object?> map) {
    final values = (map['matrix'] as List<Object?>?)
            ?.whereType<num>()
            .map((value) => value.toDouble())
            .toList(growable: false) ??
        const <double>[];
    return values.length == 16
        ? EngineeringTransform(matrix4x4: values)
        : identity;
  }
}

class EngineeringHierarchyNode {
  const EngineeringHierarchyNode({
    required this.id,
    required this.parentId,
    required this.kind,
    required this.name,
    required this.visible,
    required this.transform,
    this.sourceRef,
    this.hasExactGeometry = false,
    this.hasMesh = false,
  });

  /// Stable within the lifetime of the imported EngineeringDocument.
  final String id;
  final String? parentId;
  final EngineeringNodeKind kind;
  final String name;
  final bool visible;
  final EngineeringTransform transform;

  /// Provider-specific breadcrumb for diagnostics only. UI logic must not use
  /// this as an identity because it may be a STEP/XCAF label path, FreeCAD
  /// object name, Rhino object UUID, etc.
  final String? sourceRef;
  final bool hasExactGeometry;
  final bool hasMesh;

  factory EngineeringHierarchyNode.fromMap(Map<Object?, Object?> map) {
    final rawKind = (map['kind'] as String?) ?? 'unknown';
    final kind = EngineeringNodeKind.values.firstWhere(
      (value) => value.name == rawKind,
      orElse: () => EngineeringNodeKind.unknown,
    );
    return EngineeringHierarchyNode(
      id: (map['id'] as String?) ?? '',
      parentId: map['parentId'] as String?,
      kind: kind,
      name: (map['name'] as String?) ?? '',
      visible: map['visible'] != false,
      transform: EngineeringTransform.fromMap(
        (map['transform'] as Map<Object?, Object?>?) ?? const {},
      ),
      sourceRef: map['sourceRef'] as String?,
      hasExactGeometry: map['hasExactGeometry'] == true,
      hasMesh: map['hasMesh'] == true,
    );
  }
}

class EngineeringHierarchy {
  const EngineeringHierarchy({required this.nodes});

  final List<EngineeringHierarchyNode> nodes;

  List<EngineeringHierarchyNode> roots() =>
      nodes.where((node) => node.parentId == null).toList(growable: false);

  List<EngineeringHierarchyNode> childrenOf(String parentId) =>
      nodes.where((node) => node.parentId == parentId).toList(growable: false);

  factory EngineeringHierarchy.fromList(List<Object?> raw) {
    return EngineeringHierarchy(
      nodes: raw
          .whereType<Map<Object?, Object?>>()
          .map(EngineeringHierarchyNode.fromMap)
          .where((node) => node.id.isNotEmpty)
          .toList(growable: false),
    );
  }
}
