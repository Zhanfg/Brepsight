enum MaterialModel {
  unlit,
  pbrMetallicRoughness,
  phong,
  lambert,
  specularGlossiness,
  custom,
}

enum TextureSemantic {
  baseColor,
  normal,
  metallic,
  roughness,
  metallicRoughness,
  occlusion,
  emissive,
  opacity,
  specular,
  glossiness,
  height,
  displacement,
  ambient,
  reflection,
  unknown,
}

enum TextureColorSpace { srgb, linear, data, unknown }

enum TextureStorage { embedded, externalFile, contentUri, generated }

enum TextureWrapMode { repeat, clampToEdge, mirroredRepeat, unknown }

enum TextureFilterMode { nearest, linear, mipmapped, unknown }

class UvSetDescriptor {
  const UvSetDescriptor({
    required this.index,
    this.name = '',
  }) : assert(index >= 0);

  final int index;
  final String name;
}

class TextureAssetDescriptor {
  const TextureAssetDescriptor({
    required this.id,
    required this.storage,
    required this.colorSpace,
    this.uri,
    this.mimeType,
    this.width,
    this.height,
    this.byteLength,
    this.contentHash,
  });

  final String id;
  final TextureStorage storage;
  final TextureColorSpace colorSpace;
  final String? uri;
  final String? mimeType;
  final int? width;
  final int? height;
  final int? byteLength;
  final String? contentHash;
}

class TextureTransform {
  const TextureTransform({
    this.offsetU = 0,
    this.offsetV = 0,
    this.scaleU = 1,
    this.scaleV = 1,
    this.rotationRadians = 0,
  });

  final double offsetU;
  final double offsetV;
  final double scaleU;
  final double scaleV;
  final double rotationRadians;
}

class TextureBinding {
  const TextureBinding({
    required this.semantic,
    required this.textureId,
    this.uvSet = 0,
    this.transform = const TextureTransform(),
    this.wrapU = TextureWrapMode.repeat,
    this.wrapV = TextureWrapMode.repeat,
    this.filter = TextureFilterMode.linear,
    this.channel,
    this.strength = 1,
  }) : assert(uvSet >= 0);

  final TextureSemantic semantic;
  final String textureId;
  final int uvSet;
  final TextureTransform transform;
  final TextureWrapMode wrapU;
  final TextureWrapMode wrapV;
  final TextureFilterMode filter;
  final String? channel;
  final double strength;
}

class MaterialDescriptor {
  MaterialDescriptor({
    required this.id,
    required this.name,
    required this.model,
    Iterable<TextureBinding> textures = const [],
    Map<String, double> scalarParameters = const {},
    Map<String, List<double>> vectorParameters = const {},
  })  : textures = List.unmodifiable(textures),
        scalarParameters = Map.unmodifiable(scalarParameters),
        vectorParameters = Map.unmodifiable(vectorParameters);

  final String id;
  final String name;
  final MaterialModel model;
  final List<TextureBinding> textures;
  final Map<String, double> scalarParameters;
  final Map<String, List<double>> vectorParameters;
}

class MaterialAssetSummary {
  MaterialAssetSummary({
    Iterable<UvSetDescriptor> uvSets = const [],
    Iterable<TextureAssetDescriptor> textures = const [],
    Iterable<MaterialDescriptor> materials = const [],
  })  : uvSets = List.unmodifiable(uvSets),
        textures = List.unmodifiable(textures),
        materials = List.unmodifiable(materials);

  final List<UvSetDescriptor> uvSets;
  final List<TextureAssetDescriptor> textures;
  final List<MaterialDescriptor> materials;

  bool get hasUv => uvSets.isNotEmpty;
  bool get hasTextures => textures.isNotEmpty;
  bool get hasMaterials => materials.isNotEmpty;
}
