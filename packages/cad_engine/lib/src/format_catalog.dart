enum EngineeringDomain {
  cad,
  meshDcc,
  freeCad,
  cae,
  proprietary,
}

enum FormatAvailability {
  stage2,
  planned,
  experimental,
  bridgeOnly,
}

class EngineeringFormat {
  const EngineeringFormat({
    required this.id,
    required this.label,
    required this.extensions,
    required this.domain,
    required this.availability,
    required this.provider,
    this.notes = '',
  });

  final String id;
  final String label;
  final List<String> extensions;
  final EngineeringDomain domain;
  final FormatAvailability availability;
  final String provider;
  final String notes;
}

/// Product-level format targets.
///
/// This is intentionally a capability catalog, not a claim that every entry is
/// already loadable. The native importer registry becomes the runtime source of
/// truth once providers are linked.
const engineeringFormatCatalog = <EngineeringFormat>[
  EngineeringFormat(
    id: 'step',
    label: 'STEP',
    extensions: ['stp', 'step', 'stepz'],
    domain: EngineeringDomain.cad,
    availability: FormatAvailability.stage2,
    provider: 'occt.step',
    notes: 'Prefer XCAF/AP242 path for assembly metadata.',
  ),
  EngineeringFormat(
    id: 'iges',
    label: 'IGES',
    extensions: ['igs', 'iges'],
    domain: EngineeringDomain.cad,
    availability: FormatAvailability.stage2,
    provider: 'occt.iges',
  ),
  EngineeringFormat(
    id: 'brep',
    label: 'Open CASCADE BREP',
    extensions: ['brep', 'brp'],
    domain: EngineeringDomain.cad,
    availability: FormatAvailability.stage2,
    provider: 'occt.brep',
  ),
  EngineeringFormat(
    id: 'xbf',
    label: 'XCAF document',
    extensions: ['xbf'],
    domain: EngineeringDomain.cad,
    availability: FormatAvailability.planned,
    provider: 'occt.xcaf',
  ),
  EngineeringFormat(
    id: 'stl',
    label: 'STL',
    extensions: ['stl'],
    domain: EngineeringDomain.meshDcc,
    availability: FormatAvailability.stage2,
    provider: 'occt.stl',
  ),
  EngineeringFormat(
    id: 'obj',
    label: 'Wavefront OBJ',
    extensions: ['obj'],
    domain: EngineeringDomain.meshDcc,
    availability: FormatAvailability.stage2,
    provider: 'mesh.obj',
  ),
  EngineeringFormat(
    id: 'gltf',
    label: 'glTF 2.0',
    extensions: ['gltf', 'glb'],
    domain: EngineeringDomain.meshDcc,
    availability: FormatAvailability.stage2,
    provider: 'mesh.gltf',
  ),
  EngineeringFormat(
    id: 'ply',
    label: 'PLY',
    extensions: ['ply'],
    domain: EngineeringDomain.meshDcc,
    availability: FormatAvailability.planned,
    provider: 'assimp.ply',
  ),
  EngineeringFormat(
    id: 'fbx',
    label: 'FBX',
    extensions: ['fbx'],
    domain: EngineeringDomain.meshDcc,
    availability: FormatAvailability.planned,
    provider: 'assimp.fbx',
  ),
  EngineeringFormat(
    id: 'collada',
    label: 'Collada',
    extensions: ['dae'],
    domain: EngineeringDomain.meshDcc,
    availability: FormatAvailability.planned,
    provider: 'assimp.collada',
  ),
  EngineeringFormat(
    id: '3ds',
    label: '3D Studio',
    extensions: ['3ds'],
    domain: EngineeringDomain.meshDcc,
    availability: FormatAvailability.planned,
    provider: 'assimp.3ds',
  ),
  EngineeringFormat(
    id: '3mf',
    label: '3MF',
    extensions: ['3mf'],
    domain: EngineeringDomain.meshDcc,
    availability: FormatAvailability.planned,
    provider: 'mesh.3mf',
  ),
  EngineeringFormat(
    id: 'usd',
    label: 'Universal Scene Description',
    extensions: ['usd', 'usda', 'usdc', 'usdz'],
    domain: EngineeringDomain.meshDcc,
    availability: FormatAvailability.planned,
    provider: 'scene.usd',
    notes: 'Dedicated provider preferred over experimental fallback readers.',
  ),
  EngineeringFormat(
    id: 'alembic',
    label: 'Alembic',
    extensions: ['abc'],
    domain: EngineeringDomain.meshDcc,
    availability: FormatAvailability.planned,
    provider: 'scene.alembic',
  ),
  EngineeringFormat(
    id: 'blend',
    label: 'Blender document',
    extensions: ['blend'],
    domain: EngineeringDomain.meshDcc,
    availability: FormatAvailability.experimental,
    provider: 'bridge.blend',
    notes: 'Do not promise full fidelity; current broad import libraries deprecate BLEND.',
  ),
  EngineeringFormat(
    id: 'fcstd',
    label: 'FreeCAD document',
    extensions: ['fcstd', 'fcbak'],
    domain: EngineeringDomain.freeCad,
    availability: FormatAvailability.planned,
    provider: 'fcstd.safe',
    notes: 'Read stored BREP and metadata only; never execute embedded Python.',
  ),
  EngineeringFormat(
    id: 'vtk',
    label: 'VTK legacy',
    extensions: ['vtk'],
    domain: EngineeringDomain.cae,
    availability: FormatAvailability.planned,
    provider: 'cae.vtk',
  ),
  EngineeringFormat(
    id: 'vtk-xml',
    label: 'VTK XML',
    extensions: ['vtu', 'vtp', 'vts', 'vtr', 'vti', 'pvd'],
    domain: EngineeringDomain.cae,
    availability: FormatAvailability.planned,
    provider: 'cae.vtkxml',
  ),
  EngineeringFormat(
    id: 'gmsh',
    label: 'Gmsh mesh',
    extensions: ['msh'],
    domain: EngineeringDomain.cae,
    availability: FormatAvailability.planned,
    provider: 'cae.gmsh',
  ),
  EngineeringFormat(
    id: 'nastran',
    label: 'NASTRAN bulk data',
    extensions: ['bdf', 'nas', 'dat'],
    domain: EngineeringDomain.cae,
    availability: FormatAvailability.planned,
    provider: 'cae.nastran',
  ),
  EngineeringFormat(
    id: 'abaqus',
    label: 'Abaqus input',
    extensions: ['inp'],
    domain: EngineeringDomain.cae,
    availability: FormatAvailability.planned,
    provider: 'cae.abaqus',
  ),
  EngineeringFormat(
    id: 'calculix-frd',
    label: 'CalculiX results',
    extensions: ['frd'],
    domain: EngineeringDomain.cae,
    availability: FormatAvailability.planned,
    provider: 'cae.calculix',
  ),
  EngineeringFormat(
    id: 'solidworks-part',
    label: 'SOLIDWORKS Part',
    extensions: ['sldprt'],
    domain: EngineeringDomain.proprietary,
    availability: FormatAvailability.bridgeOnly,
    provider: 'bridge.solidworks',
  ),
  EngineeringFormat(
    id: 'solidworks-assembly',
    label: 'SOLIDWORKS Assembly',
    extensions: ['sldasm'],
    domain: EngineeringDomain.proprietary,
    availability: FormatAvailability.bridgeOnly,
    provider: 'bridge.solidworks',
  ),
  EngineeringFormat(
    id: 'solidworks-cwr',
    label: 'SOLIDWORKS Simulation Results',
    extensions: ['cwr'],
    domain: EngineeringDomain.proprietary,
    availability: FormatAvailability.bridgeOnly,
    provider: 'bridge.solidworks-simulation',
  ),
  EngineeringFormat(
    id: 'parasolid',
    label: 'Parasolid',
    extensions: ['x_t', 'x_b', 'xmt_txt', 'xmt_bin'],
    domain: EngineeringDomain.proprietary,
    availability: FormatAvailability.bridgeOnly,
    provider: 'bridge.parasolid',
    notes: 'Optional licensed translator; not part of the open OCCT base provider.',
  ),
];
