import 'dart:async';

import 'package:cad_engine/cad_engine.dart';
import 'package:flutter/material.dart';

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
      _status = result.ok ? '已打开：${result.displayName}' : '打开失败：${result.message}';
    });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('模型查看'),
        actions: [
          IconButton(
            tooltip: '适配视图',
            onPressed: () => CadEngine.instance.fitAll(),
            icon: const Icon(Icons.center_focus_strong),
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
