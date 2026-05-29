cmake_minimum_required(VERSION 3.16)
project(cursor-chapter-marker VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── OBS targets (IMPORTED, defined in cmake/ObsTargets.cmake) ──────────────
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/ObsTargets.cmake")

# ── Qt6 (from obs-deps Qt6 pre-built package) ─────────────────────────────
if(NOT DEFINED OBS_DEPS_QT6_DIR)
  message(FATAL_ERROR "Pass -DOBS_DEPS_QT6_DIR=<path/to/qt6-deps>")
endif()
find_package(Qt6 REQUIRED COMPONENTS Core Widgets
    PATHS "${OBS_DEPS_QT6_DIR}" NO_DEFAULT_PATH)

# ── Plugin target ──────────────────────────────────────────────────────────
add_library(cursor-chapter-marker MODULE
    src/plugin-main.c
    src/cursor-chapter-marker.cpp
    src/cursor-chapter-marker.hpp
)

target_include_directories(cursor-chapter-marker PRIVATE src)

target_link_libraries(cursor-chapter-marker
    PRIVATE
        OBS::libobs
        OBS::obs-frontend-api
        Qt6::Core
        Qt6::Widgets
)

if(WIN32)
    target_link_libraries(cursor-chapter-marker PRIVATE user32)
endif()

set_target_properties(cursor-chapter-marker PROPERTIES
    PREFIX ""
    AUTOMOC ON
    OUTPUT_NAME "cursor-chapter-marker"
)

# ── Install ────────────────────────────────────────────────────────────────
install(TARGETS cursor-chapter-marker
    LIBRARY DESTINATION "obs-plugins/64bit"
    RUNTIME DESTINATION "obs-plugins/64bit"
)
install(DIRECTORY data/ DESTINATION "data/obs-plugins/cursor-chapter-marker")
