cmake_minimum_required(VERSION 3.22)
project(brepsight_assimp_provider_smoke LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(assimp CONFIG REQUIRED)

get_filename_component(BREPSIGHT_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(BREPSIGHT_CPP "${BREPSIGHT_ROOT}/packages/cad_engine/android/src/main/cpp")

add_executable(
    brepsight_assimp_semantic_smoke
    semantic_fixture_test.cpp
    "${BREPSIGHT_CPP}/assimp_dcc_importer.cpp"
    "${BREPSIGHT_CPP}/mesh_presentation.cpp"
)

target_compile_definitions(brepsight_assimp_semantic_smoke PRIVATE BREPSIGHT_WITH_ASSIMP=1)
target_include_directories(brepsight_assimp_semantic_smoke PRIVATE "${BREPSIGHT_CPP}")
target_compile_options(brepsight_assimp_semantic_smoke PRIVATE -Wall -Wextra -Wpedantic)
target_link_libraries(brepsight_assimp_semantic_smoke PRIVATE assimp::assimp)
