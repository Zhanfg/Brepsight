import 'dart:async';

import 'package:cad_engine/cad_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key, required this.modelPath});

  final String? modelPath;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  int? _textureId;
  Size _surfaceSize = Size.zero;
  String? _loadedPath;
  String _status = '尚未打开模型';
  String _projection = 'perspective';
  String _displayMode = 'shaded_edges';
  String _loadedFormat = 'unknown';
  int _triangleCount = 0;
  bool _hasUv = false;
  bool _hasNormals = false;
  bool _exporting = false;
  bool _analyzing = false;
  bool _splitting = false;
  Offset? _lastFocalPoint;
  double _lastScale = 1;

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

  Future<void> _loadIfNeeded() async {
    final path = widget.modelPath;
    if (path == null || path == _loadedPath || _textureId == null) return;
    if (mounted) setState(() => _status = '正在载入模型…');
    final result = await CadEngine.instance.loadModel(path);
    if (!mounted) return;
    setState(() {
      _loadedPath = result.ok ? path : null;
      if (result.ok) {
        _loadedFormat = result.formatId;
        _triangleCount = result.triangleCount;
        _hasUv = result.hasUv;
        _hasNormals = result.hasNormals;
        final meshInfo = result.triangleCount > 0 ? ' · ${result.triangleCount} 三角面' : '';
        final uvInfo = result.hasUv ? ' · UV' : '';
        _status = '已打开：${result.displayName} · ${result.formatId.toUpperCase()}$meshInfo$uvInfo';
      } else {
        _loadedFormat = 'unknown';
        _triangleCount = 0;
        _hasUv = false;
        _hasNormals = false;
        _status = '打开失败：${result.message}';
      }
    });
  }

  Future<bool> _confirmUvLoss(String action) async {
    if (!_hasUv) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('转换会丢失 UV'),
            content: Text(
              'STL 只保留三角几何和法线；当前模型的 UV，以及依赖 UV 的材质/贴图绑定不会写入 STL。\n\n$action 不会修改原模型。',
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

  Future<void> _inspect() async {
    if (_loadedPath == null || _analyzing || _splitting) return;
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
    if (formatId == 'stl' && !await _confirmUvLoss('拆分出的 STL 部件')) return;

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
    if (formatId == 'stl' && !await _confirmUvLoss('导出')) return;

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

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.localFocalPoint;
    _lastScale = 1;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final last = _lastFocalPoint;
    if (last != null) {
      final delta = details.localFocalPoint - last;
      if (details.pointerCount >= 2) {
        unawaited(CadEngine.instance.pan(delta.dx, delta.dy));
      } else {
        unawaited(CadEngine.instance.orbit(delta.dx, delta.dy));
      }
    }

    if ((details.scale - _lastScale).abs() > 0.003) {
      unawaited(CadEngine.instance.zoom(details.scale / _lastScale));
      _lastScale = details.scale;
    }
    _lastFocalPoint = details.localFocalPoint;
  }

  @override
  void dispose() {
    unawaited(CadEngine.instance.disposeViewport());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _analyzing || _splitting || _exporting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('模型查看'),
        actions: [
          IconButton(
            tooltip: '检查模型',
            onPressed: _loadedPath == null || busy ? null : () => unawaited(_inspect()),
            icon: _analyzing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined),
          ),
          IconButton(
            tooltip: '适配视图',
            onPressed: () => CadEngine.instance.fitAll(),
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
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'stl',
                child: Row(
                  children: [
                    const Expanded(child: Text('导出 STL')),
                    if (_hasUv) const Icon(Icons.warning_amber_rounded, size: 18),
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
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerLowest),
                      if (_textureId != null) Texture(textureId: _textureId!),
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
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
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
  });

  final String format;
  final int triangleCount;
  final bool hasUv;
  final bool hasNormals;

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
