from pathlib import Path
import runpy


runpy.run_path("../helper/tool/ci/local_annotations_patch_v2.py", run_name="__main__")

path = Path("lib/src/viewer/engineering_workspace_page.dart")
text = path.read_text()
start = text.find("  Future<void> _showMore() async {\n")
end = text.find("  Widget _texture() {\n", start)
if start < 0 or end < 0:
    raise SystemExit("engineering operations sheet boundaries not found")
segment = text[start:end]
old_builder = """      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
"""
new_builder = """      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        child: Padding(
"""
if segment.count(old_builder) != 1:
    raise SystemExit(f"engineering operation builder anchor count={segment.count(old_builder)}")
segment = segment.replace(old_builder, new_builder, 1)
old_close = """      ),
    );
    if (!mounted || value == null) return;
"""
new_close = """      ),
      ),
    );
    if (!mounted || value == null) return;
"""
if segment.count(old_close) != 1:
    raise SystemExit(f"engineering operation close anchor count={segment.count(old_close)}")
segment = segment.replace(old_close, new_close, 1)
path.write_text(text[:start] + segment + text[end:])
