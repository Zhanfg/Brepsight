cmake_minimum_required(VERSION 3.22)
project(brepsight_fcstd_provider_smoke LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(OpenCASCADE REQUIRED COMPONENTS
    FoundationClasses
    ModelingData
    ModelingAlgorithms
)

get_filename_component(BREPSIGHT_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(BREPSIGHT_CPP "${BREPSIGHT_ROOT}/packages/cad_engine/android/src/main/cpp")

add_executable(
    brepsight_fcstd_semantic_smoke
    semantic_fixture_test.cpp
    "${BREPSIGHT_CPP}/brep_occt_importer.cpp"
    "${BREPSIGHT_CPP}/freecad_fcstd_importer.cpp"
    "${BREPSIGHT_CPP}/freecad_presentation_adapter.cpp"
    "${BREPSIGHT_CPP}/mesh_presentation.cpp"
)

target_compile_definitions(brepsight_fcstd_semantic_smoke PRIVATE BREPSIGHT_WITH_OCCT=1)
target_include_directories(brepsight_fcstd_semantic_smoke PRIVATE
    "${BREPSIGHT_CPP}"
    "${OpenCASCADE_INCLUDE_DIR}"
)

# Ubuntu 24.04 ships OCCT 7.6.x. Force-include a tiny compatibility alias so
# the same production importer source can be executed on the host while Android
# remains pinned to OCCT 8.0.0.
target_compile_options(brepsight_fcstd_semantic_smoke PRIVATE
    -Wall -Wextra -Wpedantic
    -include "${CMAKE_CURRENT_LIST_DIR}/occt_legacy_compat.h"
)

target_link_libraries(brepsight_fcstd_semantic_smoke PRIVATE
    ${OpenCASCADE_FoundationClasses_LIBRARIES}
    ${OpenCASCADE_ModelingData_LIBRARIES}
    ${OpenCASCADE_ModelingAlgorithms_LIBRARIES}
)
