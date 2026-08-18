import 'dart:async';

import 'package:cad_engine/cad_engine.dart';
import 'package:cad_engine/v01_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mesh_edit_sheet.dart';
import 'object_presentation_sheet.dart';

/// Mobile-first model workspace used by the 0.1 RC.
///
/// The older [ViewerPage] remains in the tree as a compatibility/reference
/// implementation. This workspace deliberately prioritizes model readability
/// over exposing every action as a permanent toolbar icon.
class ViewerWorkspacePage extends StatefulWidget {
  const ViewerWorkspacePage({
    super.key,
    required this.modelPath,
    required this.onExitViewer,
  });

  final String? modelPath;
  final VoidCallback onExitViewer;

  @override
  State<ViewerWorkspacePage> createState() => _ViewerWorkspacePageState();
}

class _ViewerWorkspacePageState extends State<ViewerWorkspacePage> {
  int? _textureId;
  int? _documentHandle;
  Size _surfaceSize = Size.zero;
  String? _loadedPath;
  String _status = '准备查看模型';
  String _projection = 'perspective';
  String _displayMode = 'shaded';
  String _loadedFormat = 'unknown';
  int _triangleCount = 0;
  bool _hasUv = false;
  bool _hasNormals = false;
  bool _exactGeometry = false;
  int _rootObjectCount = 0;
  int _hierarchyNodeCount = 0;
  bool _lightenNativeCanvas = true;

  List<CadObjectPresentation> _objects = const [];
  MeshEditState? _editState;
  bool _editing = false;
  bool _exporting = false;
  bool _inspecting = false;
  bool _importing = false;
  Timer? _progressTimer;

  Offset? _lastFocalPoint;
  double _lastScale = 1;
  double _orbitX = 0.55;
  double _orbitY = -0.35;
  double _panX = 0;
  double _panY = 0;
  double _zoom = 1;

  CadMeasurementMode _measurementMode = CadMeasurementMode.none;
  final List<CadPickPoint> _measurementPoints = <CadPickPoint>[];
  String? _measurementResult;

  bool _sectionEnabled = false;
  String _sectionAxis = 'z';
  double _sectionOffset = 0;

  bool get _hasModel => _loadedPath != null;
  bool get _editActive => _editState?.active == true;
  bool get _busy => _importing || _editing || _exporting || _inspecting || (_editState?.busy ?? false);

