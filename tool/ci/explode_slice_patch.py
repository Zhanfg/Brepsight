from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one anchor in {path}, found {count}: {old[:160]!r}")
    file.write_text(text.replace(old, new, 1))


# Public display control.
path = "packages/cad_engine/lib/src/release/v01_tools.dart"
replace_once(
    path,
    """  Future<void> clearSelectionHighlight() => _channel.invokeMethod<void>(
    'setDisplayMode',
    const <String, Object?>{'mode': 'selection_clear'},
  );

  Future<bool> setSectionPlane({
""",
    """  Future<void> clearSelectionHighlight() => _channel.invokeMethod<void>(
    'setDisplayMode',
    const <String, Object?>{'mode': 'selection_clear'},
  );

  Future<void> setExplodeFactor(double factor) {
    final safe = factor.clamp(0.0, 1.0).toDouble();
    return _channel.invokeMethod<void>('setDisplayMode', <String, Object?>{
      'mode': 'explode:${safe.toStringAsFixed(4)}',
    });
  }

  Future<bool> setSectionPlane({
""",
)

# Renderer: precompute object explode directions and apply them per draw range.
path = "packages/cad_engine/android/src/main/cpp/cad_engine_jni.cpp"
replace_once(
    path,
    """  int selectionKind = 0;
  long long selectionTriangle = -1;
  int selectionFeature = -1;
};
""",
    """  int selectionKind = 0;
  long long selectionTriangle = -1;
  int selectionFeature = -1;
  float explodeFactor = 0.0f;
};
""",
)
replace_once(
    path,
    """uniform mat4 uMvp;
uniform mat3 uNormalMatrix;
uniform int uSelectionKind;
out vec3 vNormal;
out vec3 vBarycentric;
void main() {
  gl_Position = uMvp * vec4(aPosition, 1.0);
""",
    """uniform mat4 uMvp;
uniform mat3 uNormalMatrix;
uniform int uSelectionKind;
uniform vec3 uObjectOffset;
out vec3 vNormal;
out vec3 vBarycentric;
void main() {
  gl_Position = uMvp * vec4(aPosition + uObjectOffset, 1.0);
""",
)
replace_once(
    path,
    """void drawUploadedMesh(
    GLuint program,
    const std::vector<MeshDrawRange>& drawRanges,
    GLsizei uploadedVertexCount) {
""",
    """std::vector<Vec3> buildExplodeDirections(
    const MeshData& mesh,
    const std::vector<MeshDrawRange>& drawRanges) {
  std::vector<Vec3> directions;
  directions.reserve(drawRanges.size());
  const Vec3 modelCenter = mesh.bounds.center();
  const std::size_t vertexCount = mesh.vertices.size();
  const float count = static_cast<float>(std::max<std::size_t>(drawRanges.size(), 1));

  for (std::size_t index = 0; index < drawRanges.size(); ++index) {
    const auto& range = drawRanges[index];
    Bounds3 localBounds;
    const std::size_t first = std::min(range.firstVertex, vertexCount);
    const std::size_t end = std::min(first + range.vertexCount, vertexCount);
    for (std::size_t vertex = first; vertex < end; ++vertex) {
      localBounds.include(mesh.vertices[vertex].position);
    }

    Vec3 delta{};
    if (localBounds.valid) {
      const Vec3 center = localBounds.center();
      delta = {center.x - modelCenter.x, center.y - modelCenter.y, center.z - modelCenter.z};
    }
    float length = std::sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z);
    if (length <= 1.0e-6f) {
      const float angle = 2.0f * kPi * static_cast<float>(index) / count;
      delta = {std::cos(angle), std::sin(angle), (index % 2 == 0) ? 0.25f : -0.25f};
      length = std::sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z);
    }
    const float inverse = length > 1.0e-6f ? 1.0f / length : 0.0f;
    directions.push_back({delta.x * inverse, delta.y * inverse, delta.z * inverse});
  }
  return directions;
}

Vec3 explodeOffset(
    const std::vector<Vec3>& directions,
    std::size_t rangeIndex,
    float distance) {
  if (rangeIndex >= directions.size() || distance <= 0.0f) return {};
  const Vec3 direction = directions[rangeIndex];
  return {direction.x * distance, direction.y * distance, direction.z * distance};
}

void drawUploadedMesh(
    GLuint program,
    const std::vector<MeshDrawRange>& drawRanges,
    const std::vector<Vec3>& explodeDirections,
    GLsizei uploadedVertexCount,
    float explodeDistance) {
""",
)
replace_once(
    path,
    """  const GLint colorLocation = glGetUniformLocation(program, "uBaseColor");
  const std::size_t drawableVertices = static_cast<std::size_t>(uploadedVertexCount);

  if (drawRanges.empty()) {
    glUniform3f(colorLocation, kDefaultBaseColor.x, kDefaultBaseColor.y, kDefaultBaseColor.z);
    glDrawArrays(GL_TRIANGLES, 0, uploadedVertexCount);
    return;
  }

  for (const auto& range : drawRanges) {
""",
    """  const GLint colorLocation = glGetUniformLocation(program, "uBaseColor");
  const GLint offsetLocation = glGetUniformLocation(program, "uObjectOffset");
  const std::size_t drawableVertices = static_cast<std::size_t>(uploadedVertexCount);

  if (drawRanges.empty()) {
    glUniform3f(offsetLocation, 0.0f, 0.0f, 0.0f);
    glUniform3f(colorLocation, kDefaultBaseColor.x, kDefaultBaseColor.y, kDefaultBaseColor.z);
    glDrawArrays(GL_TRIANGLES, 0, uploadedVertexCount);
    return;
  }

  for (std::size_t rangeIndex = 0; rangeIndex < drawRanges.size(); ++rangeIndex) {
    const auto& range = drawRanges[rangeIndex];
""",
)
replace_once(
    path,
    """    glUniform3f(colorLocation, color.x, color.y, color.z);
    glDrawArrays(
        GL_TRIANGLES,
        static_cast<GLint>(range.firstVertex),
        static_cast<GLsizei>(count));
  }
}

void drawSelectionOverlay(
    GLuint program,
    const std::vector<MeshDrawRange>& drawRanges,
    GLsizei uploadedVertexCount,
""",
    """    const Vec3 offset = explodeOffset(explodeDirections, rangeIndex, explodeDistance);
    glUniform3f(offsetLocation, offset.x, offset.y, offset.z);
    glUniform3f(colorLocation, color.x, color.y, color.z);
    glDrawArrays(
        GL_TRIANGLES,
        static_cast<GLint>(range.firstVertex),
        static_cast<GLsizei>(count));
  }
  glUniform3f(offsetLocation, 0.0f, 0.0f, 0.0f);
}

void drawSelectionOverlay(
    GLuint program,
    const std::vector<MeshDrawRange>& drawRanges,
    const std::vector<Vec3>& explodeDirections,
    GLsizei uploadedVertexCount,
    float explodeDistance,
""",
)
replace_once(
    path,
    """  const GLint kindLocation = glGetUniformLocation(program, "uSelectionKind");
  const GLint featureLocation = glGetUniformLocation(program, "uSelectionFeature");
  const GLint colorLocation = glGetUniformLocation(program, "uSelectionColor");
  glUniform1i(kindLocation, selectionKind);
""",
    """  const GLint kindLocation = glGetUniformLocation(program, "uSelectionKind");
  const GLint featureLocation = glGetUniformLocation(program, "uSelectionFeature");
  const GLint colorLocation = glGetUniformLocation(program, "uSelectionColor");
  const GLint offsetLocation = glGetUniformLocation(program, "uObjectOffset");

  std::size_t selectedRangeIndex = drawRanges.size();
  for (std::size_t index = 0; index < drawRanges.size(); ++index) {
    const auto& range = drawRanges[index];
    if (first >= range.firstVertex && first < range.firstVertex + range.vertexCount) {
      selectedRangeIndex = index;
      break;
    }
  }
  const Vec3 selectedOffset = explodeOffset(
      explodeDirections,
      selectedRangeIndex,
      explodeDistance);
  glUniform3f(offsetLocation, selectedOffset.x, selectedOffset.y, selectedOffset.z);
  glUniform1i(kindLocation, selectionKind);
""",
)
replace_once(
    path,
    """      const MeshDrawRange* selectedRange = nullptr;
      for (const auto& range : drawRanges) {
        if (!range.visible || range.vertexCount == 0) continue;
        if (first >= range.firstVertex && first < range.firstVertex + range.vertexCount) {
          selectedRange = &range;
          break;
        }
      }
      if (selectedRange == nullptr) {
""",
    """      const MeshDrawRange* selectedRange = selectedRangeIndex < drawRanges.size()
          ? &drawRanges[selectedRangeIndex]
          : nullptr;
      if (selectedRange == nullptr) {
""",
)
replace_once(
    path,
    """        for (const auto& range : drawRanges) {
          if (!range.visible || range.vertexCount == 0 || range.firstVertex >= drawable) continue;
          if (!selectedRange->sourceObject.empty() && range.sourceObject != selectedRange->sourceObject) continue;
          std::size_t count = std::min(range.vertexCount, drawable - range.firstVertex);
""",
    """        for (std::size_t rangeIndex = 0; rangeIndex < drawRanges.size(); ++rangeIndex) {
          const auto& range = drawRanges[rangeIndex];
          if (!range.visible || range.vertexCount == 0 || range.firstVertex >= drawable) continue;
          if (!selectedRange->sourceObject.empty() && range.sourceObject != selectedRange->sourceObject) continue;
          const Vec3 offset = explodeOffset(explodeDirections, rangeIndex, explodeDistance);
          glUniform3f(offsetLocation, offset.x, offset.y, offset.z);
          std::size_t count = std::min(range.vertexCount, drawable - range.firstVertex);
""",
)
replace_once(
    path,
    """  glDisable(GL_BLEND);
  glUniform1i(kindLocation, 0);
}

void renderLoop() {
""",
    """  glDisable(GL_BLEND);
  glUniform1i(kindLocation, 0);
  glUniform3f(offsetLocation, 0.0f, 0.0f, 0.0f);
}

void renderLoop() {
""",
)
replace_once(
    path,
    """  Bounds3 uploadedBounds;
  std::vector<MeshDrawRange> uploadedDrawRanges;
  GLsizei uploadedVertexCount = 0;
""",
    """  Bounds3 uploadedBounds;
  std::vector<MeshDrawRange> uploadedDrawRanges;
  std::vector<Vec3> uploadedExplodeDirections;
  GLsizei uploadedVertexCount = 0;
""",
)
replace_once(
    path,
    """    int selectionKind = 0;
    long long selectionTriangle = -1;
    int selectionFeature = -1;

    {
""",
    """    int selectionKind = 0;
    long long selectionTriangle = -1;
    int selectionFeature = -1;
    float explodeFactor = 0.0f;

    {
""",
)
replace_once(
    path,
    """      selectionKind = g.selectionKind;
      selectionTriangle = g.selectionTriangle;
      selectionFeature = g.selectionFeature;
      g.dirty.store(false);
""",
    """      selectionKind = g.selectionKind;
      selectionTriangle = g.selectionTriangle;
      selectionFeature = g.selectionFeature;
      explodeFactor = g.explodeFactor;
      g.dirty.store(false);
""",
)
replace_once(
    path,
    """        if (snapshot.mesh != uploadedMesh) {
          uploadedMesh = std::move(snapshot.mesh);
          uploadedVertexCount = 0;
""",
    """        if (snapshot.mesh != uploadedMesh) {
          uploadedMesh = std::move(snapshot.mesh);
          uploadedVertexCount = 0;
""",
)
replace_once(
    path,
    """          } else {
            glBufferData(GL_ARRAY_BUFFER, 0, nullptr, GL_STATIC_DRAW);
          }
        }
      }
    }
""",
    """          } else {
            glBufferData(GL_ARRAY_BUFFER, 0, nullptr, GL_STATIC_DRAW);
          }
        }
        uploadedExplodeDirections = uploadedMesh == nullptr
            ? std::vector<Vec3>{}
            : buildExplodeDirections(*uploadedMesh, uploadedDrawRanges);
      }
    }
""",
)
replace_once(
    path,
    """      const float safeZoom = std::clamp(zoom, 0.05f, 20.0f);

      const Mat4 centerModel = translation(-center.x, -center.y, -center.z);
""",
    """      const float safeZoom = std::clamp(zoom, 0.05f, 20.0f);
      const float explodeDistance = extent * 0.55f * std::clamp(explodeFactor, 0.0f, 1.0f);

      const Mat4 centerModel = translation(-center.x, -center.y, -center.z);
""",
)
replace_once(
    path,
    """      glUniform1i(glGetUniformLocation(program, "uSelectionFeature"), -1);
      glUniform3f(
          glGetUniformLocation(program, "uSelectionColor"),
""",
    """      glUniform1i(glGetUniformLocation(program, "uSelectionFeature"), -1);
      glUniform3f(glGetUniformLocation(program, "uObjectOffset"), 0.0f, 0.0f, 0.0f);
      glUniform3f(
          glGetUniformLocation(program, "uSelectionColor"),
""",
)
replace_once(
    path,
    """      drawUploadedMesh(program, uploadedDrawRanges, uploadedVertexCount);
      drawSelectionOverlay(
          program,
          uploadedDrawRanges,
          uploadedVertexCount,
          selectionKind,
""",
    """      drawUploadedMesh(
          program,
          uploadedDrawRanges,
          uploadedExplodeDirections,
          uploadedVertexCount,
          explodeDistance);
      drawSelectionOverlay(
          program,
          uploadedDrawRanges,
          uploadedExplodeDirections,
          uploadedVertexCount,
          explodeDistance,
          selectionKind,
""",
)
replace_once(
    path,
    """    g.selectionKind = 0;
    g.selectionTriangle = -1;
    g.selectionFeature = -1;
  }
""",
    """    g.selectionKind = 0;
    g.selectionTriangle = -1;
    g.selectionFeature = -1;
    g.explodeFactor = 0.0f;
  }
""",
)
replace_once(
    path,
    """        g.selectionKind = kind;
        g.selectionTriangle = triangle;
        g.selectionFeature = feature;
      }
    }
    g.dirty.store(true);
""",
    """        g.selectionKind = kind;
        g.selectionTriangle = triangle;
        g.selectionFeature = feature;
      }
    } else if (cmd.rfind("explode:", 0) == 0) {
      float factor = 0.0f;
      if (std::sscanf(cmd.c_str(), "explode:%f", &factor) == 1) {
        g.explodeFactor = std::clamp(factor, 0.0f, 1.0f);
      }
    }
    g.dirty.store(true);
""",
)

