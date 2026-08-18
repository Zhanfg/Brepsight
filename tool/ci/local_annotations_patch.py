from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one anchor in {path}, found {count}: {old[:180]!r}")
    p.write_text(text.replace(old, new, 1))


path = "lib/src/viewer/engineering_workspace_page.dart"

replace_once(
    path,
    """import 'dart:async';

import 'package:cad_engine/cad_engine.dart';
""",
    """import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cad_engine/cad_engine.dart';
""",
)
replace_once(
    path,
    """import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mesh_edit_sheet.dart';
""",
    """import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'local_annotation_sheet.dart';
import 'local_annotations.dart';
import 'mesh_edit_sheet.dart';
""",
)
replace_once(
    path,
    """  List<CadObjectPresentation> _objects = const [];
  MeshEditState? _editState;
""",
    """  List<CadObjectPresentation> _objects = const [];
  final GlobalKey _viewportCaptureKey = GlobalKey();
  List<LocalModelAnnotation> _annotations = const [];
  String? _annotationModelKey;
  bool _annotationBusy = false;
  MeshEditState? _editState;
""",
)
replace_once(
    path,
    """      _splitting ||
      _inspecting ||
      (_editState?.busy ?? false);
""",
    """      _splitting ||
      _inspecting ||
      _annotationBusy ||
      (_editState?.busy ?? false);
""",
)

# Load annotations only after the new model is known-good. A failed import must
# retain the previous model's review state alongside the previous visible mesh.
replace_once(
    path,
    """      if (!mounted) return;
      setState(() {
        _loadedPath = path;
""",
    """      String? annotationModelKey;
      List<LocalModelAnnotation> annotations = const [];
      try {
        annotationModelKey = await ModelAnnotationIdentity.forModel(
          sourcePath: path,
          formatId: result.formatId,
          triangleCount: result.triangleCount,
          rootObjectCount: result.rootObjectCount,
          hierarchyNodeCount: result.hierarchyNodeCount,
        );
        annotations = await LocalAnnotationStore.instance.load(annotationModelKey);
      } catch (_) {
        // Annotation persistence is supplementary. Importing and viewing a model
        // must remain usable even if local preferences are temporarily unavailable.
        annotationModelKey = null;
        annotations = const [];
      }

      if (!mounted) return;
      setState(() {
        _loadedPath = path;
""",
)
replace_once(
    path,
    """        _objects = objects;
        _editState = editState;
""",
    """        _objects = objects;
        _annotationModelKey = annotationModelKey;
        _annotations = annotations;
        _editState = editState;
""",
)

# Local annotation lifecycle: model-scoped identity, optional geometry anchor,
# bounded local PNG thumbnail, delete, and anchor re-selection.
replace_once(
    path,
    """  Future<void> _showExplodeControls() async {
""",
    """  Future<String?> _ensureAnnotationModelKey() async {
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
      CadSelectionFilter.face || CadSelectionFilter.body => CadSnapKind.faceCenter,
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
""",
)

# Surface the persisted local workflow alongside the other document operations.
replace_once(
    path,
    """            if (_canExplode)
              ListTile(
                leading: const Icon(Icons.open_with),
""",
    """            ListTile(
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
""",
)
replace_once(
    path,
    """      case 'explode':
        await _showExplodeControls();
        break;
      case 'inspect':
""",
    """      case 'annotations':
        await _showAnnotations();
        break;
      case 'explode':
        await _showExplodeControls();
        break;
      case 'inspect':
""",
)

# Capture only the canvas/texture layer: annotation thumbnails should not include
# bottom sheets, status chips, or other transient UI chrome.
replace_once(
    path,
    """              children: [
                ColoredBox(
                  color: dark
                      ? const Color(0xFF151B22)
                      : const Color(0xFFE7EBEF),
                ),
                _texture(),
                if (!_hasModel && !_importing) const _EmptyModelState(),
                if (_precisionPick && _measuring) _reticle(theme),
""",
    """              children: [
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
""",
)
replace_once(
    path,
    """                    _editActive ||
                    _sectionEnabled ||
                    _exploded)
""",
    """                    _editActive ||
                    _sectionEnabled ||
                    _exploded ||
                    _annotations.isNotEmpty)
""",
)
replace_once(
    path,
    """                            if (_exploded)
                              Chip(
""",
    """                            if (_annotations.isNotEmpty)
                              ActionChip(
                                avatar: const Icon(Icons.rate_review_outlined, size: 18),
                                label: Text('批注 ${_annotations.length}'),
                                onPressed: () => unawaited(_showAnnotations()),
                              ),
                            if (_exploded)
                              Chip(
""",
)

# Focused narrow-screen regression: the local-only review entry must be real and
# reach the composer without cloud/account affordances.
test_path = "test/viewer_workspace_test.dart"
replace_once(
    test_path,
    """    expect(find.text('拆分连通部件'), findsOneWidget);
    expect(find.text('爆炸视图'), findsOneWidget);
    expect(find.textContaining('OBJ'), findsWidgets);
""",
    """    expect(find.text('拆分连通部件'), findsOneWidget);
    expect(find.text('爆炸视图'), findsOneWidget);
    expect(find.text('本地批注'), findsOneWidget);
    expect(find.textContaining('仅保存在此设备'), findsOneWidget);
    expect(find.textContaining('OBJ'), findsWidgets);
""",
)
replace_once(
    test_path,
    """  testWidgets(
    'exploded assembly view drives native per-object display offsets',
""",
    """  testWidgets('local annotations reach an offline text composer on narrow screens', (
    tester,
  ) async {
    await pumpWorkspace(tester, Brightness.light);
    await tester.tap(find.byTooltip('工程操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地批注'));
    await tester.pumpAndSettle();

    expect(find.text('当前模型还没有本地批注'), findsOneWidget);
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(find.text('新建本地批注'), findsOneWidget);
    expect(find.text('批注内容'), findsOneWidget);
    expect(find.text('附加当前视图截图'), findsOneWidget);
    expect(find.textContaining('仅存储在本机批注数据中'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'exploded assembly view drives native per-object display offsets',
""",
)
