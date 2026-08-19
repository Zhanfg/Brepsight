from pathlib import Path

viewer_path = Path('lib/src/viewer/engineering_workspace_page.dart')
test_path = Path('test/viewer_workspace_test.dart')
workflow_path = Path('.github/workflows/mesh-edit-core.yml')
script_path = Path('tools/rc358_runtime_hotfix.py')

viewer = viewer_path.read_text()

field_anchor = "  bool _precisionPick = false;\n\n  bool _selectionActive = false;"
field_replacement = "  bool _precisionPick = false;\n  bool _runtimeReady = false;\n  String? _runtimeFault;\n\n  bool _selectionActive = false;"
assert viewer.count(field_anchor) == 1
viewer = viewer.replace(field_anchor, field_replacement)

start_marker = "      List<CadObjectPresentation> objects = const [];"
end_marker = "      unawaited(_loadAnnotationsForModel(path, result));"
start = viewer.index(start_marker)
end = viewer.index(end_marker, start) + len(end_marker)
replacement = r'''      // Commit the successfully loaded model to UI state before optional metadata
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
      unawaited(_loadAnnotationsForModel(path, result));'''
viewer = viewer[:start] + replacement + viewer[end:]

more_anchor = "            onPressed: !_hasModel || _busy\n                ? null\n                : () => unawaited(_showMore()),"
more_replacement = "            onPressed: !_hasModel || _busy || !_runtimeReady\n                ? null\n                : () => unawaited(_showMore()),"
assert viewer.count(more_anchor) == 1
viewer = viewer.replace(more_anchor, more_replacement)

fault_anchor = "                if (_precisionPick && _measuring) _reticle(theme),\n                if (_measuring ||"
fault_replacement = r'''                if (_precisionPick && _measuring) _reticle(theme),
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
                if (_measuring ||'''
assert viewer.count(fault_anchor) == 1
viewer = viewer.replace(fault_anchor, fault_replacement)

tool_call_anchor = "              busy: _busy,\n              exploded: _exploded,"
tool_call_replacement = "              busy: _busy,\n              runtimeReady: _runtimeReady,\n              exploded: _exploded,"
assert viewer.count(tool_call_anchor) == 1
viewer = viewer.replace(tool_call_anchor, tool_call_replacement)

ctor_anchor = "    required this.busy,\n    required this.exploded,"
ctor_replacement = "    required this.busy,\n    required this.runtimeReady,\n    required this.exploded,"
assert viewer.count(ctor_anchor) == 1
viewer = viewer.replace(ctor_anchor, ctor_replacement)

field2_anchor = "  final bool busy;\n  final bool exploded;"
field2_replacement = "  final bool busy;\n  final bool runtimeReady;\n  final bool exploded;"
assert viewer.count(field2_anchor) == 1
viewer = viewer.replace(field2_anchor, field2_replacement)

viewer = viewer.replace("enabled: !busy && !exploded,", "enabled: runtimeReady && !busy && !exploded,")
viewer = viewer.replace("enabled: !busy && !editActive,", "enabled: runtimeReady && !busy && !editActive,")
viewer = viewer.replace("enabled: !busy && !sectionActive && !exploded,", "enabled: runtimeReady && !busy && !sectionActive && !exploded,")

viewer_path.write_text(viewer)

# Regression: facade handshake is now part of normal model load, and an
# object-presentation failure must not disable the engineering tool dock.
test = test_path.read_text()
var_anchor = "  final displayCommands = <String>[];\n\n  setUp(() {\n    displayCommands.clear();"
var_replacement = "  final displayCommands = <String>[];\n  var failObjectPresentation = false;\n\n  setUp(() {\n    displayCommands.clear();\n    failObjectPresentation = false;"
assert test.count(var_anchor) == 1
test = test.replace(var_anchor, var_replacement)

progress_anchor = "            case 'loadModel':\n              return <Object?, Object?>{"
progress_replacement = "            case 'getImportProgress':\n              return <Object?, Object?>{\n                'active': false,\n                'taskId': 0,\n                'path': '',\n                'stage': 'idle',\n                'progress': 100,\n                'cancelRequested': false,\n              };\n            case 'loadModel':\n              return <Object?, Object?>{"
assert test.count(progress_anchor) == 1
test = test.replace(progress_anchor, progress_replacement)

