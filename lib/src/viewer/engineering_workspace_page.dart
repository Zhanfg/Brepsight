import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cad_engine/cad_engine.dart';
import 'package:cad_engine/v01_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'local_annotation_sheet.dart';
import 'local_annotations.dart';
import 'mesh_edit_sheet.dart';
import 'object_presentation_sheet.dart';

enum _MeasureMode { none, coordinate, distance, angle, radius, area }

class EngineeringWorkspacePage extends StatefulWidget {
  const EngineeringWorkspacePage({
    super.key,
    required this.modelPath,
    required this.onExitViewer,
  });

  final String? modelPath;
  final VoidCallback onExitViewer;

  @override
  State<EngineeringWorkspacePage> createState() =>
      _EngineeringWorkspacePageState();
}

class _EngineeringWorkspacePageState extends State<EngineeringWorkspacePage> {
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

  List<CadObjectPresentation> _objects = const [];
  final GlobalKey _viewportCaptureKey = GlobalKey();
  List<LocalModelAnnotation> _annotations = const [];
  String? _annotationModelKey;
  bool _annotationBusy = false;
  MeshEditState? _editState;
  bool _editing = false;
  bool _exporting = false;
  bool _splitting = false;
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

  _MeasureMode _measureMode = _MeasureMode.none;
  final List<CadPickPoint> _measurePoints = <CadPickPoint>[];
  String? _measureResult;
  CadPickPoint? _lastPick;
  bool _precisionPick = false;
  bool _runtimeReady = false;
  String? _runtimeFault;

  bool _selectionActive = false;
  CadSelectionFilter _selectionFilter = CadSelectionFilter.face;
  CadPickPoint? _selection;

  bool _sectionEnabled = false;
  String _sectionAxis = 'z';
  double _sectionOffset = 0;
  double _explodeFactor = 0.0;

  bool get _hasModel => _loadedPath != null;
  bool get _editActive => _editState?.active == true;
  bool get _measuring => _measureMode != _MeasureMode.none;
  CadObjectPresentation? get _selectedObject {
    final index = _selection?.objectIndex ?? -1;
    if (index < 0 || index >= _objects.length) return null;
    return _objects[index];
  }

  bool get _canExplode =>
      _objects
          .where((object) => object.hasGeometry && object.effectiveVisible)
          .length >
      1;
  bool get _exploded => _explodeFactor > 0.001;

  bool get _busy =>
      _importing ||
      _editing ||
      _exporting ||
      _splitting ||
      _inspecting ||
      _annotationBusy ||
      (_editState?.busy ?? false);

  String get _modelTitle {
    final raw = _loadedPath ?? widget.modelPath;
    if (raw == null || raw.isEmpty) return '工程工作区';
    final parts = raw
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts.isEmpty ? '工程工作区' : parts.last;
  }

