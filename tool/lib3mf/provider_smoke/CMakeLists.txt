cmake_minimum_required(VERSION 3.22)
project(brepsight_lib3mf_provider_smoke LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT DEFINED BREPSIGHT_LIB3MF_ROOT OR BREPSIGHT_LIB3MF_ROOT STREQUAL "")
  message(FATAL_ERROR "BREPSIGHT_LIB3MF_ROOT must point to the staged lib3mf Android SDK")
endif()

list(PREPEND CMAKE_PREFIX_PATH "${BREPSIGHT_LIB3MF_ROOT}")
find_package(lib3mf CONFIG REQUIRED)

add_library(brepsight_lib3mf_provider_smoke SHARED
  provider_smoke.cpp
)

target_link_libraries(brepsight_lib3mf_provider_smoke PRIVATE lib3mf::lib3mf)
target_compile_options(brepsight_lib3mf_provider_smoke PRIVATE -Wall -Wextra -Werror)
