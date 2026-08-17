import 'dart:async';

import 'package:cad_engine/cad_engine.dart';
import 'package:cad_engine/src/release/v01_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'object_presentation_sheet.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key, required this.modelPath});

  final String? modelPath;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  int? _textureId;
  int? _documentHandle;
  Size _surfaceSize = Size.zero;
  String? _loadedPath;
  String _status = '尚未打开模型';
  String _projection = 'perspective';
  String _displayMode = 'shaded_edges';
  String _loadedFormat = 'unknown';
  int _triangleCount = 0;
  bool _hasUv = false;
  bool _hasNormals = false;
  bool _exactGeometry = false;
  int _rootObjectCount = 0;
  int _hierarchyNodeCount = 0;
  List<CadObjectPresentation> _objectPresentation = const [];
  bool _exporting = false;
  bool _analyzing = false;
  bool _splitting = false;
  bool _importing = false;
  Timer? _importProgressTimer;
  Offset? _lastFocalPoint;
  double _lastScale = 1;

  // Mirrors the native camera state so screen picks use the exact same view
  // transform as the GLES renderer.
  double _cameraOrbitX = 0.55;
  double _cameraOrbitY = -0.35;
  double _cameraPanX = 0;
  double _cameraPanY = 0;
  double _cameraZoom = 1;

  CadMeasurementMode _measurementMode = CadMeasurementMode.none;
  final List<CadPickPoint> _measurementPoints = <CadPickPoint>[];
  String? _measurementResult;

  bool _sectionEnabled = false;
  String _sectionAxis = 'z';
  double _sectionOffset = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadIfNeeded());
  }

  @override
  void didUpdateWidget(covariant ViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelPath != widget.modelPath) {
      unawaited(_loadIfNeeded());
    }
  }

  Future<void> _ensureSurface(Size size) async {
    if (size.width < 2 || size.height < 2) return;
    final width = size.width.round();
    final height = size.height.round();
    if (_textureId == null) {
      final textureId = await CadEngine.instance.createViewport(width: width, height: height);
      if (!mounted) return;
      setState(() {
        _textureId = textureId;
        _surfaceSize = size;
      });
      await CadEngine.instance.setProjection(_projection);
      await CadEngine.instance.setDisplayMode(_displayMode);
      await _loadIfNeeded();
      return;
    }

    if ((_surfaceSize.width - size.width).abs() >= 2 ||
        (_surfaceSize.height - size.height).abs() >= 2) {
      _surfaceSize = size;
      await CadEngine.instance.resizeViewport(width: width, height: height);
    }
  }

  Future<void> _refreshImportProgress() async {
    if (!_importing) return;
    try {
      final progress = await CadEngineV01Tools.instance.importProgress();
      if (!mounted || !_importing || !progress.active) return;
      final label = switch (progress.stage) {
        'queued' => '排队',
        'preparing' => '预处理',
        'importing' => '解析 / 构建几何',
        'finalizing' => '提交文档',
        'restoring' => '恢复上一文档',
        'cancelling' => '正在取消',
        _ => progress.stage,
      };
      setState(() {
        _status = '正在载入模型 · $label · ${progress.progress}%';
      });
    } on PlatformException {
      // Progress is supplementary; the load result remains authoritative.
    }
  }

  void _startImportProgressPolling() {
    _importProgressTimer?.cancel();
    _importProgressTimer = Timer.periodic(
      const Duration(milliseconds: 350),
      (_) => unawaited(_refreshImportProgress()),
    );
  }

  Future<void> _cancelImport() async {
    final accepted = await CadEngineV01Tools.instance.cancelImport();
    if (!mounted) return;
    setState(() {
      _status = accepted ? '已请求取消；当前文档会保持不变…' : '当前没有可取消的导入任务';
    });
  }

  Future<void> _loadIfNeeded() async {
    final path = widget.modelPath;
    if (path == null || path == _loadedPath || _textureId == null || _importing) return;
    if (mounted) {
      setState(() {
        _status = '正在载入模型…';
        _importing = true;
        _measurementMode = CadMeasurementMode.none;
        _measurementPoints.clear();
        _measurementResult = null;
      });
    }
    _startImportProgressPolling();

    CadLoadResult result;
    try {
      result = await CadEngine.instance.loadModel(path);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '打开失败：${error.message ?? error.code} · 已保留上一文档';
      });
      return;
    } finally {
      _importProgressTimer?.cancel();
      _importProgressTimer = null;
      if (mounted) setState(() => _importing = false);
    }

    List<CadObjectPresentation> presentation = const [];
    String? presentationWarning;
    int? documentHandle;
    if (result.ok) {
      try {
        presentation = await CadEngine.instance.getObjectPresentation();
        documentHandle = await CadEngine.instance.getCurrentDocumentHandle();
      } on PlatformException catch (error) {
        presentationWarning = error.message ?? error.code;
      } on FormatException catch (error) {
        presentationWarning = error.message;
      }
    }

    if (!mounted) return;
    setState(() {
      if (result.ok) {
        _loadedPath = path;
        _documentHandle = documentHandle;
        _objectPresentation = presentation;
        _loadedFormat = result.formatId;
        _triangleCount = result.triangleCount;
        _hasUv = result.hasUv;
        _hasNormals = result.hasNormals;
        _exactGeometry = result.exactGeometry;
        _rootObjectCount = result.rootObjectCount;
        _hierarchyNodeCount = result.hierarchyNodeCount;
        _cameraPanX = 0;
        _cameraPanY = 0;
        _cameraZoom = 1;
        final meshInfo = result.triangleCount > 0 ? ' · ${result.triangleCount} 显示三角面' : '';
        final uvInfo = result.hasUv ? ' · UV' : '';
        final exactInfo = result.exactGeometry
            ? ' · Exact B-Rep · ${result.rootObjectCount} 根对象 · ${result.hierarchyNodeCount} 层级节点'
            : '';
        final objectInfo = presentation.isNotEmpty ? ' · ${presentation.length} 对象' : '';
        final warningInfo = presentationWarning == null ? '' : ' · 对象树不可用';
        _status = '已打开：${result.displayName} · ${result.formatId.toUpperCase()}$exactInfo$meshInfo$uvInfo$objectInfo$warningInfo';
      } else if (_loadedPath != null) {
        // Native 0.1 import orchestration preserves the previous visible
        // document on failure/cancellation. Preserve the matching UI metadata.
        _status = '${result.message} · 上一个模型仍保持打开';
      } else {
        _documentHandle = null;
        _objectPresentation = const [];
        _loadedFormat = 'unknown';
        _triangleCount = 0;
        _hasUv = false;
        _hasNormals = false;
        _exactGeometry = false;
        _rootObjectCount = 0;
        _hierarchyNodeCount = 0;
        _status = '打开失败：${result.message}';
      }
    });
  }

  Future<void> _showObjectPresentation() async {
    if (_objectPresentation.isEmpty || _loadedPath == null) return;
    await showObjectPresentationSheet(
      context: context,
      objects: _objectPresentation,
      onSetVisibility: (objectId, visible) async {
        final updated = await CadEngine.instance.setObjectVisibility(
          objectId: objectId,
          visible: visible,
        );
        if (mounted) {
          setState(() {
            _objectPresentation = updated;
            final visibleGeometry = updated.where((object) => object.hasGeometry && object.effectiveVisible).length;
            final geometryCount = updated.where((object) => object.hasGeometry).length;
            _status = '对象可见性已更新 · $visibleGeometry / $geometryCount 个几何对象可见';
          });
        }
        return updated;
      },
    );
  }

  Future<bool> _confirmLoss(String formatId, String action) async {
    final losses = <String>[];
    if (_exactGeometry && (formatId == 'obj' || formatId == 'stl')) {
      losses.add('精确 B-Rep / NURBS 曲面、XCAF 装配语义与可编辑拓扑将变成显示网格');
    }
    if (formatId == 'stl' && _hasUv) {
      losses.add('UV 以及依赖 UV 的材质/贴图绑定不会写入 STL');
    }
    if (formatId == 'stl') {
      losses.add('STL 不保存对象层级、名称或材质结构');
    }
    if (losses.isEmpty) return true;

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('导出存在信息损失'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final loss in losses) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.warning_amber_rounded, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(loss)),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 4),
                Text('$action 不会修改当前原模型。'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('继续'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showExactDocumentInfo() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('精确 CAD 文档', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                '当前文档保留精确 B-Rep。屏幕上的三角面只用于实时显示，不会替换或销毁原始精确几何。',
              ),
              const SizedBox(height: 18),
              _InspectionRow(label: '格式', value: _loadedFormat.toUpperCase()),
              _InspectionRow(label: '精确几何', value: '已保留'),
              _InspectionRow(label: '根对象', value: '$_rootObjectCount'),
              _InspectionRow(label: '层级节点', value: '$_hierarchyNodeCount'),
              _InspectionRow(label: '可控制对象', value: '${_objectPresentation.length}'),
              _InspectionRow(label: '显示三角面', value: '$_triangleCount'),
              const SizedBox(height: 12),
              Text(
                '装配树和对象可见性直接作用于 native document 的 presentation state；精确 B-Rep payload 不会因为显示/隐藏而重建或丢失。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _inspect() async {
    if (_loadedPath == null || _analyzing || _splitting) return;
    if (_exactGeometry) {
      await _showExactDocumentInfo();
      return;
    }

    setState(() {
      _analyzing = true;
      _status = '正在检查模型拓扑…';
    });
    try {
      final inspection = await CadEngine.instance.analyzeCurrentModel();
      if (!mounted) return;
      setState(() => _status = inspection.closed ? '模型检查完成 · 闭合网格' : '模型检查完成 · 发现开放或异常拓扑');
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => _InspectionSheet(
          inspection: inspection,
          onSplit: inspection.connectedComponentCount > 1
              ? (formatId) {
                  Navigator.of(sheetContext).pop();
                  unawaited(_split(formatId));
                }
              : null,
        ),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '检查失败：${error.message ?? error.code}');
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _status = '检查结果解析失败：${error.message}');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _split(String formatId) async {
    if (_loadedPath == null || _splitting) return;
    if (!await _confirmLoss(formatId, '拆分出的文件')) return;

    setState(() {
      _splitting = true;
      _status = '请选择拆分部件的目标文件夹…';
    });
    try {
      final result = await CadEngine.instance.splitCurrentModel(formatId);
      if (!mounted) return;
      setState(() {
        if (result == null) {
          _status = '已取消部件拆分';
        } else {
          _status = '已拆分 ${result.partCount} 个 ${result.formatId.toUpperCase()} 部件';
        }
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '拆分失败：${error.message ?? error.code}');
    } finally {
      if (mounted) setState(() => _splitting = false);
    }
  }

  Future<void> _export(String formatId) async {
    if (_loadedPath == null || _exporting) return;
    if (!await _confirmLoss(formatId, '导出')) return;

    setState(() {
      _exporting = true;
      _status = '正在准备 ${formatId.toUpperCase()} 导出…';
    });

    try {
      final result = await CadEngine.instance.exportCurrentModel(formatId);
      if (!mounted) return;
      setState(() {
        if (result == null) {
          _status = '已取消导出';
        } else {
          _status = '已导出：${result.displayName}';
        }
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '导出失败：${error.message ?? error.code}');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _setProjection(String value) {
    if (_projection == value) return;
    setState(() => _projection = value);
    unawaited(CadEngine.instance.setProjection(value));
  }

  void _setDisplayMode(String value) {
    if (_displayMode == value) return;
    setState(() => _displayMode = value);
    unawaited(CadEngine.instance.setDisplayMode(value));
  }

  void _fitAll() {
    _cameraPanX = 0;
    _cameraPanY = 0;
    _cameraZoom = 1;
    unawaited(CadEngine.instance.fitAll());
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
        _cameraPanX += delta.dx / width;
        _cameraPanY += delta.dy / height;
        unawaited(CadEngine.instance.pan(delta.dx, delta.dy));
      } else {
        _cameraOrbitX += delta.dx * 0.010;
        _cameraOrbitY = (_cameraOrbitY + delta.dy * 0.010).clamp(-1.55, 1.55);
        unawaited(CadEngine.instance.orbit(delta.dx, delta.dy));
      }
    }

    if ((details.scale - _lastScale).abs() > 0.003) {
      final factor = details.scale / _lastScale;
      _cameraZoom = (_cameraZoom * factor).clamp(0.05, 20.0);
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
        CadMeasurementMode.distance => '距离测量：依次点击两个模型点',
        CadMeasurementMode.angle => '角度测量：依次点击 A、顶点 B、C',
        CadMeasurementMode.radius => '半径测量：点击圆/圆弧上的三个点',
        CadMeasurementMode.none => '已退出测量模式',
      };
    });
  }

  String _measurementNumber(double value) {
    final abs = value.abs();
    if (abs >= 100000 || (abs > 0 && abs < 0.001)) return value.toStringAsExponential(4);
    return value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  Future<void> _onMeasureTap(TapUpDetails details) async {
    final handle = _documentHandle;
    if (_measurementMode == CadMeasurementMode.none ||
        handle == null ||
        _surfaceSize.width < 2 ||
        _surfaceSize.height < 2) {
      return;
    }

    final hit = await CadEngineV01Tools.instance.pickModelPoint(
      documentHandle: handle,
      width: _surfaceSize.width.round(),
      height: _surfaceSize.height.round(),
      orbitX: _cameraOrbitX,
      orbitY: _cameraOrbitY,
      panX: _cameraPanX,
      panY: _cameraPanY,
      zoom: _cameraZoom,
      orthographic: _projection == 'orthographic',
      screenX: details.localPosition.dx,
      screenY: details.localPosition.dy,
    );
    if (!mounted) return;
    if (hit == null) {
      setState(() => _status = '该位置没有命中可见模型三角面');
      return;
    }

    setState(() => _measurementPoints.add(hit));
    final requiredPoints = switch (_measurementMode) {
      CadMeasurementMode.distance => 2,
      CadMeasurementMode.angle || CadMeasurementMode.radius => 3,
      CadMeasurementMode.none => 0,
    };
    if (_measurementPoints.length < requiredPoints) {
      setState(() {
        _status = '已选 ${_measurementPoints.length} / $requiredPoints 点 · ${hit.stableId}';
      });
      return;
    }

    final points = List<CadPickPoint>.of(_measurementPoints);
    final text = switch (_measurementMode) {
      CadMeasurementMode.distance =>
        '距离 = ${_measurementNumber(CadMeasurement.distance(points[0], points[1]))} 模型单位',
      CadMeasurementMode.angle => (() {
          final value = CadMeasurement.angle(points[0], points[1], points[2]);
          return value == null ? '角度无法计算：选点重合或退化' : '角度 ∠ABC = ${_measurementNumber(value)}°';
        })(),
      CadMeasurementMode.radius => (() {
          final value = CadMeasurement.radius(points[0], points[1], points[2]);
          return value == null ? '半径无法计算：三个点共线或重合' : '三点圆半径 R = ${_measurementNumber(value)} 模型单位';
        })(),
      CadMeasurementMode.none => '',
    };
    setState(() {
      _measurementResult = text;
      _status = text;
      _measurementPoints.clear();
    });
  }

  Future<void> _showSectionControls() async {
    if (_loadedPath == null || _importing) return;
    final request = await showModalBottomSheet<_SectionRequest>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _SectionSheet(
        enabled: _sectionEnabled,
        axis: _sectionAxis,
        offset: _sectionOffset,
      ),
    );
    if (request == null || !mounted) return;

    setState(() => _status = request.enabled ? '正在生成剖切显示…' : '正在关闭剖切…');
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
      if (!ok) throw const PlatformException(code: 'SECTION_FAILED', message: 'Native section plane rejected the request.');
      final handle = await CadEngine.instance.getCurrentDocumentHandle();
      NativeDocumentSummary? summary;
      List<CadObjectPresentation> presentation = const [];
      if (handle != null) {
        summary = await CadEngine.instance.getDocumentSummary(handle);
        presentation = await CadEngine.instance.getObjectPresentation(handle: handle);
      }
      if (!mounted) return;
      setState(() {
        _sectionEnabled = request.enabled;
        _sectionAxis = request.axis;
        _sectionOffset = request.offset;
        _documentHandle = handle;
        if (summary != null) {
          _triangleCount = summary.triangleCount;
          _rootObjectCount = summary.rootObjectCount;
          _hierarchyNodeCount = summary.hierarchyNodeCount;
        }
        _objectPresentation = presentation;
        _status = request.enabled
            ? '剖切已启用 · ${request.axis.toUpperCase()} ≥ ${_measurementNumber(request.offset)}'
            : '剖切已关闭';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '剖切失败：${error.message ?? error.code}');
    }
  }

  @override
  void dispose() {
    _importProgressTimer?.cancel();
    unawaited(CadEngine.instance.disposeViewport());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _analyzing || _splitting || _exporting || _importing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('模型查看'),
        actions: [
          if (_importing)
            IconButton(
              tooltip: '取消当前导入',
              onPressed: () => unawaited(_cancelImport()),
              icon: const Icon(Icons.cancel_outlined),
            ),
          PopupMenuButton<CadMeasurementMode>(
            tooltip: '工程测量',
            enabled: _loadedPath != null && !busy,
            initialValue: _measurementMode == CadMeasurementMode.none ? null : _measurementMode,
            onSelected: _setMeasurementMode,
            icon: Icon(
              Icons.straighten,
              color: _measurementMode == CadMeasurementMode.none
                  ? null
                  : Theme.of(context).colorScheme.primary,
            ),
            itemBuilder: (context) => const [
              PopupMenuItem(value: CadMeasurementMode.distance, child: Text('两点距离')),
              PopupMenuItem(value: CadMeasurementMode.angle, child: Text('三点角度')),
              PopupMenuItem(value: CadMeasurementMode.radius, child: Text('三点半径')),
              PopupMenuDivider(),
              PopupMenuItem(value: CadMeasurementMode.none, child: Text('退出测量')),
            ],
          ),
          IconButton(
            tooltip: _sectionEnabled ? '调整 / 关闭剖切' : '剖切平面',
            onPressed: _loadedPath == null || busy ? null : () => unawaited(_showSectionControls()),
            icon: Icon(
              Icons.content_cut,
              color: _sectionEnabled ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          if (_objectPresentation.isNotEmpty)
            IconButton(
              tooltip: '对象树 / 可见性',
              onPressed: busy ? null : () => unawaited(_showObjectPresentation()),
              icon: const Icon(Icons.layers_outlined),
            ),
          IconButton(
            tooltip: _exactGeometry ? '精确 CAD 信息' : '检查模型',
            onPressed: _loadedPath == null || busy ? null : () => unawaited(_inspect()),
            icon: _analyzing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_exactGeometry ? Icons.account_tree_outlined : Icons.fact_check_outlined),
          ),
          IconButton(
            tooltip: '适配视图',
            onPressed: _textureId == null ? null : _fitAll,
            icon: const Icon(Icons.center_focus_strong),
          ),
          PopupMenuButton<String>(
            tooltip: '导出 / 转换',
            enabled: _loadedPath != null && !busy,
            onSelected: (value) => unawaited(_export(value)),
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'obj',
                child: Row(
                  children: [
                    const Expanded(child: Text('导出 OBJ')),
                    if (_hasUv) const Text('保留 UV', style: TextStyle(fontSize: 12)),
                    if (_exactGeometry) const Icon(Icons.warning_amber_rounded, size: 18),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'stl',
                child: Row(
                  children: [
                    const Expanded(child: Text('导出 STL')),
                    if (_hasUv || _exactGeometry) const Icon(Icons.warning_amber_rounded, size: 18),
                  ],
                ),
              ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: '显示模式',
            initialValue: _displayMode,
            onSelected: _setDisplayMode,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'shaded', child: Text('实体着色')),
              PopupMenuItem(value: 'shaded_edges', child: Text('着色 + 边线')),
              PopupMenuItem(value: 'wireframe', child: Text('线框')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  unawaited(_ensureSurface(size));
                });
                final measuring = _measurementMode != CadMeasurementMode.none;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: measuring ? null : _onScaleStart,
                  onScaleUpdate: measuring ? null : _onScaleUpdate,
                  onTapUp: measuring ? _onMeasureTap : null,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerLowest),
                      if (_textureId != null) Texture(textureId: _textureId!),
                      if (measuring)
                        Positioned(
                          left: 12,
                          top: 12,
                          child: Chip(
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
                        ),
                      if (_sectionEnabled)
                        Positioned(
                          right: 12,
                          top: 12,
                          child: Chip(
                            avatar: const Icon(Icons.content_cut, size: 18),
                            label: Text(
                              '${_sectionAxis.toUpperCase()} ≥ ${_measurementNumber(_sectionOffset)}',
                            ),
                          ),
                        ),
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: _ProjectionControl(
                          selected: _projection,
                          onChanged: _setProjection,
                        ),
                      ),
                      if (_loadedPath != null)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: _ModelCapabilityBadge(
                            format: _loadedFormat,
                            triangleCount: _triangleCount,
                            hasUv: _hasUv,
                            hasNormals: _hasNormals,
                            exactGeometry: _exactGeometry,
                            rootObjectCount: _rootObjectCount,
                            hierarchyNodeCount: _hierarchyNodeCount,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  if (_importing)
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.info_outline, size: 18),
                    ),
                  Expanded(child: Text(_status, maxLines: 2, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        ],
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
  late final TextEditingController offsetController =
      TextEditingController(text: widget.offset.toString());

  @override
  void dispose() {
    offsetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
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
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用几何剖切'),
              subtitle: const Text('仅裁剪显示网格；精确 B-Rep / 原文件不会被修改'),
              value: enabled,
              onChanged: (value) => setState(() => enabled = value),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'x', label: Text('X')),
                ButtonSegment(value: 'y', label: Text('Y')),
                ButtonSegment(value: 'z', label: Text('Z')),
              ],
              selected: <String>{axis},
              onSelectionChanged: enabled
                  ? (selection) => setState(() => axis = selection.first)
                  : null,
              showSelectedIcon: false,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: offsetController,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: '平面坐标 / Offset',
                helperText: '保留法向量正侧，例如 Z ≥ 0',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                final offset = double.tryParse(offsetController.text.trim());
                if (enabled && offset == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入有效的剖切坐标')),
                  );
                  return;
                }
                Navigator.of(context).pop(
                  _SectionRequest(enabled: enabled, axis: axis, offset: offset ?? 0),
                );
              },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectionSheet extends StatelessWidget {
  const _InspectionSheet({required this.inspection, this.onSplit});

  final MeshInspection inspection;
  final ValueChanged<String>? onSplit;

  String _number(num value) {
    final absolute = value.abs();
    if (absolute >= 1000000 || (absolute > 0 && absolute < 0.001)) {
      return value.toStringAsExponential(3);
    }
    if (absolute >= 1000) return value.toStringAsFixed(1);
    if (absolute >= 10) return value.toStringAsFixed(2);
    return value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final size = inspection.size.length == 3
        ? '${_number(inspection.size[0])} × ${_number(inspection.size[1])} × ${_number(inspection.size[2])}'
        : '—';
    final unit = inspection.unitKnown ? inspection.unitLabel : '模型单位';
    final health = inspection.closed && inspection.nonManifoldEdgeCount == 0
        ? '闭合 / Manifold'
        : '需要检查';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  inspection.closed ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('模型检查', style: Theme.of(context).textTheme.titleLarge),
                      Text(health, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _InspectionRow(label: '外包尺寸', value: '$size $unit'),
            _InspectionRow(label: '三角面', value: '${inspection.triangleCount}'),
            _InspectionRow(label: '唯一顶点', value: '${inspection.uniqueVertexCount}'),
            _InspectionRow(label: '连通部件', value: '${inspection.connectedComponentCount}'),
            const Divider(height: 28),
            _InspectionRow(
              label: '开边',
              value: '${inspection.openEdgeCount}',
              warning: inspection.openEdgeCount > 0,
            ),
            _InspectionRow(
              label: '非流形边',
              value: '${inspection.nonManifoldEdgeCount}',
              warning: inspection.nonManifoldEdgeCount > 0,
            ),
            _InspectionRow(
              label: '退化三角面',
              value: '${inspection.degenerateTriangleCount}',
              warning: inspection.degenerateTriangleCount > 0,
            ),
            const Divider(height: 28),
            _InspectionRow(label: '表面积', value: '${_number(inspection.surfaceArea)} $unit²'),
            _InspectionRow(
              label: '闭合体积',
              value: inspection.closed ? '${_number(inspection.enclosedVolume)} $unit³' : '—（模型未闭合）',
            ),
            if (!inspection.unitKnown) ...[
              const SizedBox(height: 16),
              Text(
                'STL/OBJ 通常不携带可靠的长度单位。这里保留原文件坐标尺度，不擅自解释为 mm、cm 或 inch。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (onSplit != null) ...[
              const SizedBox(height: 22),
              Text(
                '检测到 ${inspection.connectedComponentCount} 个独立部件',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '按连通关系拆分后，每个部件会作为独立文件写入你选择的文件夹。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onSplit!('obj'),
                      icon: const Icon(Icons.call_split),
                      label: const Text('拆为 OBJ'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => onSplit!('stl'),
                      icon: const Icon(Icons.call_split),
                      label: const Text('拆为 STL'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InspectionRow extends StatelessWidget {
  const _InspectionRow({required this.label, required this.value, this.warning = false});

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: warning ? theme.colorScheme.error : null,
                fontWeight: warning ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelCapabilityBadge extends StatelessWidget {
  const _ModelCapabilityBadge({
    required this.format,
    required this.triangleCount,
    required this.hasUv,
    required this.hasNormals,
    required this.exactGeometry,
    required this.rootObjectCount,
    required this.hierarchyNodeCount,
  });

  final String format;
  final int triangleCount;
  final bool hasUv;
  final bool hasNormals;
  final bool exactGeometry;
  final int rootObjectCount;
  final int hierarchyNodeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          '${format.toUpperCase()} · $triangleCount △'
          '${exactGeometry ? ' · B-Rep · $rootObjectCount/$hierarchyNodeCount' : ''}'
          '${hasUv ? ' · UV' : ''}'
          '${hasNormals ? ' · N' : ''}',
          style: theme.textTheme.labelMedium,
        ),
      ),
    );
  }
}

class _ProjectionControl extends StatelessWidget {
  const _ProjectionControl({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'perspective', icon: Icon(Icons.photo_camera_outlined), label: Text('透视')),
        ButtonSegment(value: 'orthographic', icon: Icon(Icons.crop_square), label: Text('正交')),
      ],
      selected: {selected},
      onSelectionChanged: (value) => onChanged(value.first),
      showSelectedIcon: false,
    );
  }
}
