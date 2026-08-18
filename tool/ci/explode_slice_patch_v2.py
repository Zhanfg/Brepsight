from pathlib import Path
import runpy


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one anchor in {path}, found {count}: {old[:160]!r}")
    p.write_text(text.replace(old, new, 1))


# The product test was dart-formatted after the previous selection slice. The
# original explode patch intentionally uses an exact anchor, so normalize only
# this switch arm to its pre-format indentation before running that reviewed
# patch. Dart formatting later restores canonical indentation.
test_path = "test/viewer_workspace_test.dart"
replace_once(
    test_path,
    """            case 'resizeViewport':
            case 'disposeViewport':
            case 'setProjection':
            case 'setDisplayMode':
            case 'fitAll':
            case 'orbit':
            case 'pan':
            case 'zoom':
              return null;
""",
    """        case 'resizeViewport':
        case 'disposeViewport':
        case 'setProjection':
        case 'setDisplayMode':
        case 'fitAll':
        case 'orbit':
        case 'pan':
        case 'zoom':
          return null;
""",
)

# Apply the original reviewed renderer/native/UI explode patch.
runpy.run_path("../helper/tool/ci/explode_slice_patch.py", run_name="__main__")

viewer = "lib/src/viewer/engineering_workspace_page.dart"

# CPU picking still operates on the un-exploded mesh. Until the explode
# transform is incorporated into the native picker, do not expose controls that
# would let users pick a visually displaced part and receive a hit at its old
# location.
replace_once(
    viewer,
    """  Future<void> _showSelectionTools() async {
    if (!_hasModel || _busy) return;
""",
    """  Future<void> _showSelectionTools() async {
    if (!_hasModel || _busy || _exploded) return;
""",
)
replace_once(
    viewer,
    """  Future<void> _showMeasurementTools() async {
    if (!_hasModel || _busy) return;
""",
    """  Future<void> _showMeasurementTools() async {
    if (!_hasModel || _busy || _exploded) return;
""",
)
replace_once(
    viewer,
    """  Future<void> _showEditor() async {
    if (!_hasModel || _busy || _sectionEnabled) return;
""",
    """  Future<void> _showEditor() async {
    if (!_hasModel || _busy || _sectionEnabled || _exploded) return;
""",
)

# Entering exploded view clears stale pick/measurement state before any visual
# displacement is applied.
replace_once(
    viewer,
    """  Future<void> _showExplodeControls() async {
    if (!_canExplode || _busy || _editActive || _sectionEnabled) return;
    var factor = _explodeFactor;
""",
    """  Future<void> _showExplodeControls() async {
    if (!_canExplode || _busy || _editActive || _sectionEnabled) return;
    setState(() {
      _clearMeasure(leaveMode: true);
      _clearSelection(leaveMode: true);
    });
    var factor = _explodeFactor;
""",
)

# Section-plane changes rebuild the display mesh and native loadModel resets the
# explode factor. Reapply the current display-only factor after that rebuild so
# the UI chip and renderer cannot diverge.
replace_once(
    viewer,
    """      final handle = await CadEngine.instance.getCurrentDocumentHandle();
      final summary = handle == null
          ? null
          : await CadEngine.instance.getDocumentSummary(handle);
      if (!mounted) return;
      setState(() {
        _sectionEnabled = request.enabled;
""",
    """      final handle = await CadEngine.instance.getCurrentDocumentHandle();
      final summary = handle == null
          ? null
          : await CadEngine.instance.getDocumentSummary(handle);
      if (_explodeFactor > 0.001) {
        await CadEngineV01Tools.instance.setExplodeFactor(_explodeFactor);
      }
      if (!mounted) return;
      setState(() {
        _sectionEnabled = request.enabled;
""",
)

# Make the dock state honest: selection, measurement and mesh editing are
# visibly disabled while parts are displaced; section remains available.
replace_once(
    viewer,
    """              busy: _busy,
              selectionActive: _selectionActive,
              measurementActive: _measuring,
""",
    """              busy: _busy,
              exploded: _exploded,
              selectionActive: _selectionActive,
              measurementActive: _measuring,
""",
)
replace_once(
    viewer,
    """    required this.busy,
    required this.selectionActive,
""",
    """    required this.busy,
    required this.exploded,
    required this.selectionActive,
""",
)
replace_once(
    viewer,
    """  final bool busy;
  final bool selectionActive;
""",
    """  final bool busy;
  final bool exploded;
  final bool selectionActive;
""",
)
replace_once(
    viewer,
    """                active: selectionActive,
                enabled: !busy,
""",
    """                active: selectionActive,
                enabled: !busy && !exploded,
""",
)
replace_once(
    viewer,
    """                active: measurementActive,
                enabled: !busy,
""",
    """                active: measurementActive,
                enabled: !busy && !exploded,
""",
)
replace_once(
    viewer,
    """                active: editActive,
                enabled: !busy && !sectionActive,
""",
    """                active: editActive,
                enabled: !busy && !sectionActive && !exploded,
""",
)
