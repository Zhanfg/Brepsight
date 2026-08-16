cmake_minimum_required(VERSION 3.22.1)
project(cad_engine LANGUAGES CXX)

set(BREPSIGHT_OCCT_ROOT "" CACHE PATH "Optional root of a BrepSight OCCT Android SDK")

add_library(
    cad_engine
    SHARED
    cad_engine_jni.cpp
    mesh_analysis_jni.cpp
    mesh_split_jni.cpp
    mesh_merge_jni.cpp
    stl_importer.cpp
    obj_importer.cpp
    step_occt_importer.cpp
    mesh_writer.cpp
    mesh_analysis.cpp
    mesh_components.cpp
    mesh_merge.cpp
)

target_compile_features(cad_engine PRIVATE cxx_std_20)
target_compile_options(cad_engine PRIVATE -Wall -Wextra -Wpedantic)
target_link_libraries(cad_engine PRIVATE android log EGL GLESv3)

if(BREPSIGHT_OCCT_ROOT)
    file(GLOB_RECURSE _brepsight_occt_configs
        LIST_DIRECTORIES FALSE
        "${BREPSIGHT_OCCT_ROOT}/OpenCASCADEConfig.cmake"
        "${BREPSIGHT_OCCT_ROOT}/*/OpenCASCADEConfig.cmake"
        "${BREPSIGHT_OCCT_ROOT}/*/*/OpenCASCADEConfig.cmake"
        "${BREPSIGHT_OCCT_ROOT}/*/*/*/OpenCASCADEConfig.cmake"
    )
    list(LENGTH _brepsight_occt_configs _brepsight_occt_config_count)
    if(_brepsight_occt_config_count EQUAL 0)
        message(FATAL_ERROR "BREPSIGHT_OCCT_ROOT does not contain OpenCASCADEConfig.cmake: ${BREPSIGHT_OCCT_ROOT}")
    endif()
    list(GET _brepsight_occt_configs 0 _brepsight_occt_config)
    get_filename_component(OpenCASCADE_DIR "${_brepsight_occt_config}" DIRECTORY)

    find_package(OpenCASCADE CONFIG REQUIRED COMPONENTS
        FoundationClasses
        ModelingData
        ModelingAlgorithms
        ApplicationFramework
        DataExchange
    )

    target_compile_definitions(cad_engine PRIVATE BREPSIGHT_WITH_OCCT=1)
    target_include_directories(cad_engine PRIVATE "${OpenCASCADE_INCLUDE_DIR}")
    target_link_libraries(cad_engine PRIVATE
        ${OpenCASCADE_FoundationClasses_LIBRARIES}
        ${OpenCASCADE_ModelingData_LIBRARIES}
        ${OpenCASCADE_ModelingAlgorithms_LIBRARIES}
        ${OpenCASCADE_ApplicationFramework_LIBRARIES}
        ${OpenCASCADE_DataExchange_LIBRARIES}
    )
    message(STATUS "BrepSight OCCT provider enabled from ${OpenCASCADE_DIR}")
else()
    message(STATUS "BrepSight OCCT provider disabled; STL/OBJ mesh path remains available")
endif()
