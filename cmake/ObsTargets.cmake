# Defines OBS::libobs and OBS::obs-frontend-api as IMPORTED targets.
# Requires the following variables to be set before including this file
# (build.ps1 sets them via cmake -D flags):
#
#   OBS_BIN_DIR      — path to the OBS 64-bit bin directory
#                      e.g. X:/obs-studio/bin/64bit
#   OBS_HEADERS_DIR  — path to a sparse checkout of obs-studio source
#   OBS_IMPLIB_DIR   — path to the directory containing generated .lib files

if(NOT DEFINED OBS_BIN_DIR)
    message(FATAL_ERROR "OBS_BIN_DIR is not set. Pass -DOBS_BIN_DIR=<path>")
endif()
if(NOT DEFINED OBS_HEADERS_DIR)
    message(FATAL_ERROR "OBS_HEADERS_DIR is not set. Pass -DOBS_HEADERS_DIR=<path>")
endif()
if(NOT DEFINED OBS_IMPLIB_DIR)
    message(FATAL_ERROR "OBS_IMPLIB_DIR is not set. Pass -DOBS_IMPLIB_DIR=<path>")
endif()

# ── OBS::libobs ─────────────────────────────────────────────────────────
add_library(OBS::libobs SHARED IMPORTED GLOBAL)
set_target_properties(OBS::libobs PROPERTIES
    IMPORTED_LOCATION  "${OBS_BIN_DIR}/obs.dll"
    IMPORTED_IMPLIB    "${OBS_IMPLIB_DIR}/obs.lib"
    INTERFACE_INCLUDE_DIRECTORIES "${OBS_HEADERS_DIR}/libobs"
)

# ── OBS::obs-frontend-api ────────────────────────────────────────────────
add_library(OBS::obs-frontend-api SHARED IMPORTED GLOBAL)
set_target_properties(OBS::obs-frontend-api PROPERTIES
    IMPORTED_LOCATION  "${OBS_BIN_DIR}/obs-frontend-api.dll"
    IMPORTED_IMPLIB    "${OBS_IMPLIB_DIR}/obs-frontend-api.lib"
    INTERFACE_INCLUDE_DIRECTORIES "${OBS_HEADERS_DIR}/frontend/api"
)
# obs-frontend-api depends on libobs headers too
target_link_libraries(OBS::obs-frontend-api INTERFACE OBS::libobs)
