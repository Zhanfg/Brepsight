cmake_minimum_required(VERSION 3.22)
project(brepsight_opennurbs_contract LANGUAGES C CXX)

set(BREPSIGHT_OPENNURBS_SOURCE "" CACHE PATH "Pinned openNURBS source checkout")
if(NOT BREPSIGHT_OPENNURBS_SOURCE OR NOT EXISTS "${BREPSIGHT_OPENNURBS_SOURCE}/opennurbs_public.h")
  message(FATAL_ERROR "BREPSIGHT_OPENNURBS_SOURCE must point to a pinned openNURBS checkout")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Build the pinned upstream library in the same graph so this executable tests
# BrepSight's real importer rather than a mock parser.
add_subdirectory("${BREPSIGHT_OPENNURBS_SOURCE}" opennurbs-build EXCLUDE_FROM_ALL)

set(BREPSIGHT_CPP_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../packages/cad_engine/android/src/main/cpp")
add_executable(brepsight_3dm_contract
  contract_fixture_test.cpp
  "${BREPSIGHT_CPP_DIR}/rhino_3dm_importer.cpp"
  "${BREPSIGHT_CPP_DIR}/mesh_presentation.cpp"
)
target_compile_definitions(brepsight_3dm_contract PRIVATE BREPSIGHT_WITH_OPENNURBS=1)
target_include_directories(brepsight_3dm_contract PRIVATE
  "${BREPSIGHT_CPP_DIR}"
  "${BREPSIGHT_OPENNURBS_SOURCE}"
)
target_compile_options(brepsight_3dm_contract PRIVATE -Wall -Wextra -Wpedantic)
target_link_libraries(brepsight_3dm_contract PRIVATE OpenNURBS)
