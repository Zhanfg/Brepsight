#include <lib3mf_implicit.hpp>

#include <vector>

extern "C" int brepsight_lib3mf_provider_smoke() {
  auto wrapper = Lib3MF::CWrapper::loadLibrary();
  if (!wrapper) return 1;

  Lib3MF_uint32 major = 0;
  Lib3MF_uint32 minor = 0;
  Lib3MF_uint32 micro = 0;
  wrapper->GetLibraryVersion(major, minor, micro);

  auto model = wrapper->CreateModel();
  if (!model) return 2;

  const auto unit = model->GetUnit();
  auto reader = model->QueryReader("3mf");
  auto buildItems = model->GetBuildItems();
  auto meshObjects = model->GetMeshObjects();
  auto componentObjects = model->GetComponentsObjects();

  std::vector<Lib3MF::sPosition> vertices;
  std::vector<Lib3MF::sTriangle> triangles;

  if (meshObjects->MoveNext()) {
    auto mesh = meshObjects->GetCurrentMeshObject();
    mesh->GetVertices(vertices);
    mesh->GetTriangleIndices(triangles);
    (void)mesh->GetVertexCount();
    (void)mesh->GetTriangleCount();
  }

  if (buildItems->MoveNext()) {
    auto item = buildItems->GetCurrent();
    auto object = item->GetObjectResource();
    (void)item->GetObjectResourceID();
    (void)item->GetObjectTransform();
    (void)object->GetName();
    (void)object->GetPartNumber();
    (void)object->IsMeshObject();
    (void)object->IsComponentsObject();
  }

  if (componentObjects->MoveNext()) {
    auto object = componentObjects->GetCurrentComponentsObject();
    const auto count = object->GetComponentCount();
    if (count > 0) {
      auto component = object->GetComponent(0);
      (void)component->GetObjectResource();
      (void)component->GetObjectResourceID();
      (void)component->GetTransform();
    }
  }

  (void)major;
  (void)minor;
  (void)micro;
  (void)unit;
  (void)reader;
  return 0;
}
