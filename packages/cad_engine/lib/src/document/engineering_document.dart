enum EngineeringRepresentation {
  exactGeometry,
  mesh,
  drawing,
  pointCloud,
  simulation,
  toolpath,
  bim,
  volumetric,
}

enum DocumentCapability {
  exactGeometry,
  meshGeometry,
  hierarchy,
  layers,
  materials,
  textures,
  pmi,
  units,
  animation,
  bimProperties,
  resultFields,
  toolpaths,
  pointAttributes,
}

class CapabilitySet {
  CapabilitySet([Iterable<DocumentCapability> values = const []])
      : values = Set.unmodifiable(values);

  final Set<DocumentCapability> values;

  bool contains(DocumentCapability capability) => values.contains(capability);

  bool containsAll(Iterable<DocumentCapability> capabilities) =>
      values.containsAll(capabilities);

  CapabilitySet union(Iterable<DocumentCapability> other) =>
      CapabilitySet({...values, ...other});
}

class DocumentProvenance {
  const DocumentProvenance({
    required this.sourcePath,
    required this.sourceFormatId,
    required this.providerId,
  });

  final String sourcePath;
  final String sourceFormatId;
  final String providerId;
}

class EngineeringDocument {
  EngineeringDocument({
    required this.id,
    required this.displayName,
    required this.provenance,
    required Iterable<EngineeringRepresentation> representations,
    required this.capabilities,
    this.unit,
    this.nativeHandle,
    Map<String, Object?> metadata = const {},
  })  : representations = Set.unmodifiable(representations),
        metadata = Map.unmodifiable(metadata);

  final String id;
  final String displayName;
  final DocumentProvenance provenance;
  final Set<EngineeringRepresentation> representations;
  final CapabilitySet capabilities;
  final String? unit;

  /// Opaque native document handle. Flutter must not copy large geometry data.
  final int? nativeHandle;

  /// Small inspection metadata only. Large arrays/buffers stay native-side.
  final Map<String, Object?> metadata;

  bool hasRepresentation(EngineeringRepresentation representation) =>
      representations.contains(representation);
}