  String get _modelMeta {
    if (!_hasModel) return '从文件页打开工程模型';
    final triangles = _triangleCount >= 1000000
        ? '${(_triangleCount / 1000000).toStringAsFixed(1)}M'
        : _triangleCount >= 1000
        ? '${(_triangleCount / 1000).toStringAsFixed(1)}k'
        : '$_triangleCount';
    return '${_loadedFormat.toUpperCase()} · $triangles 三角面'
        '${_exactGeometry ? ' · Exact B-Rep' : ''}'
        '${_hasUv ? ' · UV' : ''}'
        '${_hasNormals ? ' · N' : ''}';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadIfReady());
  }

  @override
  void didUpdateWidget(covariant EngineeringWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelPath != widget.modelPath) unawaited(_loadIfReady());
  }

  Future<void> _ensureSurface(Size size) async {
    if (size.width < 2 || size.height < 2) return;
    final width = size.width.round();
    final height = size.height.round();
    if (_textureId == null) {
      final id = await CadEngine.instance.createViewport(
        width: width,
        height: height,
      );
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
      // Supplementary progress only.
    }
  }

  Future<void> _cancelImport() async {
    final accepted = await CadEngineV01Tools.instance.cancelImport();
    if (!mounted) return;
    setState(() => _status = accepted ? '正在取消导入…' : '当前没有可取消的导入任务');
  }

  void _clearMeasure({bool leaveMode = false}) {
    _measurePoints.clear();
    _measureResult = null;
    _lastPick = null;
    if (leaveMode) {
      _measureMode = _MeasureMode.none;
      _precisionPick = false;
    }
  }

  void _clearSelection({bool leaveMode = false}) {
    _selection = null;
    if (leaveMode) _selectionActive = false;
    unawaited(CadEngineV01Tools.instance.clearSelectionHighlight());
  }

  Future<void> _loadIfReady() async {
    final path = widget.modelPath;
    if (path == null ||
        path.isEmpty ||
        path == _loadedPath ||
        _textureId == null ||
        _importing) {
      return;
    }

    setState(() {
      _importing = true;
      _status = '正在载入模型…';
      _clearMeasure(leaveMode: true);
      _clearSelection(leaveMode: true);
    });
    _startProgressPolling();

    try {
      final result = await CadEngine.instance.loadModel(path);
      if (!mounted) return;
      if (!result.ok) {
        setState(
          () => _status = _loadedPath == null
              ? '打开失败：${result.message}'
              : '${result.message} · 已保留上一模型',
        );
        return;
      }

      // Commit the successfully loaded model to UI state before optional metadata
      // probes. A presentation/metadata failure must never erase the current
      // document handle or leave the Viewer looking interactive while picks
      // silently return because `_documentHandle == null`.
      if (!mounted) return;
      setState(() {
        _loadedPath = path;
        _documentHandle = null;
        _objects = const [];
        _annotationModelKey = null;
        _annotations = const [];
        _editState = null;
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
        _explodeFactor = 0.0;
        _runtimeReady = false;
        _runtimeFault = null;
        _status =
            '${result.formatId.toUpperCase()} 已载入 · '
            '${result.triangleCount} 三角面 · 正在验证 Android 运行桥…';
      });
      _fitAll();

      int? handle;
      MeshEditState? editState;
      try {
        // `getImportProgress` is intentionally handled by CadEngineEntrypoint,
        // not the core plugin. Calling it here is a cheap real-runtime
        // handshake that catches wrong MethodChannel handler registration.
        await CadEngineV01Tools.instance.importProgress();
        handle = await CadEngine.instance.getCurrentDocumentHandle();
        if (handle == null || handle <= 0) {
          throw PlatformException(
            code: 'RUNTIME_NO_DOCUMENT',
            message: '模型已载入，但 Android bridge 没有返回 current document handle。',
          );
        }
        // This is the second facade-only handshake and also establishes the
        // initial edit state independently of object-presentation parsing.
        editState = await CadEngine.instance.getMeshEditState();
      } on MissingPluginException catch (error) {
        if (!mounted) return;
        final message = 'Android 运行桥未注册：${error.message ?? 'cad_engine/methods'}';
        setState(() {
          _runtimeReady = false;
          _runtimeFault = message;
          _status = message;
        });
        return;
      } on PlatformException catch (error) {
        if (!mounted) return;
        final message = 'Android 运行桥异常：${error.message ?? error.code}';
        setState(() {
          _runtimeReady = false;
          _runtimeFault = message;
          _status = message;
        });
        return;
      }

      List<CadObjectPresentation> objects = const [];
      try {
        objects = await CadEngine.instance.getObjectPresentation();
      } on PlatformException {
        // Object hierarchy is optional. It must not invalidate selection,
        // measurement, sectioning or editing for a valid loaded document.
        objects = const [];
      } on FormatException {
        objects = const [];
      }

      if (!mounted) return;
      setState(() {
        _documentHandle = handle;
        _objects = objects;
        _editState = editState;
        _runtimeReady = true;
        _runtimeFault = null;
        _status =
            '${result.formatId.toUpperCase()} 已载入 · '
            '${result.triangleCount} 三角面 · 工程工具已就绪';
      });
      unawaited(_loadAnnotationsForModel(path, result));
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

  void _setStandardView(String view) {
    final target = switch (view) {
      'front' => (0.0, 0.0),
      'back' => (3.141592653589793, 0.0),
      'right' => (1.5707963267948966, 0.0),
      'left' => (-1.5707963267948966, 0.0),
      'top' => (0.0, -1.55),
      'bottom' => (0.0, 1.55),
      _ => (0.72, -0.52),
    };
    final dx = (target.$1 - _orbitX) / 0.010;
    final dy = (target.$2 - _orbitY) / 0.010;
    _orbitX = target.$1;
    _orbitY = target.$2;
    unawaited(CadEngine.instance.orbit(dx, dy));
    _fitAll();
    if (!mounted) return;
    setState(() {
      _status = switch (view) {
        'front' => '前视图',
        'back' => '后视图',
        'right' => '右视图',
        'left' => '左视图',
        'top' => '顶视图',
        'bottom' => '底视图',
        _ => '等轴测视图',
      };
    });
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

  String _measureName(_MeasureMode mode) => switch (mode) {
    _MeasureMode.coordinate => '坐标',
    _MeasureMode.distance => '距离',
    _MeasureMode.angle => '角度',
    _MeasureMode.radius => '半径',
    _MeasureMode.area => '面积',
    _MeasureMode.none => '',
  };

  int _requiredPoints(_MeasureMode mode) => switch (mode) {
    _MeasureMode.coordinate => 1,
    _MeasureMode.distance => 2,
    _MeasureMode.angle || _MeasureMode.radius || _MeasureMode.area => 3,
    _MeasureMode.none => 0,
  };

  void _setMeasureMode(_MeasureMode mode) {
    setState(() {
      _measureMode = mode;
      _clearMeasure();
      if (mode != _MeasureMode.none) _clearSelection(leaveMode: true);
      _status = switch (mode) {
        _MeasureMode.coordinate => '坐标测量 · 选择 1 个点',
        _MeasureMode.distance => '距离测量 · 选择 2 个点',
        _MeasureMode.angle => '角度测量 · 选择 A、B、C',
        _MeasureMode.radius => '半径测量 · 选择圆弧上的 3 个点',
        _MeasureMode.area => '面积测量 · 选择空间中的 3 个点',
        _MeasureMode.none => '已退出测量',
      };
      if (mode == _MeasureMode.none) _precisionPick = false;
    });
  }

  String _number(double value) {
    final abs = value.abs();
    if (abs >= 100000 || (abs > 0 && abs < 0.001)) {
      return value.toStringAsExponential(4);
    }
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _coordinate(CadPickPoint point) =>
      'X ${_number(point.x)} · Y ${_number(point.y)} · Z ${_number(point.z)}';

  Future<CadPickPoint?> _pickAt(Offset position) async {
    final handle = _documentHandle;
    if (handle == null || _surfaceSize.shortestSide < 2) return null;
    return CadEngineV01Tools.instance.pickModelPoint(
      documentHandle: handle,
      width: _surfaceSize.width.round(),
      height: _surfaceSize.height.round(),
      orbitX: _orbitX,
      orbitY: _orbitY,
      panX: _panX,
      panY: _panY,
      zoom: _zoom,
      orthographic: _projection == 'orthographic',
      screenX: position.dx,
      screenY: position.dy,
    );
  }

  Future<void> _consumePick(Offset position) async {
    if (!_measuring) return;
    final point = await _pickAt(position);
    if (!mounted) return;
    if (point == null) {
      setState(() => _status = '该位置没有命中模型');
      return;
    }

    _measurePoints.add(point);
    _lastPick = point;
    final required = _requiredPoints(_measureMode);
    if (_measurePoints.length < required) {
      setState(() {
        _status =
            '已选 ${_measurePoints.length} / $required 点 · ${_coordinate(point)}';
      });
      return;
    }

    final points = List<CadPickPoint>.of(_measurePoints);
    final result = switch (_measureMode) {
      _MeasureMode.coordinate => '坐标 ${_coordinate(points[0])}',
      _MeasureMode.distance =>
        '距离 ${_number(CadMeasurement.distance(points[0], points[1]))}',
      _MeasureMode.angle => (() {
        final value = CadMeasurement.angle(points[0], points[1], points[2]);
        return value == null ? '角度无法计算' : '角度 ${_number(value)}°';
      })(),
      _MeasureMode.radius => (() {
        final value = CadMeasurement.radius(points[0], points[1], points[2]);
        return value == null ? '半径无法计算' : '半径 R ${_number(value)}';
      })(),
      _MeasureMode.area =>
        '面积 ${_number(CadMeasurement.area(points[0], points[1], points[2]))}',
      _MeasureMode.none => '',
    };
    setState(() {
      _measureResult = result;
      _measurePoints.clear();
      _status = result;
    });
  }

  Future<void> _capturePrecisionCenter() async {
    if (!_precisionPick || !_measuring || _surfaceSize.shortestSide < 2) return;
    await _consumePick(
      Offset(_surfaceSize.width * 0.5, _surfaceSize.height * 0.5),
    );
  }

  String _selectionName(CadSelectionFilter filter) => switch (filter) {
    CadSelectionFilter.vertex => '顶点',
    CadSelectionFilter.edge => '边',
    CadSelectionFilter.face => '面',
    CadSelectionFilter.body => '对象',
  };

  Future<void> _setSelectionFilter(CadSelectionFilter filter) async {
    setState(() {
      _clearMeasure(leaveMode: true);
      _clearSelection();
      _selectionFilter = filter;
      _selectionActive = true;
      _status = '${_selectionName(filter)}选择 · 点击模型';
    });
  }

  Future<void> _selectAt(Offset position) async {
    if (!_selectionActive || _measuring) return;
    final point = await _pickAt(position);
    if (!mounted) return;
    if (point == null) {
      setState(() => _status = '该位置没有命中模型');
      return;
    }
    final accepted = switch (_selectionFilter) {
      CadSelectionFilter.vertex => point.snapKind == CadSnapKind.vertex,
      CadSelectionFilter.edge => point.snapKind == CadSnapKind.edgeMidpoint,
      CadSelectionFilter.face || CadSelectionFilter.body => true,
    };
    if (!accepted) {
      _clearSelection();
      setState(
        () => _status = '未命中${_selectionName(_selectionFilter)} · 请靠近目标特征再点一次',
      );
      return;
    }
    await CadEngineV01Tools.instance.setSelectionHighlight(
      filter: _selectionFilter,
      point: point,
    );
    if (!mounted) return;
    setState(() {
      _selection = point;
      final object = _selectedObject;
      _status =
          '${_selectionName(_selectionFilter)}已选择 · '
          '${object?.displayLabel ?? point.featureStableId}';
    });
  }

  Future<void> _showSelectionProperties() async {
    final point = _selection;
    if (point == null) return;
    final object = _selectedObject;
    final rows = <(String, String)>[
      ('选择类型', _selectionName(_selectionFilter)),
      ('稳定特征 ID', point.featureStableId),
      ('三角面', '#${point.triangleIndex}'),
      ('X', _number(point.x)),
      ('Y', _number(point.y)),
      ('Z', _number(point.z)),
      ('深度', _number(point.depth)),
      ('模型格式', _loadedFormat.toUpperCase()),
      ('精确几何', _exactGeometry ? '是' : '否'),
      if (object != null) ('对象', object.displayLabel),
      if (object != null) ('对象 ID', object.id),
      if (object != null && object.type.isNotEmpty) ('对象类型', object.type),
      if (object != null) ('可见', object.effectiveVisible ? '是' : '否'),
      if (object != null && object.hasBaseColor)
        (
          '基础颜色',
          object.baseColor.map((value) => value.toStringAsFixed(3)).join(' / '),
        ),
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _InfoSheet(
        title: '选择属性',
        rows: rows,
        note: object == null
            ? '当前格式未暴露独立对象层级；属性仍绑定到稳定网格特征。'
            : '对象属性来自导入文档的本地 presentation 元数据，不依赖云端服务。',
      ),
    );
  }

  Future<void> _showSelectionTools() async {
    if (!_hasModel || _busy || _exploded) return;
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('选择过滤'),
              subtitle: Text('只允许目标特征被选中；高亮保持在 native 3D 视图中'),
            ),
            for (final item in const <(String, String, IconData)>[
              ('vertex', '顶点', Icons.circle_outlined),
              ('edge', '边', Icons.horizontal_rule),
              ('face', '面', Icons.change_history_outlined),
              ('body', '对象', Icons.view_in_ar_outlined),
            ])
              ListTile(
                leading: Icon(item.$3),
                title: Text(item.$2),
                trailing: _selectionFilter.name == item.$1 && _selectionActive
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, item.$1),
              ),
            if (_selection != null) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('属性'),
                subtitle: Text(_selection!.featureStableId),
                onTap: () => Navigator.pop(context, 'properties'),
              ),
              ListTile(
                leading: const Icon(Icons.deselect),
                title: const Text('清除选择'),
                onTap: () => Navigator.pop(context, 'clear'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || value == null) return;
    switch (value) {
      case 'vertex':
        await _setSelectionFilter(CadSelectionFilter.vertex);
        break;
      case 'edge':
        await _setSelectionFilter(CadSelectionFilter.edge);
        break;
      case 'face':
        await _setSelectionFilter(CadSelectionFilter.face);
        break;
      case 'body':
        await _setSelectionFilter(CadSelectionFilter.body);
        break;
      case 'properties':
        await _showSelectionProperties();
        break;
      case 'clear':
        setState(() {
          _clearSelection(leaveMode: true);
          _status = '选择已清除';
        });
        break;
    }
  }

  Future<void> _showMeasurementTools() async {
    if (!_hasModel || _busy || _exploded) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _measureTile(
                sheetContext,
                Icons.my_location,
                '点坐标',
                '读取模型空间 X / Y / Z 坐标',
                _MeasureMode.coordinate,
              ),
              _measureTile(
                sheetContext,
                Icons.straighten,
                '两点距离',
                '选择模型上的两个位置',
                _MeasureMode.distance,
              ),
              _measureTile(
                sheetContext,
                Icons.architecture_outlined,
                '三点角度',
                'A — 顶点 B — C',
                _MeasureMode.angle,
              ),
              _measureTile(
                sheetContext,
                Icons.radio_button_unchecked,
                '三点半径',
                '选择圆或圆弧上的三个位置',
                _MeasureMode.radius,
              ),
              _measureTile(
                sheetContext,
                Icons.change_history_outlined,
                '三点面积',
                '计算任意空间平面三角形面积',
                _MeasureMode.area,
              ),
              const Divider(),
              SwitchListTile(
                secondary: const Icon(Icons.center_focus_weak),
                title: const Text('精确十字光标'),
                subtitle: const Text('拖动模型对准中心十字，再点“捕捉中心”；手指不会遮挡目标'),
                value: _precisionPick,
                onChanged: (value) {
                  setState(() => _precisionPick = value);
                  updateSheet(() {});
                },
              ),
              if (_measuring)
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('退出测量'),
                  onTap: () {
                    _setMeasureMode(_MeasureMode.none);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _measureTile(
    BuildContext sheetContext,
    IconData icon,
    String title,
    String subtitle,
    _MeasureMode mode,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () {
        _setMeasureMode(mode);
        Navigator.pop(sheetContext);
      },
    );
  }

  Future<void> _loadAnnotationsForModel(
    String path,
    CadLoadResult result,
  ) async {
    try {
      final key = await ModelAnnotationIdentity.forModel(
        sourcePath: path,
        formatId: result.formatId,
        triangleCount: result.triangleCount,
        rootObjectCount: result.rootObjectCount,
        hierarchyNodeCount: result.hierarchyNodeCount,
      );
      final annotations = await LocalAnnotationStore.instance.load(key);
      if (!mounted || _loadedPath != path) return;
      setState(() {
        _annotationModelKey = key;
        _annotations = annotations;
      });
    } catch (_) {
      // Local review data must never delay or invalidate model display. The
      // user can still view the model and retry persistence when creating a note.
    }
  }

  Future<String?> _ensureAnnotationModelKey() async {
    final existing = _annotationModelKey;
    if (existing != null && existing.isNotEmpty) return existing;
    final path = _loadedPath;
    if (path == null || path.isEmpty) return null;
    try {
      final key = await ModelAnnotationIdentity.forModel(
        sourcePath: path,
        formatId: _loadedFormat,
        triangleCount: _triangleCount,
        rootObjectCount: _rootObjectCount,
        hierarchyNodeCount: _hierarchyNodeCount,
      );
      if (mounted) setState(() => _annotationModelKey = key);
      return key;
    } catch (_) {
      return null;
    }
  }

  String _persistentAnnotationFeatureId(
    CadPickPoint point,
    CadSelectionFilter filter,
  ) =>
      'triangle:${point.triangleIndex}:${filter.name}:${point.featureIndex}:'
      'object:${point.objectIndex}';

  CadPickPoint? get _annotationAnchor {
    if (_editActive || _sectionEnabled || _exploded) return null;
    return _selection;
  }

  Future<String> _captureAnnotationScreenshot() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _viewportCaptureKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      throw StateError('当前模型视图尚未准备好截图。');
    }

    const maxBytes = 220 * 1024;
    for (final ratio in const <double>[0.40, 0.25]) {
      final image = await boundary.toImage(pixelRatio: ratio);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) continue;
        final bytes = data.buffer.asUint8List();
        if (bytes.length <= maxBytes) return base64Encode(bytes);
      } finally {
        image.dispose();
      }
    }
    throw StateError('当前视图截图超过本地批注缩略图大小限制。');
  }

  Future<void> _createAnnotation() async {
    if (!_hasModel || _annotationBusy) return;
    final anchor = _annotationAnchor;
    final filter = _selectionFilter;
    final request = await showAnnotationComposer(
      context: context,
      anchored: anchor != null,
    );
    if (!mounted || request == null) return;

    setState(() => _annotationBusy = true);
    try {
      final modelKey = await _ensureAnnotationModelKey();
      if (modelKey == null) {
        throw StateError('无法建立当前模型的本地批注身份。');
      }
      final screenshot = request.includeScreenshot
          ? await _captureAnnotationScreenshot()
          : null;
      final now = DateTime.now();
      final annotation = LocalModelAnnotation(
        id: '${now.microsecondsSinceEpoch}',
        text: request.text,
        createdAtMillis: now.millisecondsSinceEpoch,
        anchorKind: anchor == null ? null : filter.name,
        featureStableId: anchor == null
            ? null
            : _persistentAnnotationFeatureId(anchor, filter),
        triangleIndex: anchor?.triangleIndex ?? -1,
        featureIndex: anchor?.featureIndex ?? -1,
        objectIndex: anchor?.objectIndex ?? -1,
        x: anchor?.x,
        y: anchor?.y,
        z: anchor?.z,
        depth: anchor?.depth,
        screenshotPngBase64: screenshot,
      );
      final next = <LocalModelAnnotation>[annotation, ..._annotations];
      await LocalAnnotationStore.instance.save(modelKey, next);
      if (!mounted) return;
      setState(() {
        _annotations = next;
        _status = anchor == null ? '模型级批注已保存' : '几何锚点批注已保存';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '批注保存失败：$error');
    } finally {
      if (mounted) setState(() => _annotationBusy = false);
    }
  }

  Future<void> _deleteAnnotation(LocalModelAnnotation annotation) async {
    final modelKey = _annotationModelKey;
    if (modelKey == null || _annotationBusy) return;
    final next = _annotations
        .where((item) => item.id != annotation.id)
        .toList(growable: false);
    setState(() => _annotationBusy = true);
    try {
      await LocalAnnotationStore.instance.save(modelKey, next);
      if (!mounted) return;
      setState(() {
        _annotations = next;
        _status = '本地批注已删除';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '删除批注失败：$error');
    } finally {
      if (mounted) setState(() => _annotationBusy = false);
    }
  }

  Future<void> _openAnnotation(LocalModelAnnotation annotation) async {
    if (!annotation.hasAnchor) {
      if (mounted) setState(() => _status = '模型级批注 · ${annotation.text}');
      return;
    }
    if (_editActive || _sectionEnabled || _exploded) {
      if (mounted) {
        setState(() => _status = '该批注带几何锚点 · 请先恢复未编辑、未剖切、未爆炸的显示状态');
      }
      return;
    }
    final handle = _documentHandle;
    if (handle == null) return;
    final filter = switch (annotation.anchorKind) {
      'vertex' => CadSelectionFilter.vertex,
      'edge' => CadSelectionFilter.edge,
      'body' => CadSelectionFilter.body,
      _ => CadSelectionFilter.face,
    };
    final snapKind = switch (filter) {
      CadSelectionFilter.vertex => CadSnapKind.vertex,
      CadSelectionFilter.edge => CadSnapKind.edgeMidpoint,
      CadSelectionFilter.face ||
      CadSelectionFilter.body => CadSnapKind.faceCenter,
    };
    final point = CadPickPoint(
      x: annotation.x!,
      y: annotation.y!,
      z: annotation.z!,
      triangleIndex: annotation.triangleIndex,
      depth: annotation.depth!,
      documentHandle: handle,
      snapKind: snapKind,
      featureIndex: annotation.featureIndex,
      objectIndex: annotation.objectIndex,
    );
    await CadEngineV01Tools.instance.setSelectionHighlight(
      filter: filter,
      point: point,
    );
    if (!mounted) return;
    setState(() {
      _clearMeasure(leaveMode: true);
      _selectionActive = true;
      _selectionFilter = filter;
      _selection = point;
      _status = '已定位批注锚点 · ${annotation.text}';
    });
  }

  Future<void> _showAnnotations() async {
    if (!_hasModel || _annotationBusy) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => LocalAnnotationSheet(
        annotations: _annotations,
        onAdd: () => unawaited(_createAnnotation()),
        onOpen: (annotation) => unawaited(_openAnnotation(annotation)),
        onDelete: (annotation) => unawaited(_deleteAnnotation(annotation)),
      ),
    );
  }

  Future<void> _showExplodeControls() async {
    if (!_canExplode || _busy || _editActive || _sectionEnabled) return;
    setState(() {
      _clearMeasure(leaveMode: true);
      _clearSelection(leaveMode: true);
    });
    var factor = _explodeFactor;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('爆炸视图', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('按对象绘制分区从模型中心向外展开；只改变显示位置，不修改源 CAD / 网格。'),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('展开'),
                  Expanded(
                    child: Slider(
                      value: factor,
                      onChanged: (value) {
                        factor = value;
                        updateSheet(() {});
                        setState(() => _explodeFactor = value);
                        unawaited(
                          CadEngineV01Tools.instance.setExplodeFactor(value),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${(factor * 100).round()}%',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: factor <= 0.001
                    ? null
                    : () {
                        factor = 0.0;
                        updateSheet(() {});
                        setState(() => _explodeFactor = 0.0);
                        unawaited(
                          CadEngineV01Tools.instance.setExplodeFactor(0),
                        );
                      },
                icon: const Icon(Icons.restart_alt),
                label: const Text('复位'),
              ),
            ],
          ),
        ),
      ),
    );
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
      if (!ok) {
        throw PlatformException(
          code: 'SECTION_REJECTED',
          message: 'Native section plane rejected the request.',
        );
      }
      final handle = await CadEngine.instance.getCurrentDocumentHandle();
      final summary = handle == null
          ? null
          : await CadEngine.instance.getDocumentSummary(handle);
      if (_explodeFactor > 0.001) {
        await CadEngineV01Tools.instance.setExplodeFactor(_explodeFactor);
      }
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
      onSetVisibility: (objectId, visible) => CadEngine.instance
          .setObjectVisibility(objectId: objectId, visible: visible),
    );
    if (updated != null && mounted) setState(() => _objects = updated);
  }

  Future<void> _syncEditState(MeshEditState state, String status) async {
    final handle = await CadEngine.instance.getCurrentDocumentHandle();
    final summary = handle == null
        ? null
        : await CadEngine.instance.getDocumentSummary(handle);
    if (!mounted) return;
    setState(() {
      _editState = state;
      _documentHandle = handle;
      if (summary != null) {
        _loadedFormat = summary.formatId;
        _triangleCount = summary.triangleCount;
        _exactGeometry = summary.exactGeometry;
      }
      _clearMeasure(leaveMode: true);
      _explodeFactor = 0.0;
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
    if (!_hasModel || _busy || _sectionEnabled || _exploded) return;
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
        onDiscard: () =>
            _editAction(CadEngine.instance.discardMeshEdit, '已恢复原模型'),
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
      setState(
        () => _status = result == null ? '已取消导出' : '已导出 ${result.displayName}',
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '导出失败：${error.message ?? error.code}');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _split(String format) async {
    if (!_hasModel || _splitting || _editActive) return;
    setState(() {
      _splitting = true;
      _status = '正在分析连通部件…';
    });
    try {
      final result = await CadEngine.instance.splitCurrentModel(format);
      if (!mounted) return;
      setState(() {
        _status = result == null
            ? '已取消部件拆分'
            : '已拆分 ${result.partCount} 个部件 · ${result.formatId.toUpperCase()}';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '拆分失败：${error.message ?? error.code}');
    } finally {
      if (mounted) setState(() => _splitting = false);
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

  Widget _viewChip(String value, String label) {
    return ActionChip(
      avatar: Icon(
        value == 'iso' ? Icons.view_in_ar_outlined : Icons.crop_square,
        size: 18,
      ),
      label: Text(label),
      onPressed: () {
        _setStandardView(value);
        Navigator.pop(context);
      },
    );
  }

  Future<void> _showViewOptions() async {
    var projection = _projection;
    var displayMode = _displayMode;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('视图与显示', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
              Text('标准视角', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _viewChip('iso', '等轴'),
                  _viewChip('front', '前'),
                  _viewChip('back', '后'),
                  _viewChip('left', '左'),
                  _viewChip('right', '右'),
                  _viewChip('top', '顶'),
                  _viewChip('bottom', '底'),
                  ActionChip(
                    avatar: const Icon(Icons.center_focus_strong, size: 18),
                    label: const Text('适配'),
                    onPressed: () {
                      _fitAll();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('投影', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'perspective',
                    label: Text('透视'),
                    icon: Icon(Icons.photo_camera_outlined),
                  ),
                  ButtonSegment(
                    value: 'orthographic',
                    label: Text('正交'),
                    icon: Icon(Icons.crop_square),
                  ),
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
                  ButtonSegment(
                    value: 'shaded',
                    label: Text('实体'),
                    icon: Icon(Icons.view_in_ar),
                  ),
                  ButtonSegment(
                    value: 'shaded_edges',
                    label: Text('边线'),
                    icon: Icon(Icons.grid_on),
                  ),
                  ButtonSegment(
                    value: 'wireframe',
                    label: Text('线框'),
                    icon: Icon(Icons.gesture),
                  ),
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
                Theme.of(context).brightness == Brightness.dark
                    ? '暗色模式使用深石墨画布和中等亮度蓝灰线框，避免夜间高亮白底。'
                    : '亮色模式使用浅灰蓝画布和深钢色线框，保证拓扑边可读。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                '显示配色自动跟随应用主题；主题选择与陀螺仪设置在“设置”页统一管理。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _chooseMeshFormat({required String title}) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(title),
              subtitle: const Text('当前已接通的稳定 writer：OBJ / STL'),
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('OBJ'),
              subtitle: Text(
                _hasUv ? '当前模型含 UV；OBJ 导出可继续携带 UV' : '当前模型无 UV；OBJ 将仅导出几何/法线能力',
              ),
              onTap: () => Navigator.pop(context, 'obj'),
            ),
            ListTile(
              leading: const Icon(Icons.view_in_ar_outlined),
              title: const Text('STL'),
              subtitle: const Text('三角网格；不保存层级、材质或 UV'),
              onTap: () => Navigator.pop(context, 'stl'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMore() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_objects.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: const Text('对象与可见性'),
                  subtitle: const Text('浏览模型层级并隐藏/显示对象'),
                  onTap: () => Navigator.pop(context, 'objects'),
                ),
              ListTile(
                leading: const Icon(Icons.rate_review_outlined),
                title: const Text('本地批注'),
                subtitle: Text(
                  _annotations.isEmpty
                      ? '文本、几何锚点与可选截图 · 仅保存在此设备'
                      : '已保存 ${_annotations.length} 条 · 仅保存在此设备',
                ),
                onTap: () => Navigator.pop(context, 'annotations'),
              ),
              if (_canExplode)
                ListTile(
                  leading: const Icon(Icons.open_with),
                  title: const Text('爆炸视图'),
                  subtitle: Text(
                    _exploded
                        ? '当前展开 ${(100 * _explodeFactor).round()}% · 可实时调整或复位'
                        : '按对象绘制分区展开装配关系',
                  ),
                  onTap: _editActive || _sectionEnabled
                      ? null
                      : () => Navigator.pop(context, 'explode'),
                ),
              ListTile(
                leading: Icon(
                  _exactGeometry
                      ? Icons.info_outline
                      : Icons.fact_check_outlined,
                ),
                title: Text(_exactGeometry ? 'CAD 信息' : '模型检查'),
                onTap: () => Navigator.pop(context, 'inspect'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('转换 / 导出'),
                subtitle: const Text('将当前显示/编辑工作副本写为 OBJ 或 STL'),
                onTap: () => Navigator.pop(context, 'export'),
              ),
              ListTile(
                leading: const Icon(Icons.call_split),
                title: const Text('拆分连通部件'),
                subtitle: const Text('按网格连通域拆出多个 OBJ / STL 文件'),
                onTap: _editActive
                    ? null
                    : () => Navigator.pop(context, 'split'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || value == null) return;
    switch (value) {
      case 'objects':
        await _showObjects();
        break;
      case 'annotations':
        await _showAnnotations();
        break;
      case 'explode':
        await _showExplodeControls();
        break;
      case 'inspect':
        await _inspect();
        break;
      case 'export':
        final format = await _chooseMeshFormat(title: '转换 / 导出当前模型');
        if (format != null && mounted) await _export(format);
        break;
      case 'split':
        final format = await _chooseMeshFormat(title: '拆分连通部件');
        if (format != null && mounted) await _split(format);
        break;
    }
  }

  Widget _texture() {
    final id = _textureId;
    if (id == null) return const SizedBox.expand();
    final texture = Texture(textureId: id);
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_displayMode == 'wireframe') {
      return ColorFiltered(
        colorFilter: ColorFilter.matrix(
          dark
              ? const <double>[
                  9.567,
                  32.184,
                  3.249,
                  0,
                  -600,
                  9.567,
                  32.184,
                  3.249,
                  0,
                  -600,
                  9.567,
                  32.184,
                  3.249,
                  0,
                  -600,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]
              : const <double>[
                  -9.567,
                  -32.184,
                  -3.249,
                  0,
                  860,
                  -9.567,
                  -32.184,
                  -3.249,
                  0,
                  860,
                  -9.567,
                  -32.184,
                  -3.249,
                  0,
                  860,
                  0,
                  0,
                  0,
                  1,
                  0,
                ],
        ),
        child: texture,
      );
    }
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        dark ? const Color(0x181E2A36) : const Color(0x70DCE4EC),
        BlendMode.screen,
      ),
      child: texture,
    );
  }

  Widget _reticle(ThemeData theme) {
    final color = theme.colorScheme.primary;
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(width: 1.5, height: 42, color: color),
              Container(width: 42, height: 1.5, color: color),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                  color: theme.colorScheme.surface.withValues(alpha: 0.18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickCard(ThemeData theme, CadPickPoint point) {
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '拾取 · 三角面 #${point.triangleIndex}',
              style: theme.textTheme.labelMedium,
            ),
            Text(_coordinate(point), style: theme.textTheme.bodySmall),
            Text(
              'ID ${point.stableId} · depth ${_number(point.depth)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final allowCamera = !_measuring || _precisionPick;
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
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _modelMeta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
            tooltip: '视图与显示',
            onPressed: _textureId == null
                ? null
                : () => unawaited(_showViewOptions()),
            icon: const Icon(Icons.view_in_ar_outlined),
          ),
          IconButton(
            tooltip: '工程操作',
            onPressed: !_hasModel || _busy || !_runtimeReady
                ? null
                : () => unawaited(_showMore()),
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final statusWidth = constraints.maxWidth > 360
              ? 320.0
              : (constraints.maxWidth - 24).clamp(0.0, 320.0);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => unawaited(_ensureSurface(size)),
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: allowCamera ? _onScaleStart : null,
            onScaleUpdate: allowCamera ? _onScaleUpdate : null,
            onTapUp: _measuring && !_precisionPick
                ? (details) => unawaited(_consumePick(details.localPosition))
                : _selectionActive
                ? (details) => unawaited(_selectAt(details.localPosition))
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  key: _viewportCaptureKey,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: dark
                            ? const Color(0xFF151B22)
                            : const Color(0xFFE7EBEF),
                      ),
                      _texture(),
                      if (!_hasModel && !_importing) const _EmptyModelState(),
                    ],
                  ),
                ),
                if (_precisionPick && _measuring) _reticle(theme),
                if (_runtimeFault != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Material(
                      color: theme.colorScheme.errorContainer.withValues(alpha: 0.96),
                      elevation: 3,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _runtimeFault!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_measuring ||
                    _selectionActive ||
                    _selection != null ||
                    _editActive ||
                    _sectionEnabled ||
                    _exploded ||
                    _annotations.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_measuring)
                              Chip(
                                avatar: const Icon(Icons.straighten, size: 18),
                                label: Text(
                                  '${_measureName(_measureMode)} · '
                                  '${_measurePoints.length} 点'
                                  '${_precisionPick ? ' · 精确' : ''}'
                                  '${_measureResult == null ? '' : ' · $_measureResult'}',
                                ),
                              ),
                            if (_selectionActive)
                              ActionChip(
                                avatar: const Icon(Icons.ads_click, size: 18),
                                label: Text(
                                  _selection == null
                                      ? '${_selectionName(_selectionFilter)}选择'
                                      : '${_selectionName(_selectionFilter)} · #${_selection!.triangleIndex}',
                                ),
                                onPressed: _selection == null
                                    ? () => unawaited(_showSelectionTools())
                                    : () =>
                                          unawaited(_showSelectionProperties()),
                              ),
                            if (_annotations.isNotEmpty)
                              ActionChip(
                                avatar: const Icon(
                                  Icons.rate_review_outlined,
                                  size: 18,
                                ),
                                label: Text('批注 ${_annotations.length}'),
                                onPressed: () => unawaited(_showAnnotations()),
                              ),
                            if (_exploded)
                              Chip(
                                avatar: const Icon(Icons.open_with, size: 18),
                                label: Text(
                                  '爆炸 ${(100 * _explodeFactor).round()}%',
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
                                label: Text(
                                  '${_sectionAxis.toUpperCase()} ≥ '
                                  '${_number(_sectionOffset)}',
                                ),
                              ),
                          ],
                        ),
                        if (_measuring) ...[
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: statusWidth),
                            child: Material(
                              color: theme.colorScheme.surface.withValues(
                                alpha: 0.92,
                              ),
                              elevation: 1,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(right: 7),
                                      child: Icon(
                                        Icons.info_outline,
                                        size: 16,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
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
                        ],
                        if (_lastPick != null && _measuring) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              width: constraints.maxWidth < 380 ? 238 : 270,
                              child: _pickCard(theme, _lastPick!),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_precisionPick && _measuring)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.extended(
                      heroTag: 'precision-pick',
                      onPressed: () => unawaited(_capturePrecisionCenter()),
                      icon: const Icon(Icons.gps_fixed),
                      label: const Text('捕捉中心'),
                    ),
                  ),
                if (!_measuring)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    width: statusWidth,
                    child: IgnorePointer(
                      child: Material(
                        color: theme.colorScheme.surface.withValues(
                          alpha: 0.88,
                        ),
                        elevation: 1,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              if (_importing || _editing || _splitting)
                                const Padding(
                                  padding: EdgeInsets.only(right: 9),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(right: 7),
                                  child: Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  _status,
                                  maxLines: 1,
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
              runtimeReady: _runtimeReady,
              exploded: _exploded,
              selectionActive: _selectionActive,
              measurementActive: _measuring,
              sectionActive: _sectionEnabled,
              editActive: _editActive,
              onSelect: () => unawaited(_showSelectionTools()),
              onMeasure: () => unawaited(_showMeasurementTools()),
              onSection: () => unawaited(_showSectionControls()),
              onEdit: () => unawaited(_showEditor()),
            )
          : null,
    );
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    unawaited(CadEngineV01Tools.instance.setExplodeFactor(0));
    unawaited(CadEngineV01Tools.instance.clearSelectionHighlight());
    unawaited(CadEngine.instance.disposeViewport());
    super.dispose();
  }
}

class _ToolDock extends StatelessWidget {
  const _ToolDock({
    required this.busy,
    required this.runtimeReady,
    required this.exploded,
    required this.selectionActive,
    required this.measurementActive,
    required this.sectionActive,
    required this.editActive,
    required this.onSelect,
    required this.onMeasure,
    required this.onSection,
    required this.onEdit,
  });

  final bool busy;
  final bool runtimeReady;
  final bool exploded;
  final bool selectionActive;
  final bool measurementActive;
  final bool sectionActive;
  final bool editActive;
  final VoidCallback onSelect;
  final VoidCallback onMeasure;
  final VoidCallback onSection;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _ToolButton(
                icon: Icons.ads_click,
                label: '选择',
                active: selectionActive,
                enabled: runtimeReady && !busy && !exploded,
                onTap: onSelect,
              ),
              _ToolButton(
                icon: Icons.straighten,
                label: '测量',
                active: measurementActive,
                enabled: runtimeReady && !busy && !exploded,
                onTap: onMeasure,
              ),
              _ToolButton(
                icon: Icons.content_cut,
                label: '剖切',
                active: sectionActive,
                enabled: runtimeReady && !busy && !editActive,
                onTap: onSection,
              ),
              _ToolButton(
                icon: Icons.transform,
                label: '编辑',
                active: editActive,
                enabled: runtimeReady && !busy && !sectionActive && !exploded,
                onTap: onEdit,
              ),
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
    final color = active
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: active
                      ? theme.colorScheme.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
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
            Icon(
              Icons.view_in_ar_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('尚未打开模型', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '返回文件页选择 STL、OBJ、STEP、IGES、3MF、3DM 等模型。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionRequest {
  const _SectionRequest({
    required this.enabled,
    required this.axis,
    required this.offset,
  });

  final bool enabled;
  final String axis;
  final double offset;
}

class _SectionSheet extends StatefulWidget {
  const _SectionSheet({
    required this.enabled,
    required this.axis,
    required this.offset,
  });

  final bool enabled;
  final String axis;
  final double offset;

  @override
  State<_SectionSheet> createState() => _SectionSheetState();
}

class _SectionSheetState extends State<_SectionSheet> {
  late bool enabled = widget.enabled;
  late String axis = widget.axis;
  late final TextEditingController controller = TextEditingController(
    text: widget.offset.toString(),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
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
            onSelectionChanged: enabled
                ? (value) => setState(() => axis = value.first)
                : null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
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
              Navigator.pop(
                context,
                _SectionRequest(
                  enabled: enabled,
                  axis: axis,
                  offset: offset ?? 0,
                ),
              );
            },
            child: const Text('应用'),
          ),
        ],
      ),
    );
  }
}

class _InfoSheet extends StatelessWidget {
  const _InfoSheet({
    required this.title,
    required this.rows,
    required this.note,
  });

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
