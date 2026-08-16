enum EngineeringDomain {
  cad,
  cadDrawing,
  rhinoNurbs,
  meshDcc,
  additive,
  pointCloud,
  bim,
  freeCad,
  cae,
  cam,
  volumetric,
  proprietary,
}

enum FormatAvailability {
  stage2,
  priorityNative,
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
/// This is a capability/recognition catalog, not a claim that every entry is
/// currently loadable. Runtime importer probing becomes the source of truth as
/// providers are linked. Proprietary formats are deliberately represented so
/// the UI can explain a bridge requirement instead of saying "unknown file".
const engineeringFormatCatalog = <EngineeringFormat>[
  // Neutral / exact CAD.
  EngineeringFormat(id: 'step', label: 'STEP', extensions: ['stp', 'step', 'stepz'], domain: EngineeringDomain.cad, availability: FormatAvailability.stage2, provider: 'occt.step', notes: 'Prefer XCAF/AP242 for hierarchy, names, colors and PMI where available.'),
  EngineeringFormat(id: 'iges', label: 'IGES', extensions: ['igs', 'iges'], domain: EngineeringDomain.cad, availability: FormatAvailability.stage2, provider: 'occt.iges'),
  EngineeringFormat(id: 'brep', label: 'Open CASCADE BREP', extensions: ['brep', 'brp'], domain: EngineeringDomain.cad, availability: FormatAvailability.stage2, provider: 'occt.brep'),
  EngineeringFormat(id: 'xbf', label: 'XCAF document', extensions: ['xbf'], domain: EngineeringDomain.cad, availability: FormatAvailability.planned, provider: 'occt.xcaf'),
  EngineeringFormat(id: 'acis', label: 'ACIS SAT/SAB', extensions: ['sat', 'sab'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.acis'),
  EngineeringFormat(id: 'parasolid', label: 'Parasolid', extensions: ['x_t', 'x_b', 'xmt_txt', 'xmt_bin'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.parasolid'),
  EngineeringFormat(id: 'jt', label: 'JT', extensions: ['jt'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.jt'),
  EngineeringFormat(id: 'vda', label: 'VDA-FS', extensions: ['vda'], domain: EngineeringDomain.cad, availability: FormatAvailability.planned, provider: 'cad.vda'),

  // AutoCAD / drafting.
  EngineeringFormat(id: 'dxf', label: 'AutoCAD DXF', extensions: ['dxf', 'dxb', 'dxfb'], domain: EngineeringDomain.cadDrawing, availability: FormatAvailability.priorityNative, provider: 'drawing.dxf', notes: 'Read-only native parser target for common 2D/3D entities, layers and blocks.'),
  EngineeringFormat(id: 'dwg', label: 'AutoCAD DWG', extensions: ['dwg'], domain: EngineeringDomain.cadDrawing, availability: FormatAvailability.bridgeOnly, provider: 'bridge.oda-drawings', notes: 'Optional Android provider. GPL LibreDWG is not linked into the Apache core.'),
  EngineeringFormat(id: 'dwf', label: 'Autodesk DWF/DWFx', extensions: ['dwf', 'dwfx'], domain: EngineeringDomain.cadDrawing, availability: FormatAvailability.bridgeOnly, provider: 'bridge.oda-drawings'),
  EngineeringFormat(id: 'dgn', label: 'MicroStation DGN', extensions: ['dgn'], domain: EngineeringDomain.cadDrawing, availability: FormatAvailability.bridgeOnly, provider: 'bridge.dgn'),
  EngineeringFormat(id: 'hpgl', label: 'HP-GL/2 plot', extensions: ['plt', 'hpgl', 'hpgl2'], domain: EngineeringDomain.cadDrawing, availability: FormatAvailability.planned, provider: 'drawing.hpgl'),

  // Rhino / NURBS.
  EngineeringFormat(id: '3dm', label: 'Rhino 3DM', extensions: ['3dm'], domain: EngineeringDomain.rhinoNurbs, availability: FormatAvailability.priorityNative, provider: 'opennurbs.3dm', notes: 'Target Rhino 1-8+ documents through McNeel openNURBS.'),
  EngineeringFormat(id: '3dmbak', label: 'Rhino backup', extensions: ['3dmbak'], domain: EngineeringDomain.rhinoNurbs, availability: FormatAvailability.planned, provider: 'opennurbs.3dm'),
  EngineeringFormat(id: 'rws', label: 'Rhino Worksession', extensions: ['rws'], domain: EngineeringDomain.rhinoNurbs, availability: FormatAvailability.planned, provider: 'rhino.worksession', notes: 'Reference resolver only.'),

  // Mesh / DCC / scenes.
  EngineeringFormat(id: 'stl', label: 'STL', extensions: ['stl'], domain: EngineeringDomain.additive, availability: FormatAvailability.stage2, provider: 'mesh.stl'),
  EngineeringFormat(id: 'obj', label: 'Wavefront OBJ', extensions: ['obj', 'mtl'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.stage2, provider: 'mesh.obj'),
  EngineeringFormat(id: 'gltf', label: 'glTF 2.0', extensions: ['gltf', 'glb'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.stage2, provider: 'mesh.gltf'),
  EngineeringFormat(id: 'ply', label: 'PLY', extensions: ['ply'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.priorityNative, provider: 'mesh.ply'),
  EngineeringFormat(id: 'fbx', label: 'FBX', extensions: ['fbx'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.priorityNative, provider: 'assimp.fbx'),
  EngineeringFormat(id: 'collada', label: 'COLLADA', extensions: ['dae'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.priorityNative, provider: 'assimp.collada'),
  EngineeringFormat(id: '3ds', label: '3D Studio', extensions: ['3ds'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.planned, provider: 'assimp.3ds'),
  EngineeringFormat(id: 'usd', label: 'Universal Scene Description', extensions: ['usd', 'usda', 'usdc', 'usdz'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.planned, provider: 'scene.usd'),
  EngineeringFormat(id: 'alembic', label: 'Alembic', extensions: ['abc'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.planned, provider: 'scene.alembic'),
  EngineeringFormat(id: 'blend', label: 'Blender document', extensions: ['blend'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.experimental, provider: 'bridge.blend', notes: 'No full-fidelity launch promise; prefer exchange formats or a separated bridge.'),
  EngineeringFormat(id: 'vrml', label: 'VRML', extensions: ['wrl', 'vrml'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.priorityNative, provider: 'scene.vrml'),
  EngineeringFormat(id: 'x3d', label: 'X3D', extensions: ['x3d', 'x3dv'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.planned, provider: 'scene.x3d'),
  EngineeringFormat(id: 'off', label: 'Geomview OFF', extensions: ['off'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.planned, provider: 'mesh.off'),
  EngineeringFormat(id: 'gts', label: 'GNU Triangulated Surface', extensions: ['gts'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.planned, provider: 'mesh.gts'),
  EngineeringFormat(id: 'lightwave', label: 'LightWave', extensions: ['lwo', 'lws'], domain: EngineeringDomain.meshDcc, availability: FormatAvailability.planned, provider: 'assimp.lightwave'),

  // Additive manufacturing and toolpaths.
  EngineeringFormat(id: '3mf', label: '3MF', extensions: ['3mf'], domain: EngineeringDomain.additive, availability: FormatAvailability.priorityNative, provider: 'lib3mf', notes: 'Preserve units, build items, materials/colors and supported extension metadata.'),
  EngineeringFormat(id: 'amf', label: 'Additive Manufacturing File', extensions: ['amf'], domain: EngineeringDomain.additive, availability: FormatAvailability.planned, provider: 'additive.amf'),
  EngineeringFormat(id: 'gcode', label: 'G-code / CNC toolpath', extensions: ['gcode', 'gco', 'gc', 'nc', 'tap', 'cnc', 'ngc'], domain: EngineeringDomain.cam, availability: FormatAvailability.priorityNative, provider: 'toolpath.gcode', notes: 'Viewer only; never execute or transmit machine commands automatically.'),
  EngineeringFormat(id: 'bgcode', label: 'Binary G-code', extensions: ['bgcode'], domain: EngineeringDomain.additive, availability: FormatAvailability.planned, provider: 'toolpath.bgcode'),
  EngineeringFormat(id: 'cli', label: 'Common Layer Interface', extensions: ['cli'], domain: EngineeringDomain.additive, availability: FormatAvailability.planned, provider: 'slice.cli'),
  EngineeringFormat(id: 'slc', label: 'SLC slice', extensions: ['slc'], domain: EngineeringDomain.additive, availability: FormatAvailability.planned, provider: 'slice.slc'),
  EngineeringFormat(id: 'resin-slice', label: 'Resin slicer output', extensions: ['ctb', 'cbddlp', 'photon', 'pwmo'], domain: EngineeringDomain.additive, availability: FormatAvailability.experimental, provider: 'slice.vendor'),

  // Point clouds / scan.
  EngineeringFormat(id: 'e57', label: 'ASTM E57', extensions: ['e57'], domain: EngineeringDomain.pointCloud, availability: FormatAvailability.priorityNative, provider: 'point.e57'),
  EngineeringFormat(id: 'las', label: 'LAS/LAZ point cloud', extensions: ['las', 'laz'], domain: EngineeringDomain.pointCloud, availability: FormatAvailability.priorityNative, provider: 'point.las'),
  EngineeringFormat(id: 'pcd', label: 'Point Cloud Data', extensions: ['pcd'], domain: EngineeringDomain.pointCloud, availability: FormatAvailability.priorityNative, provider: 'point.pcd'),
  EngineeringFormat(id: 'points', label: 'Generic point table', extensions: ['xyz', 'pts', 'ptx', 'asc', 'csv'], domain: EngineeringDomain.pointCloud, availability: FormatAvailability.planned, provider: 'point.table'),
  EngineeringFormat(id: 'recap', label: 'Autodesk ReCap', extensions: ['rcp', 'rcs'], domain: EngineeringDomain.pointCloud, availability: FormatAvailability.bridgeOnly, provider: 'bridge.recap'),

  // FreeCAD.
  EngineeringFormat(id: 'fcstd', label: 'FreeCAD document', extensions: ['fcstd', 'fcbak'], domain: EngineeringDomain.freeCad, availability: FormatAvailability.planned, provider: 'fcstd.safe', notes: 'Read stored BREP and metadata only; never execute embedded Python.'),

  // BIM / AEC.
  EngineeringFormat(id: 'ifc', label: 'Industry Foundation Classes', extensions: ['ifc', 'ifczip', 'ifcxml'], domain: EngineeringDomain.bim, availability: FormatAvailability.planned, provider: 'bim.ifc'),
  EngineeringFormat(id: 'bcf', label: 'BIM Collaboration Format', extensions: ['bcf', 'bcfzip', 'bcfxml'], domain: EngineeringDomain.bim, availability: FormatAvailability.planned, provider: 'bim.bcf'),
  EngineeringFormat(id: 'revit', label: 'Autodesk Revit', extensions: ['rvt', 'rfa', 'rte'], domain: EngineeringDomain.bim, availability: FormatAvailability.bridgeOnly, provider: 'bridge.revit'),
  EngineeringFormat(id: 'gbxml', label: 'gbXML', extensions: ['gbxml'], domain: EngineeringDomain.bim, availability: FormatAvailability.planned, provider: 'bim.gbxml'),

  // CAE / simulation.
  EngineeringFormat(id: 'vtk', label: 'VTK legacy', extensions: ['vtk'], domain: EngineeringDomain.cae, availability: FormatAvailability.priorityNative, provider: 'cae.vtk'),
  EngineeringFormat(id: 'vtk-xml', label: 'VTK XML', extensions: ['vtu', 'vtp', 'vts', 'vtr', 'vti', 'pvd'], domain: EngineeringDomain.cae, availability: FormatAvailability.priorityNative, provider: 'cae.vtkxml'),
  EngineeringFormat(id: 'gmsh', label: 'Gmsh mesh', extensions: ['msh'], domain: EngineeringDomain.cae, availability: FormatAvailability.priorityNative, provider: 'cae.gmsh'),
  EngineeringFormat(id: 'nastran', label: 'NASTRAN bulk data', extensions: ['bdf', 'nas', 'dat'], domain: EngineeringDomain.cae, availability: FormatAvailability.planned, provider: 'cae.nastran'),
  EngineeringFormat(id: 'nastran-results', label: 'NASTRAN results', extensions: ['op2', 'f06'], domain: EngineeringDomain.cae, availability: FormatAvailability.planned, provider: 'cae.nastran-results'),
  EngineeringFormat(id: 'abaqus', label: 'Abaqus input', extensions: ['inp'], domain: EngineeringDomain.cae, availability: FormatAvailability.planned, provider: 'cae.abaqus'),
  EngineeringFormat(id: 'abaqus-odb', label: 'Abaqus results', extensions: ['odb'], domain: EngineeringDomain.cae, availability: FormatAvailability.bridgeOnly, provider: 'bridge.abaqus'),
  EngineeringFormat(id: 'calculix-frd', label: 'CalculiX results', extensions: ['frd'], domain: EngineeringDomain.cae, availability: FormatAvailability.planned, provider: 'cae.calculix'),
  EngineeringFormat(id: 'cgns', label: 'CGNS', extensions: ['cgns'], domain: EngineeringDomain.cae, availability: FormatAvailability.planned, provider: 'cae.cgns'),
  EngineeringFormat(id: 'exodus', label: 'Exodus II', extensions: ['e', 'exo', 'ex2'], domain: EngineeringDomain.cae, availability: FormatAvailability.planned, provider: 'cae.exodus'),
  EngineeringFormat(id: 'med', label: 'MED', extensions: ['med'], domain: EngineeringDomain.cae, availability: FormatAvailability.planned, provider: 'cae.med'),
  EngineeringFormat(id: 'ansys-cdb', label: 'ANSYS CDB', extensions: ['cdb'], domain: EngineeringDomain.cae, availability: FormatAvailability.planned, provider: 'cae.ansys-cdb'),
  EngineeringFormat(id: 'ansys-results', label: 'ANSYS results', extensions: ['rst', 'rth'], domain: EngineeringDomain.cae, availability: FormatAvailability.bridgeOnly, provider: 'bridge.ansys'),
  EngineeringFormat(id: 'lsdyna', label: 'LS-DYNA keyword', extensions: ['k', 'key'], domain: EngineeringDomain.cae, availability: FormatAvailability.planned, provider: 'cae.lsdyna'),
  EngineeringFormat(id: 'unv', label: 'I-DEAS Universal', extensions: ['unv'], domain: EngineeringDomain.cae, availability: FormatAvailability.planned, provider: 'cae.unv'),

  // Volumetric / voxel.
  EngineeringFormat(id: 'openvdb', label: 'OpenVDB', extensions: ['vdb'], domain: EngineeringDomain.volumetric, availability: FormatAvailability.planned, provider: 'volume.openvdb'),

  // Proprietary MCAD recognition / bridges.
  EngineeringFormat(id: 'solidworks-part', label: 'SOLIDWORKS Part', extensions: ['sldprt'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.solidworks'),
  EngineeringFormat(id: 'solidworks-assembly', label: 'SOLIDWORKS Assembly', extensions: ['sldasm'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.solidworks'),
  EngineeringFormat(id: 'solidworks-drawing', label: 'SOLIDWORKS Drawing', extensions: ['slddrw'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.solidworks'),
  EngineeringFormat(id: 'solidworks-cwr', label: 'SOLIDWORKS Simulation Results', extensions: ['cwr'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.solidworks-simulation'),
  EngineeringFormat(id: 'inventor', label: 'Autodesk Inventor', extensions: ['ipt', 'iam', 'idw', 'ipn'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.inventor'),
  EngineeringFormat(id: 'fusion', label: 'Autodesk Fusion', extensions: ['f3d', 'f3z'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.fusion'),
  EngineeringFormat(id: 'catia', label: 'CATIA', extensions: ['catpart', 'catproduct', 'cgr', 'model', 'session'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.catia'),
  EngineeringFormat(id: 'nx', label: 'Siemens NX', extensions: ['prt'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.nx', notes: 'Extension is ambiguous; provider must probe file content.'),
  EngineeringFormat(id: 'creo', label: 'PTC Creo / ProE', extensions: ['prt', 'asm', 'drw'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.creo', notes: 'Extensions are ambiguous; provider must probe file content.'),
  EngineeringFormat(id: 'solidedge', label: 'Solid Edge', extensions: ['par', 'psm', 'asm', 'dft'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.solidedge'),
  EngineeringFormat(id: 'alias', label: 'Autodesk Alias', extensions: ['wire'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.alias'),
  EngineeringFormat(id: 'sketchup', label: 'SketchUp', extensions: ['skp'], domain: EngineeringDomain.proprietary, availability: FormatAvailability.bridgeOnly, provider: 'bridge.sketchup'),
];