object_anchor = "            case 'getObjectPresentation':\n              return '[{\"id\":\"body-0\""
assert test.count(object_anchor) == 1
test = test.replace(
    "            case 'getObjectPresentation':\n              return '[{\"id\":\"body-0\",\"label\":\"Chest\",\"type\":\"mesh\",\"parentId\":\"\",\"visible\":true,\"effectiveVisible\":true,\"hasGeometry\":true,\"hasBaseColor\":true,\"baseColor\":[0.7,0.76,0.84]},{\"id\":\"body-1\",\"label\":\"Plate\",\"type\":\"mesh\",\"parentId\":\"\",\"visible\":true,\"effectiveVisible\":true,\"hasGeometry\":true,\"hasBaseColor\":false,\"baseColor\":[0.7,0.76,0.84]}]';",
    "            case 'getObjectPresentation':\n              if (failObjectPresentation) {\n                throw PlatformException(\n                  code: 'PRESENTATION_BROKEN',\n                  message: 'synthetic object metadata failure',\n                );\n              }\n              return '[{\"id\":\"body-0\",\"label\":\"Chest\",\"type\":\"mesh\",\"parentId\":\"\",\"visible\":true,\"effectiveVisible\":true,\"hasGeometry\":true,\"hasBaseColor\":true,\"baseColor\":[0.7,0.76,0.84]},{\"id\":\"body-1\",\"label\":\"Plate\",\"type\":\"mesh\",\"parentId\":\"\",\"visible\":true,\"effectiveVisible\":true,\"hasGeometry\":true,\"hasBaseColor\":false,\"baseColor\":[0.7,0.76,0.84]}]';",
)

insert_before = "  testWidgets(\n    'STL opens as a model-first narrow-screen engineering workspace',"
assert test.count(insert_before) == 1
new_test = r'''  testWidgets(
    'object presentation failure does not invalidate runtime handle or tools',
    (tester) async {
      failObjectPresentation = true;
      await pumpWorkspace(tester, Brightness.light);

      expect(find.textContaining('工程工具已就绪'), findsOneWidget);
      await tester.tap(find.text('测量'));
      await tester.pumpAndSettle();
      expect(find.text('点坐标'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

'''
test = test.replace(insert_before, new_test + insert_before)
test_path.write_text(test)

# Restore the normal workflow and remove this one-shot patch script so the
# product head contains only the runtime fix and regression.
workflow_path.write_text("""name: Mesh Edit Core

on:
  workflow_dispatch:
  pull_request:
    paths:
      - 'packages/cad_engine/android/src/main/cpp/mesh_transform.*'
      - 'packages/cad_engine/android/src/main/cpp/mesh_writer.*'
      - 'packages/cad_engine/android/src/test/cpp/mesh_transform_test.cpp'
      - '.github/workflows/mesh-edit-core.yml'
  push:
    paths:
      - 'packages/cad_engine/android/src/main/cpp/mesh_transform.*'
      - 'packages/cad_engine/android/src/main/cpp/mesh_writer.*'
      - 'packages/cad_engine/android/src/test/cpp/mesh_transform_test.cpp'
      - '.github/workflows/mesh-edit-core.yml'

permissions:
  contents: read

jobs:
  transform-contract:
    name: Transform and export working copy
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - name: Checkout BrepSight
        uses: actions/checkout@v6
      - name: Build and run mesh edit/export regression
        shell: bash
        run: |
          set -euo pipefail
          CPP_DIR='packages/cad_engine/android/src/main/cpp'
          TEST_DIR='packages/cad_engine/android/src/test/cpp'
          g++ -std=c++20 -Wall -Wextra -Werror \\
            -I\"${CPP_DIR}\" \\
            \"${CPP_DIR}/mesh_transform.cpp\" \\
            \"${CPP_DIR}/mesh_writer.cpp\" \\
            \"${TEST_DIR}/mesh_transform_test.cpp\" \\
            -o /tmp/brepsight_mesh_transform_test
          /tmp/brepsight_mesh_transform_test
""")
script_path.unlink()
