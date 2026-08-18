from pathlib import Path
import runpy


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one anchor in {path}, found {count}: {old[:180]!r}")
    p.write_text(text.replace(old, new, 1))


# Apply the reviewed first-pass integration, then harden the load path. Keeping
# this as a wrapper preserves the already-audited UI/annotation patch while
# making the persistence layer supplementary rather than import-blocking.
runpy.run_path("../helper/tool/ci/local_annotations_patch.py", run_name="__main__")

path = "lib/src/viewer/engineering_workspace_page.dart"

replace_once(
    path,
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
""",
    """      if (!mounted) return;
""",
)
replace_once(
    path,
    """        _objects = objects;
        _annotationModelKey = annotationModelKey;
        _annotations = annotations;
        _editState = editState;
""",
    """        _objects = objects;
        _annotationModelKey = null;
        _annotations = const [];
        _editState = editState;
""",
)
replace_once(
    path,
    """      });
      _fitAll();
    } on PlatformException catch (error) {
""",
    """      });
      _fitAll();
      unawaited(_loadAnnotationsForModel(path, result));
    } on PlatformException catch (error) {
""",
)
replace_once(
    path,
    """  Future<String?> _ensureAnnotationModelKey() async {
""",
    """  Future<void> _loadAnnotationsForModel(
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
""",
)
