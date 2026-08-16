cmake_minimum_required(VERSION 3.22.1)
project(cad_engine LANGUAGES CXX)

add_library(cad_engine SHARED cad_engine_jni.cpp)

target_compile_features(cad_engine PRIVATE cxx_std_20)
target_compile_options(cad_engine PRIVATE -Wall -Wextra -Wpedantic)

target_link_libraries(cad_engine PRIVATE android log EGL GLESv3)

# Stage 2: link freshly-built OpenCASCADE here instead of the old Qt-bound
# libCADAssistant.so. Keep the Flutter/native ABI stable while replacing this
# EGL proof renderer with OCCT V3d_Viewer/AIS_InteractiveContext.