# Viewer controls and state.
path = "lib/src/viewer/engineering_workspace_page.dart"
replace_once(
    path,
    """  bool _sectionEnabled = false;
  String _sectionAxis = 'z';
  double _sectionOffset = 0;
""",
    """  bool _sectionEnabled = false;
  String _sectionAxis = 'z';
  double _sectionOffset = 0;
  double _explodeFactor = 0.0;
""",
)
replace_once(
    path,
    """  bool get _busy =>
""",
    """  bool get _canExplode =>
      _objects.where((object) => object.hasGeometry && object.effectiveVisible).length > 1;
  bool get _exploded => _explodeFactor > 0.001;

  bool get _busy =>
""",
)
replace_once(
    path,
    """        _zoom = 1;
        _status =
""",
    """        _zoom = 1;
        _explodeFactor = 0.0;
        _status =
""",
)
replace_once(
    path,
    """  Future<void> _showSectionControls() async {
""",
    """  Future<void> _showExplodeControls() async {
    if (!_canExplode || _busy || _editActive || _sectionEnabled) return;
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
                        unawaited(CadEngineV01Tools.instance.setExplodeFactor(value));
                      },
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text('${(factor * 100).round()}%', textAlign: TextAlign.end),
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
                        unawaited(CadEngineV01Tools.instance.setExplodeFactor(0));
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
""",
)
replace_once(
    path,
    """      _clearMeasure(leaveMode: true);
      _status = status;
""",
    """      _clearMeasure(leaveMode: true);
      _explodeFactor = 0.0;
      _status = status;
""",
)
replace_once(
    path,
    """            if (_objects.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('对象与可见性'),
                subtitle: const Text('浏览模型层级并隐藏/显示对象'),
                onTap: () => Navigator.pop(context, 'objects'),
              ),
            ListTile(
""",
    """            if (_objects.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('对象与可见性'),
                subtitle: const Text('浏览模型层级并隐藏/显示对象'),
                onTap: () => Navigator.pop(context, 'objects'),
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
""",
)
replace_once(
    path,
    """      case 'inspect':
        await _inspect();
        break;
""",
    """      case 'explode':
        await _showExplodeControls();
        break;
      case 'inspect':
        await _inspect();
        break;
""",
)
replace_once(
    path,
    """                    _selection != null ||
                    _editActive ||
                    _sectionEnabled)
""",
    """                    _selection != null ||
                    _editActive ||
                    _sectionEnabled ||
                    _exploded)
""",
)
replace_once(
    path,
    """                            if (_editActive)
                              Chip(
""",
    """                            if (_exploded)
                              Chip(
                                avatar: const Icon(Icons.open_with, size: 18),
                                label: Text('爆炸 ${(100 * _explodeFactor).round()}%'),
                              ),
                            if (_editActive)
                              Chip(
""",
)
replace_once(
    path,
    """  void dispose() {
    _progressTimer?.cancel();
    unawaited(CadEngineV01Tools.instance.clearSelectionHighlight());
""",
    """  void dispose() {
    _progressTimer?.cancel();
    unawaited(CadEngineV01Tools.instance.setExplodeFactor(0));
    unawaited(CadEngineV01Tools.instance.clearSelectionHighlight());
""",
)