  String get _modelTitle {
    final raw = _loadedPath ?? widget.modelPath;
    if (raw == null || raw.isEmpty) return '模型查看';
    final normalized = raw.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty).toList(growable: false);
    return parts.isEmpty ? '模型查看' : parts.last;
  }

  String get _modelMeta {
    if (!_hasModel) return '从文件页打开模型';
    final triangles = _triangleCount >= 1000000
        ? '${(_triangleCount / 1000000).toStringAsFixed(1)}M'
        : _triangleCount >= 1000
            ? '${(_triangleCount / 1000).toStringAsFixed(1)}k'
            : '$_triangleCount';
    return '${_loadedFormat.toUpperCase()} · $triangles 三角面${_exactGeometry ? ' · Exact B-Rep' : ''}${_hasNormals ? ' · N' : ''}';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadIfReady());
  }

  @override
  void didUpdateWidget(covariant ViewerWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelPath != widget.modelPath) unawaited(_loadIfReady());
  }

  Future<void> _ensureSurface(Size size) async {
    if (size.width < 2 || size.height < 2) return;
    final width = size.width.round();
    final height = size.height.round();
    if (_textureId == null) {
      final id = await CadEngine.instance.createViewport(width: width, height: height);
      if (!mounted) return;
      setState(() {
        _textureId = id;
        _surfaceSize = size;
      });
      await CadEngine.instance.setProjection(_projection);
      await CadEngine.instance.setDisplayMode(_displayMode);
      await _loadIfReady();
      return;
    }
    if ((_surfaceSize.width - size.width).abs() >= 2 ||
        (_surfaceSize.height - size.height).abs() >= 2) {
      _surfaceSize = size;
      await CadEngine.instance.resizeViewport(width: width, height: height);
    }
  }

  void _startProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 350),
      (_) => unawaited(_refreshProgress()),
    );
  }

  Future<void> _refreshProgress() async {
    if (!_importing) return;
    try {
      final progress = await CadEngineV01Tools.instance.importProgress();
      if (!mounted || !_importing || !progress.active) return;
      final stage = switch (progress.stage) {
        'queued' => '排队',
        'preparing' => '预处理',
        'importing' => '解析几何',
        'finalizing' => '提交文档',
        'restoring' => '恢复文档',
        'cancelling' => '正在取消',
        _ => progress.stage,
      };
      setState(() => _status = '$stage · ${progress.progress}%');
    } on PlatformException {
      // Progress is supplementary. The final load result remains authoritative.
    }
  }

  Future<void> _cancelImport() async {
    final accepted = await CadEngineV01Tools.instance.cancelImport();
    if (!mounted) return;
    setState(() => _status = accepted ? '正在取消导入…' : '当前没有可取消的导入任务');
  }

  Future<void> _loadIfReady() async {
    final path = widget.modelPath;
    if (path == null || path.isEmpty || path == _loadedPath || _textureId == null || _importing) return;

    setState(() {
      _importing = true;
      _status = '正在载入模型…';
      _measurementMode = CadMeasurementMode.none;
      _measurementPoints.clear();
      _measurementResult = null;
    });
    _startProgressPolling();

    try {
      final result = await CadEngine.instance.loadModel(path);
      if (!mounted) return;
      if (!result.ok) {
        setState(() => _status = _loadedPath == null ? '打开失败：${result.message}' : '${result.message} · 已保留上一模型');
        return;
      }

      List<CadObjectPresentation> objects = const [];
      int? handle;
      MeshEditState? editState;
      try {
        objects = await CadEngine.instance.getObjectPresentation();
        handle = await CadEngine.instance.getCurrentDocumentHandle();
        editState = await CadEngine.instance.getMeshEditState();
      } on PlatformException {
        objects = const [];
      } on FormatException {
        objects = const [];
      }

      if (!mounted) return;
      setState(() {
        _loadedPath = path;
        _documentHandle = handle;
        _objects = objects;
        _editState = editState;
        _loadedFormat = result.formatId;
        _triangleCount = result.triangleCount;
        _hasUv = result.hasUv;
        _hasNormals = result.hasNormals;
        _exactGeometry = result.exactGeometry;
        _rootObjectCount = result.rootObjectCount;
        _hierarchyNodeCount = result.hierarchyNodeCount;
        _orbitX = 0.55;
        _orbitY = -0.35;
        _panX = 0;
        _panY = 0;
        _zoom = 1;
        _status = '${result.formatId.toUpperCase()} 已载入 · ${result.triangleCount} 三角面';
      });
      _fitAll();
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '打开失败：${error.message ?? error.code}');
    } finally {
      _progressTimer?.cancel();
      _progressTimer = null;
      if (mounted) setState(() => _importing = false);
    }
  }

  void _fitAll() {
    _panX = 0;
    _panY = 0;
    _zoom = 1;
    unawaited(CadEngine.instance.fitAll());
  }

  void _setProjection(String value) {
    if (value == _projection) return;
    setState(() => _projection = value);
    unawaited(CadEngine.instance.setProjection(value));
  }

  void _setDisplayMode(String value) {
    if (value == _displayMode) return;
    setState(() => _displayMode = value);
    unawaited(CadEngine.instance.setDisplayMode(value));
  }

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.localFocalPoint;
    _lastScale = 1;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final last = _lastFocalPoint;
    if (last != null) {
      final delta = details.localFocalPoint - last;
      if (details.pointerCount >= 2) {
        final width = _surfaceSize.width <= 0 ? 1.0 : _surfaceSize.width;
        final height = _surfaceSize.height <= 0 ? 1.0 : _surfaceSize.height;
        _panX += delta.dx / width;
        _panY += delta.dy / height;
        unawaited(CadEngine.instance.pan(delta.dx, delta.dy));
      } else {
        _orbitX += delta.dx * 0.010;
        _orbitY = (_orbitY + delta.dy * 0.010).clamp(-1.55, 1.55);
        unawaited(CadEngine.instance.orbit(delta.dx, delta.dy));
      }
    }
    if ((details.scale - _lastScale).abs() > 0.003) {
      final factor = details.scale / _lastScale;
      _zoom = (_zoom * factor).clamp(0.05, 20.0);
      unawaited(CadEngine.instance.zoom(factor));
      _lastScale = details.scale;
    }
    _lastFocalPoint = details.localFocalPoint;
  }

  void _setMeasurementMode(CadMeasurementMode mode) {
    setState(() {
      _measurementMode = mode;
      _measurementPoints.clear();
      _measurementResult = null;
      _status = switch (mode) {
        CadMeasurementMode.distance => '距离测量 · 选择 2 个点',
        CadMeasurementMode.angle => '角度测量 · 选择 A、B、C',
        CadMeasurementMode.radius => '半径测量 · 选择圆弧上的 3 个点',
        CadMeasurementMode.none => '已退出测量',
      };
    });
  }

  String _number(double value) {
    final abs = value.abs();
    if (abs >= 100000 || (abs > 0 && abs < 0.001)) return value.toStringAsExponential(4);
    return value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  Future<void> _measureAt(TapUpDetails details) async {
    final handle = _documentHandle;
    if (_measurementMode == CadMeasurementMode.none || handle == null || _surfaceSize.shortestSide < 2) return;
    final point = await CadEngineV01Tools.instance.pickModelPoint(
      documentHandle: handle,
      width: _surfaceSize.width.round(),
      height: _surfaceSize.height.round(),
      orbitX: _orbitX,
      orbitY: _orbitY,
      panX: _panX,
      panY: _panY,
      zoom: _zoom,
      orthographic: _projection == 'orthographic',
      screenX: details.localPosition.dx,
      screenY: details.localPosition.dy,
    );
    if (!mounted) return;
    if (point == null) {
      setState(() => _status = '该位置没有命中模型');
      return;
    }
    _measurementPoints.add(point);
    final required = _measurementMode == CadMeasurementMode.distance ? 2 : 3;
    if (_measurementPoints.length < required) {
      setState(() => _status = '已选 ${_measurementPoints.length} / $required 点');
      return;
    }

    final points = List<CadPickPoint>.of(_measurementPoints);
    final result = switch (_measurementMode) {
      CadMeasurementMode.distance => '距离 ${_number(CadMeasurement.distance(points[0], points[1]))}',
      CadMeasurementMode.angle => (() {
          final value = CadMeasurement.angle(points[0], points[1], points[2]);
          return value == null ? '角度无法计算' : '角度 ${_number(value)}°';
        })(),
      CadMeasurementMode.radius => (() {
          final value = CadMeasurement.radius(points[0], points[1], points[2]);
          return value == null ? '半径无法计算' : '半径 R ${_number(value)}';
        })(),
      CadMeasurementMode.none => '',
    };
    setState(() {
      _measurementResult = result;
      _measurementPoints.clear();
      _status = result;
    });
  }

  Future<void> _showMeasurementTools() async {
    if (!_hasModel || _busy) return;
    final mode = await showModalBottomSheet<CadMeasurementMode>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.straighten),
              title: const Text('两点距离'),
              subtitle: const Text('点击模型上的两个位置'),
              onTap: () => Navigator.pop(context, CadMeasurementMode.distance),
            ),
            ListTile(
              leading: const Icon(Icons.architecture_outlined),
              title: const Text('三点角度'),
              subtitle: const Text('A — 顶点 B — C'),
              onTap: () => Navigator.pop(context, CadMeasurementMode.angle),
            ),
            ListTile(
              leading: const Icon(Icons.radio_button_unchecked),
              title: const Text('三点半径'),
              subtitle: const Text('选择圆或圆弧上的三个位置'),
              onTap: () => Navigator.pop(context, CadMeasurementMode.radius),
            ),
            if (_measurementMode != CadMeasurementMode.none)
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('退出测量'),
                onTap: () => Navigator.pop(context, CadMeasurementMode.none),
              ),
          ],
        ),
      ),
    );
    if (mode != null && mounted) _setMeasurementMode(mode);
  }

  Future<void> _showSectionControls() async {
    if (!_hasModel || _busy || _editActive) return;
    final request = await showModalBottomSheet<_SectionRequest>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _SectionSheet(
        enabled: _sectionEnabled,
        axis: _sectionAxis,
        offset: _sectionOffset,
      ),
    );
    if (request == null || !mounted) return;
    final normal = switch (request.axis) {
      'x' => const <double>[1, 0, 0],
      'y' => const <double>[0, 1, 0],
      _ => const <double>[0, 0, 1],
    };
    try {
      final ok = await CadEngineV01Tools.instance.setSectionPlane(
        enabled: request.enabled,
        nx: normal[0],
        ny: normal[1],
        nz: normal[2],
        offset: request.offset,
      );
      if (!ok) throw PlatformException(code: 'SECTION_REJECTED', message: 'Native section plane rejected the request.');
      final handle = await CadEngine.instance.getCurrentDocumentHandle();
      final summary = handle == null ? null : await CadEngine.instance.getDocumentSummary(handle);
      if (!mounted) return;
      setState(() {
        _sectionEnabled = request.enabled;
        _sectionAxis = request.axis;
        _sectionOffset = request.offset;
        _documentHandle = handle;
        if (summary != null) _triangleCount = summary.triangleCount;
        _status = request.enabled
            ? '剖切 · ${request.axis.toUpperCase()} ≥ ${_number(request.offset)}'
            : '剖切已关闭';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '剖切失败：${error.message ?? error.code}');
    }
  }

  Future<void> _showObjects() async {
    if (_objects.isEmpty || _busy || _editActive) return;
    final updated = await showObjectPresentationSheet(
      context: context,
      objects: _objects,
      onSetVisibility: (objectId, visible) => CadEngine.instance.setObjectVisibility(
        objectId: objectId,
        visible: visible,
      ),
    );
    if (updated != null && mounted) setState(() => _objects = updated);
  }

  Future<void> _syncEditState(MeshEditState state, String status) async {
    final handle = await CadEngine.instance.getCurrentDocumentHandle();
    final summary = handle == null ? null : await CadEngine.instance.getDocumentSummary(handle);
    if (!mounted) return;
    setState(() {
      _editState = state;
      _documentHandle = handle;
      if (summary != null) {
        _loadedFormat = summary.formatId;
        _triangleCount = summary.triangleCount;
        _exactGeometry = summary.exactGeometry;
      }
      _measurementMode = CadMeasurementMode.none;
      _measurementPoints.clear();
      _measurementResult = null;
      _status = status;
    });
    _fitAll();
  }

  Future<MeshEditState> _editAction(
    Future<MeshEditState> Function() action,
    String status,
  ) async {
    if (mounted) setState(() => _editing = true);
    try {
      final next = await action();
      await _syncEditState(next, status);
      return next;
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _showEditor() async {
    if (!_hasModel || _busy || _sectionEnabled) return;
    try {
      final state = _editActive
          ? _editState!
          : await _editAction(CadEngine.instance.beginMeshEdit, '已创建网格工作副本');
      if (!mounted || !state.active) return;
      await showMeshEditSheet(
        context: context,
        initialState: state,
        onApply: (request) => _editAction(
          () => CadEngine.instance.applyMeshTransform(
            tx: request.tx,
            ty: request.ty,
            tz: request.tz,
            rx: request.rx,
            ry: request.ry,
            rz: request.rz,
            sx: request.sx,
            sy: request.sy,
            sz: request.sz,
          ),
          '已应用变换 · 可撤销/重做',
        ),
        onUndo: () => _editAction(CadEngine.instance.undoMeshEdit, '已撤销'),
        onRedo: () => _editAction(CadEngine.instance.redoMeshEdit, '已重做'),
        onReset: () => _editAction(CadEngine.instance.resetMeshEdit, '已重置工作副本'),
        onDiscard: () => _editAction(CadEngine.instance.discardMeshEdit, '已恢复原模型'),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '编辑失败：${error.message ?? error.code}');
    }
  }

  Future<void> _export(String format) async {
    if (!_hasModel || _exporting) return;
    setState(() {
      _exporting = true;
      _status = '正在准备 ${format.toUpperCase()}…';
    });
    try {
      final result = await CadEngine.instance.exportCurrentModel(format);
      if (!mounted) return;
      setState(() => _status = result == null ? '已取消导出' : '已导出 ${result.displayName}');
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '导出失败：${error.message ?? error.code}');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _inspect() async {
    if (!_hasModel || _inspecting || _editActive) return;
    setState(() => _inspecting = true);
    try {
      if (_exactGeometry) {
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          useSafeArea: true,
          builder: (context) => _InfoSheet(
            title: 'CAD 文档',
            rows: [
              ('格式', _loadedFormat.toUpperCase()),
              ('精确几何', '已保留'),
              ('根对象', '$_rootObjectCount'),
              ('层级节点', '$_hierarchyNodeCount'),
              ('显示三角面', '$_triangleCount'),
            ],
            note: '屏幕三角网格仅用于实时显示；原始精确 B-Rep 不会被查看操作替换。',
          ),
        );
      } else {
        final inspection = await CadEngine.instance.analyzeCurrentModel();
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) => _InfoSheet(
            title: inspection.closed ? '模型检查 · 闭合' : '模型检查 · 需要检查',
            rows: [
              ('三角面', '${inspection.triangleCount}'),
              ('唯一顶点', '${inspection.uniqueVertexCount}'),
              ('连通部件', '${inspection.connectedComponentCount}'),
              ('开边', '${inspection.openEdgeCount}'),
              ('非流形边', '${inspection.nonManifoldEdgeCount}'),
              ('退化面', '${inspection.degenerateTriangleCount}'),
            ],
            note: inspection.unitKnown
                ? '单位：${inspection.unitLabel}'
                : 'STL/OBJ 通常不携带可靠长度单位，因此这里不擅自解释为 mm、cm 或 inch。',
          ),
        );
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '检查失败：${error.message ?? error.code}');
    } finally {
      if (mounted) setState(() => _inspecting = false);
    }
  }

  Future<void> _showViewOptions() async {
    var projection = _projection;
    var displayMode = _displayMode;
    var lightCanvas = _lightenNativeCanvas;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('视图设置', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
              Text('投影', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'perspective', label: Text('透视'), icon: Icon(Icons.photo_camera_outlined)),
                  ButtonSegment(value: 'orthographic', label: Text('正交'), icon: Icon(Icons.crop_square)),
                ],
                selected: {projection},
                showSelectedIcon: false,
                onSelectionChanged: (value) {
                  projection = value.first;
                  update(() {});
                  _setProjection(projection);
                },
              ),
              const SizedBox(height: 20),
              Text('模型显示', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'shaded', label: Text('实体'), icon: Icon(Icons.view_in_ar)),
                  ButtonSegment(value: 'shaded_edges', label: Text('边线'), icon: Icon(Icons.grid_on)),
                  ButtonSegment(value: 'wireframe', label: Text('线框'), icon: Icon(Icons.gesture)),
                ],
                selected: {displayMode},
                showSelectedIcon: false,
                onSelectionChanged: (value) {
                  displayMode = value.first;
                  update(() {});
                  _setDisplayMode(displayMode);
                },
              ),
              const SizedBox(height: 12),
              Text(
                '高三角面模型默认用实体着色。边线/线框用于检查网格，不再作为默认视图。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('提亮画布'),
                subtitle: const Text('降低 native 深色画布的黑场感，同时保留模型明暗层次'),
                value: lightCanvas,
                onChanged: (value) {
                  lightCanvas = value;
                  update(() {});
                  if (mounted) setState(() => _lightenNativeCanvas = value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMore() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(_exactGeometry ? Icons.account_tree_outlined : Icons.fact_check_outlined),
              title: Text(_exactGeometry ? 'CAD 信息' : '模型检查'),
              onTap: () => Navigator.pop(context, 'inspect'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('导出 OBJ'),
              subtitle: _hasUv ? const Text('OBJ 可保留 UV') : null,
              onTap: () => Navigator.pop(context, 'obj'),
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('导出 STL'),
              subtitle: _exactGeometry ? const Text('精确几何将以显示网格导出') : null,
              onTap: () => Navigator.pop(context, 'stl'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || value == null) return;
    switch (value) {
      case 'inspect':
        await _inspect();
        break;
      case 'obj':
      case 'stl':
        await _export(value);
        break;
    }
  }

  Widget _texture() {
    final id = _textureId;
    if (id == null) return const SizedBox.expand();
    final texture = Texture(textureId: id);
    if (!_lightenNativeCanvas) return texture;
    // The current GLES renderer owns an opaque surface. Screen blending lifts
    // the near-black clear color without inverting material/model colors.
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Color(0xA6AAB4C2), BlendMode.screen),
      child: texture,
    );
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    unawaited(CadEngine.instance.disposeViewport());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final measuring = _measurementMode != CadMeasurementMode.none;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回文件',
          onPressed: widget.onExitViewer,
          icon: const Icon(Icons.arrow_back),
        ),
        titleSpacing: 2,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _modelTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              _modelMeta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          if (_importing)
            IconButton(
              tooltip: '取消导入',
              onPressed: () => unawaited(_cancelImport()),
              icon: const Icon(Icons.cancel_outlined),
            ),
          IconButton(
            tooltip: '适配模型',
            onPressed: _textureId == null ? null : _fitAll,
            icon: const Icon(Icons.center_focus_strong),
          ),
          IconButton(
            tooltip: '视图设置',
            onPressed: _textureId == null ? null : () => unawaited(_showViewOptions()),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: '更多',
            onPressed: !_hasModel || _busy ? null : () => unawaited(_showMore()),
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_ensureSurface(size)));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: measuring ? null : _onScaleStart,
            onScaleUpdate: measuring ? null : _onScaleUpdate,
            onTapUp: measuring ? _measureAt : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFFDCE2E9)),
                _texture(),
                if (!_hasModel && !_importing)
                  const _EmptyModelState(),
                if (measuring || _editActive || _sectionEnabled)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (measuring)
                          Chip(
                            avatar: const Icon(Icons.straighten, size: 18),
                            label: Text(
                              '${switch (_measurementMode) {
                                CadMeasurementMode.distance => '距离',
                                CadMeasurementMode.angle => '角度',
                                CadMeasurementMode.radius => '半径',
                                CadMeasurementMode.none => '',
                              }} · ${_measurementPoints.length} 点'
                              '${_measurementResult == null ? '' : ' · $_measurementResult'}',
                            ),
                          ),
                        if (_editActive)
                          Chip(
                            avatar: const Icon(Icons.transform, size: 18),
                            label: Text('工作副本 · r${_editState!.cursor}'),
                          ),
                        if (_sectionEnabled)
                          Chip(
                            avatar: const Icon(Icons.content_cut, size: 18),
                            label: Text('${_sectionAxis.toUpperCase()} ≥ ${_number(_sectionOffset)}'),
                          ),
                      ],
                    ),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: IgnorePointer(
                    child: Material(
                      color: theme.colorScheme.surface.withValues(alpha: 0.91),
                      elevation: 1,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        child: Row(
                          children: [
                            if (_importing || _editing)
                              const Padding(
                                padding: EdgeInsets.only(right: 10),
                                child: SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Icon(Icons.info_outline, size: 17, color: theme.colorScheme.onSurfaceVariant),
                              ),
                            Expanded(
                              child: Text(
                                _status,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _hasModel
          ? _ToolDock(
              busy: _busy,
              measurementActive: measuring,
              sectionActive: _sectionEnabled,
              editActive: _editActive,
              hasObjects: _objects.isNotEmpty,
              onMeasure: () => unawaited(_showMeasurementTools()),
              onSection: () => unawaited(_showSectionControls()),
              onEdit: () => unawaited(_showEditor()),
              onObjects: () => unawaited(_showObjects()),
            )
          : null,
    );
  }
}

class _ToolDock extends StatelessWidget {
  const _ToolDock({
    required this.busy,
    required this.measurementActive,
    required this.sectionActive,
    required this.editActive,
    required this.hasObjects,
    required this.onMeasure,
    required this.onSection,
    required this.onEdit,
    required this.onObjects,
  });

  final bool busy;
  final bool measurementActive;
  final bool sectionActive;
  final bool editActive;
  final bool hasObjects;
  final VoidCallback onMeasure;
  final VoidCallback onSection;
  final VoidCallback onEdit;
  final VoidCallback onObjects;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              _ToolButton(icon: Icons.straighten, label: '测量', active: measurementActive, enabled: !busy, onTap: onMeasure),
              _ToolButton(icon: Icons.content_cut, label: '剖切', active: sectionActive, enabled: !busy && !editActive, onTap: onSection),
              _ToolButton(icon: Icons.transform, label: '编辑', active: editActive, enabled: !busy && !sectionActive, onTap: onEdit),
              _ToolButton(icon: Icons.layers_outlined, label: '对象', active: false, enabled: !busy && !editActive && hasObjects, onTap: onObjects),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.36,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                decoration: BoxDecoration(
                  color: active ? theme.colorScheme.secondaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: 2),
              Text(label, style: theme.textTheme.labelMedium?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyModelState extends StatelessWidget {
  const _EmptyModelState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_in_ar_outlined, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('尚未打开模型', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '返回文件页选择 STL、OBJ、STEP、IGES、3MF、3DM 等模型。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionRequest {
  const _SectionRequest({required this.enabled, required this.axis, required this.offset});
  final bool enabled;
  final String axis;
  final double offset;
}

class _SectionSheet extends StatefulWidget {
  const _SectionSheet({required this.enabled, required this.axis, required this.offset});
  final bool enabled;
  final String axis;
  final double offset;

  @override
  State<_SectionSheet> createState() => _SectionSheetState();
}

class _SectionSheetState extends State<_SectionSheet> {
  late bool enabled = widget.enabled;
  late String axis = widget.axis;
  late final TextEditingController controller = TextEditingController(text: widget.offset.toString());

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('剖切平面', style: Theme.of(context).textTheme.titleLarge),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用剖切'),
            subtitle: const Text('只裁剪显示网格，不修改源 CAD'),
            value: enabled,
            onChanged: (value) => setState(() => enabled = value),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'x', label: Text('X')),
              ButtonSegment(value: 'y', label: Text('Y')),
              ButtonSegment(value: 'z', label: Text('Z')),
            ],
            selected: {axis},
            showSelectedIcon: false,
            onSelectionChanged: enabled ? (value) => setState(() => axis = value.first) : null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(
              labelText: '平面坐标',
              helperText: '例如 Z ≥ 0',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final offset = double.tryParse(controller.text.trim());
              if (enabled && offset == null) return;
              Navigator.pop(context, _SectionRequest(enabled: enabled, axis: axis, offset: offset ?? 0));
            },
            child: const Text('应用'),
          ),
        ],
      ),
    );
  }
}

class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.title, required this.rows, required this.note});
  final String title;
  final List<(String, String)> rows;
  final String note;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(row.$1)),
                  const SizedBox(width: 16),
                  Text(row.$2, textAlign: TextAlign.end),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Text(note, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
