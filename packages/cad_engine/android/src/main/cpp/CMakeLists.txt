cmake_minimum_required(VERSION 3.22.1)
project(cad_engine LANGUAGES CXX)

set(BREPSIGHT_OCCT_ROOT "" CACHE PATH "Optional root of a BrepSight OCCT Android SDK")
set(BREPSIGHT_LIB3MF_ROOT "" CACHE PATH "Optional root of a BrepSight lib3mf Android SDK")

add_library(
    cad_engine
    SHARED
    cad_engine_jni.cpp
    mesh_analysis_jni.cpp
    mesh_split_jni.cpp
    mesh_merge_jni.cpp
    runtime_model_loader.cpp
    stl_importer.cpp
    obj_importer.cpp
    step_occt_importer.cpp
    three_mf_importer.cpp
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

    # OCCT 8.0 STEP/XCAF imported targets transitively reference TKService/TKV3d.
    # Load Visualization targets so those link dependencies are defined; BrepSight
    # continues to render through its own Android GLES viewport.
    find_package(OpenCASCADE CONFIG REQUIRED COMPONENTS
        FoundationClasses
        ModelingData
        ModelingAlgorithms
        Visualization
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

if(BREPSIGHT_LIB3MF_ROOT)
    set(lib3mf_DIR "${BREPSIGHT_LIB3MF_ROOT}/lib/cmake/lib3mf")
    if(NOT EXISTS "${lib3mf_DIR}/lib3mfConfig.cmake")
        message(FATAL_ERROR "BREPSIGHT_LIB3MF_ROOT does not contain lib/cmake/lib3mf/lib3mfConfig.cmake: ${BREPSIGHT_LIB3MF_ROOT}")
    endif()
    find_package(lib3mf CONFIG REQUIRED PATHS "${lib3mf_DIR}" NO_DEFAULT_PATH)
    target_compile_definitions(cad_engine PRIVATE BREPSIGHT_WITH_LIB3MF=1)
    target_link_libraries(cad_engine PRIVATE lib3mf::lib3mf)
    message(STATUS "BrepSight 3MF provider enabled from ${lib3mf_DIR}")
else()
    message(STATUS "BrepSight 3MF provider disabled; .3mf files remain unavailable in this build")
endif()