# Focused UI regression uses two geometry objects and checks explode commands.
path = "test/viewer_workspace_test.dart"
replace_once(
    path,
    """void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cad_engine/methods');

  setUp(() {
""",
    """void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cad_engine/methods');
  final displayCommands = <String>[];

  setUp(() {
    displayCommands.clear();
""",
)
replace_once(
    path,
    """        case 'resizeViewport':
        case 'disposeViewport':
        case 'setProjection':
        case 'setDisplayMode':
        case 'fitAll':
""",
    """        case 'resizeViewport':
        case 'disposeViewport':
        case 'setProjection':
        case 'fitAll':
""",
)
replace_once(
    path,
    """        case 'loadModel':
          return <Object?, Object?>{
""",
    """        case 'setDisplayMode':
          final arguments = call.arguments as Map<Object?, Object?>?;
          final mode = arguments?['mode'] as String?;
          if (mode != null) displayCommands.add(mode);
          return null;
        case 'loadModel':
          return <Object?, Object?>{
""",
)
replace_once(
    path,
    """        case 'getObjectPresentation':
          return '[{"id":"body-0","label":"Chest","type":"mesh","parentId":"","visible":true,"effectiveVisible":true,"hasGeometry":true,"hasBaseColor":true,"baseColor":[0.7,0.76,0.84]}]';
""",
    """        case 'getObjectPresentation':
          return '[{"id":"body-0","label":"Chest","type":"mesh","parentId":"","visible":true,"effectiveVisible":true,"hasGeometry":true,"hasBaseColor":true,"baseColor":[0.7,0.76,0.84]},{"id":"body-1","label":"Plate","type":"mesh","parentId":"","visible":true,"effectiveVisible":true,"hasGeometry":true,"hasBaseColor":false,"baseColor":[0.7,0.76,0.84]}]';
""",
)
replace_once(
    path,
    """    expect(find.text('拆分连通部件'), findsOneWidget);
    expect(find.textContaining('OBJ'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

""",
    """    expect(find.text('拆分连通部件'), findsOneWidget);
    expect(find.text('爆炸视图'), findsOneWidget);
    expect(find.textContaining('OBJ'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exploded assembly view drives native per-object display offsets',
      (tester) async {
    await pumpWorkspace(tester, Brightness.light);
    await tester.tap(find.byTooltip('工程操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('爆炸视图'));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(0.6);
    await tester.pumpAndSettle();

    expect(displayCommands.any((mode) => mode == 'explode:0.6000'), isTrue);
    expect(find.text('60%'), findsOneWidget);
    await tester.tap(find.text('复位'));
    await tester.pumpAndSettle();
    expect(displayCommands.any((mode) => mode == 'explode:0.0000'), isTrue);
    expect(tester.takeException(), isNull);
  });

""",
)
