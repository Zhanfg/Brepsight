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

  static const bool lib3mf = bool.fromEnvironment(
    'BREPSIGHT_LIB3MF_ENABLED',
    defaultValue: false,
  );

  static const String lib3mfVersion = String.fromEnvironment(
    'BREPSIGHT_LIB3MF_VERSION',
    defaultValue: '',
  );

  static const bool step = occt;
  static const bool iges = occt;
  static const bool brep = occt;
  static const bool threeMf = lib3mf;

  static const bool stl = true;
  static const bool obj = true;

  static String get exactCadLabel => occt
      ? 'OCCT ${occtVersion.isEmpty ? 'enabled' : occtVersion}'
      : '精确 CAD provider 未打包';

  static String get threeMfLabel => lib3mf
      ? 'lib3mf ${lib3mfVersion.isEmpty ? 'enabled' : lib3mfVersion}'
      : '3MF provider 未打包';
}
