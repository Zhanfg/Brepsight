cmake_minimum_required(VERSION 3.22.1)
project(cad_engine LANGUAGES CXX)

set(BREPSIGHT_OCCT_ROOT "" CACHE PATH "Optional root of a BrepSight OCCT Android SDK")
set(BREPSIGHT_LIB3MF_ROOT "" CACHE PATH "Optional root of a BrepSight lib3mf Android SDK")
set(BREPSIGHT_ASSIMP_ROOT "" CACHE PATH "Optional root of a BrepSight Assimp Android SDK")

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
    assimp_dcc_importer.cpp
    brep_occt_importer.cpp
    step_occt_importer.cpp
    iges_occt_importer.cpp
    freecad_fcstd_importer.cpp
    freecad_presentation_adapter.cpp
    three_mf_importer.cpp
    mesh_writer.cpp
    mesh_analysis.cpp
    mesh_components.cpp
    mesh_merge.cpp
    mesh_presentation.cpp
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
        Visualization
        ApplicationFramework
        DataExchange
    )

    target_compile_definitions(cad_engine PRIVATE BREPSIGHT_WITH_OCCT=1)
    target_include_directories(cad_engine PRIVATE "${OpenCASCADE_INCLUDE_DIR}")
    target_link_libraries(cad_engine PRIVATE
        TKBRep
        TKDESTEP
        TKDEIGES
        TKXCAF
        TKMesh
    )
    message(STATUS "BrepSight OCCT providers enabled from ${OpenCASCADE_DIR}")
else()
    message(STATUS "BrepSight OCCT providers disabled; STL/OBJ mesh path remains available")
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

if(BREPSIGHT_ASSIMP_ROOT)
    file(GLOB_RECURSE _brepsight_assimp_configs
        LIST_DIRECTORIES FALSE
        "${BREPSIGHT_ASSIMP_ROOT}/assimpConfig.cmake"
        "${BREPSIGHT_ASSIMP_ROOT}/*/assimpConfig.cmake"
        "${BREPSIGHT_ASSIMP_ROOT}/*/*/assimpConfig.cmake"
        "${BREPSIGHT_ASSIMP_ROOT}/*/*/*/assimpConfig.cmake"
        "${BREPSIGHT_ASSIMP_ROOT}/*/*/*/*/assimpConfig.cmake"
    )
    list(LENGTH _brepsight_assimp_configs _brepsight_assimp_config_count)
    if(_brepsight_assimp_config_count EQUAL 0)
        message(FATAL_ERROR "BREPSIGHT_ASSIMP_ROOT does not contain assimpConfig.cmake: ${BREPSIGHT_ASSIMP_ROOT}")
    endif()
    list(GET _brepsight_assimp_configs 0 _brepsight_assimp_config)
    get_filename_component(assimp_DIR "${_brepsight_assimp_config}" DIRECTORY)

    find_package(assimp CONFIG REQUIRED PATHS "${assimp_DIR}" NO_DEFAULT_PATH)
    target_compile_definitions(cad_engine PRIVATE BREPSIGHT_WITH_ASSIMP=1)
    target_link_libraries(cad_engine PRIVATE assimp::assimp)
    message(STATUS "BrepSight Assimp baseline provider enabled from ${assimp_DIR}")
else()
    message(STATUS "BrepSight Assimp provider disabled; DCC/interchange mesh formats remain unavailable in this build")
endif()
