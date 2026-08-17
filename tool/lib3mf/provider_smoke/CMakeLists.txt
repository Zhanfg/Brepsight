cmake_minimum_required(VERSION 3.22)
project(brepsight_lib3mf_provider_smoke LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT DEFINED BREPSIGHT_LIB3MF_ROOT OR BREPSIGHT_LIB3MF_ROOT STREQUAL "")
  message(FATAL_ERROR "BREPSIGHT_LIB3MF_ROOT must point to a staged lib3mf SDK")
endif()

file(GLOB_RECURSE _lib3mf_configs
  LIST_DIRECTORIES FALSE
  "${BREPSIGHT_LIB3MF_ROOT}/lib3mfConfig.cmake"
  "${BREPSIGHT_LIB3MF_ROOT}/*/lib3mfConfig.cmake"
  "${BREPSIGHT_LIB3MF_ROOT}/*/*/lib3mfConfig.cmake"
  "${BREPSIGHT_LIB3MF_ROOT}/*/*/*/lib3mfConfig.cmake"
)
list(LENGTH _lib3mf_configs _lib3mf_count)
if(_lib3mf_count EQUAL 0)
  message(FATAL_ERROR "lib3mfConfig.cmake not found under staged SDK: ${BREPSIGHT_LIB3MF_ROOT}")
endif()
list(GET _lib3mf_configs 0 _lib3mf_config)
get_filename_component(lib3mf_DIR "${_lib3mf_config}" DIRECTORY)
find_package(lib3mf CONFIG REQUIRED PATHS "${lib3mf_DIR}" NO_DEFAULT_PATH)

set(BREPSIGHT_NATIVE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../packages/cad_engine/android/src/main/cpp")

add_library(brepsight_lib3mf_provider_smoke SHARED
  provider_smoke.cpp
  "${BREPSIGHT_NATIVE_DIR}/three_mf_importer.cpp"
)

target_compile_definitions(brepsight_lib3mf_provider_smoke PRIVATE BREPSIGHT_WITH_LIB3MF=1)
target_include_directories(brepsight_lib3mf_provider_smoke PRIVATE "${BREPSIGHT_NATIVE_DIR}")
target_link_libraries(brepsight_lib3mf_provider_smoke PRIVATE lib3mf::lib3mf)
target_compile_options(brepsight_lib3mf_provider_smoke PRIVATE -Wall -Wextra -Werror)

if(NOT ANDROID)
  add_executable(brepsight_lib3mf_semantic_fixture_test
    semantic_fixture_test.cpp
    "${BREPSIGHT_NATIVE_DIR}/three_mf_importer.cpp"
  )
  target_compile_definitions(brepsight_lib3mf_semantic_fixture_test PRIVATE BREPSIGHT_WITH_LIB3MF=1)
  target_include_directories(brepsight_lib3mf_semantic_fixture_test PRIVATE "${BREPSIGHT_NATIVE_DIR}")
  target_link_libraries(brepsight_lib3mf_semantic_fixture_test PRIVATE lib3mf::lib3mf)
  target_compile_options(brepsight_lib3mf_semantic_fixture_test PRIVATE -Wall -Wextra -Werror)
endif()
