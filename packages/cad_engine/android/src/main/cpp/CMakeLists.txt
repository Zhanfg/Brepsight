cmake_minimum_required(VERSION 3.22.1)
project(cad_engine LANGUAGES CXX)

add_library(
    cad_engine
    SHARED
    cad_engine_jni.cpp
    mesh_analysis_jni.cpp
    stl_importer.cpp
    obj_importer.cpp
    mesh_writer.cpp
    mesh_analysis.cpp
)

target_compile_features(cad_engine PRIVATE cxx_std_20)
target_compile_options(cad_engine PRIVATE -Wall -Wextra -Wpedantic)

target_link_libraries(cad_engine PRIVATE android log EGL GLESv3)

# OCCT will be added as a provider beside the mesh path. The Flutter/native ABI
# stays stable while exact B-Rep formats are introduced incrementally.
