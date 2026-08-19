cmake_minimum_required(VERSION 3.22)
project(brepsight_occt_semantic_contract LANGUAGES CXX)

set(BREPSIGHT_OCCT_ROOT "" CACHE PATH "Root of installed pinned OCCT SDK")
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

# OCCT 8.0 installs one export file per module. Those generated export files
# validate cross-module imported-target dependencies as they are included, so
# dependencies must be loaded before their consumers. ApplicationFramework's
# XCAF targets reference TKService/TKV3d from Visualization.
find_package(OpenCASCADE CONFIG REQUIRED COMPONENTS
  FoundationClasses
  ModelingData
  ModelingAlgorithms
  Visualization
  ApplicationFramework
  DataExchange
)

set(BREPSIGHT_CPP_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../packages/cad_engine/android/src/main/cpp")
add_executable(brepsight_iges_contract
  contract_fixture_test.cpp
  "${BREPSIGHT_CPP_DIR}/iges_occt_importer.cpp"
)
target_compile_features(brepsight_iges_contract PRIVATE cxx_std_20)
target_compile_definitions(brepsight_iges_contract PRIVATE BREPSIGHT_WITH_OCCT=1)
target_include_directories(brepsight_iges_contract PRIVATE
  "${BREPSIGHT_CPP_DIR}"
  "${OpenCASCADE_INCLUDE_DIR}"
)
target_compile_options(brepsight_iges_contract PRIVATE -Wall -Wextra -Wpedantic)
target_link_libraries(brepsight_iges_contract PRIVATE
  TKDEIGES
  TKXCAF
  TKMesh
  TKPrim
  TKBRep
  TKTopAlgo
)
