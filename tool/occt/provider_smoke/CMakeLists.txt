cmake_minimum_required(VERSION 3.22.1)
project(brepsight_occt_provider_smoke LANGUAGES CXX)

set(BREPSIGHT_OCCT_ROOT "" CACHE PATH "Root of installed BrepSight OCCT SDK")
if(NOT BREPSIGHT_OCCT_ROOT)
  message(FATAL_ERROR "BREPSIGHT_OCCT_ROOT is required")
endif()

file(GLOB_RECURSE _occt_configs
  LIST_DIRECTORIES FALSE
  "${BREPSIGHT_OCCT_ROOT}/OpenCASCADEConfig.cmake"
  "${BREPSIGHT_OCCT_ROOT}/*/OpenCASCADEConfig.cmake"
  "${BREPSIGHT_OCCT_ROOT}/*/*/OpenCASCADEConfig.cmake"
  "${BREPSIGHT_OCCT_ROOT}/*/*/*/OpenCASCADEConfig.cmake"
)
list(LENGTH _occt_configs _occt_count)
if(_occt_count EQUAL 0)
  message(FATAL_ERROR "OpenCASCADEConfig.cmake not found under ${BREPSIGHT_OCCT_ROOT}")
endif()
list(GET _occt_configs 0 _occt_config)
get_filename_component(OpenCASCADE_DIR "${_occt_config}" DIRECTORY)

# STEP/XCAF exported targets transitively reference TKService and TKV3d.
# Loading Visualization defines those official imported targets; BrepSight still
# renders through its own Android GLES viewport.
find_package(OpenCASCADE CONFIG REQUIRED COMPONENTS
  FoundationClasses
  ModelingData
  ModelingAlgorithms
  Visualization
  ApplicationFramework
  DataExchange
)

set(BREPSIGHT_CPP_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../packages/cad_engine/android/src/main/cpp")

add_library(brepsight_occt_provider_smoke SHARED
  "${BREPSIGHT_CPP_DIR}/step_occt_importer.cpp"
)

target_compile_features(brepsight_occt_provider_smoke PRIVATE cxx_std_20)
target_compile_definitions(brepsight_occt_provider_smoke PRIVATE BREPSIGHT_WITH_OCCT=1)
target_include_directories(brepsight_occt_provider_smoke PRIVATE
  "${BREPSIGHT_CPP_DIR}"
  "${OpenCASCADE_INCLUDE_DIR}"
)
target_compile_options(brepsight_occt_provider_smoke PRIVATE -Wall -Wextra -Werror -Wpedantic)

# Link only the toolkits for symbols used directly by step_occt_importer.cpp.
# OCCT imported targets carry the remaining runtime dependency graph.
target_link_libraries(brepsight_occt_provider_smoke PRIVATE
  TKDESTEP
  TKXCAF
  TKMesh
)
