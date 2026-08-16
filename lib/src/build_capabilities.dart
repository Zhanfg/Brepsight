class BrepSightBuildCapabilities {
  const BrepSightBuildCapabilities._();

  static const bool occt = bool.fromEnvironment(
    'BREPSIGHT_OCCT_ENABLED',
    defaultValue: false,
  );

  static const String occtVersion = String.fromEnvironment(
    'BREPSIGHT_OCCT_VERSION',
    defaultValue: '',
  );

  static const bool step = occt;
  static const bool iges = occt;
  static const bool brep = occt;

  static const bool stl = true;
  static const bool obj = true;

  static String get exactCadLabel => occt
      ? 'OCCT ${occtVersion.isEmpty ? 'enabled' : occtVersion}'
      : '精确 CAD provider 未打包';
}
