cmake_minimum_required(VERSION 3.22)
project(jsbsim_gdextension VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
option(JSBSIM_ENABLED "Link against JSBSim library" ON)
option(GODOT_CPP_DIR  "Path to godot-cpp (set via -DGODOT_CPP_DIR=...)"  "")

# ---------------------------------------------------------------------------
# godot-cpp
# ---------------------------------------------------------------------------
# Expected structure:
#   RC-Flight-Sim/
#     godot_project/addons/jsbsim_gdextension/   <-- this CMakeLists.txt
#     godot-cpp/                                  <-- godot-cpp submodule
#
# Override with -DGODOT_CPP_DIR=<path>
if("${GODOT_CPP_DIR}" STREQUAL "")
    set(GODOT_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../godot-cpp")
endif()

if(NOT EXISTS "${GODOT_CPP_DIR}/CMakeLists.txt")
    message(FATAL_ERROR
        "godot-cpp not found at: ${GODOT_CPP_DIR}\n"
        "Clone it with: git submodule add https://github.com/godotengine/godot-cpp godot-cpp\n"
        "Or pass -DGODOT_CPP_DIR=<path> to CMake.")
endif()

add_subdirectory("${GODOT_CPP_DIR}" godot-cpp)

# ---------------------------------------------------------------------------
# JSBSim
# ---------------------------------------------------------------------------
if(JSBSIM_ENABLED)
    find_package(JSBSim QUIET)
    if(NOT JSBSim_FOUND)
        # Fallback: look for JSBSim as a submodule
        set(JSBSIM_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../jsbsim"
            CACHE PATH "Path to JSBSim source directory")
        if(EXISTS "${JSBSIM_DIR}/CMakeLists.txt")
            set(JSBSIM_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
            set(JSBSIM_BUILD_CLI OFF CACHE BOOL "" FORCE)
            add_subdirectory("${JSBSIM_DIR}" jsbsim_build)
            set(JSBSIM_LIBRARIES libJSBSim)
            set(JSBSIM_INCLUDE_DIRS "${JSBSIM_DIR}/src")
        else()
            message(WARNING
                "JSBSim not found – building stub (kinematic fallback only).\n"
                "Clone with: git submodule add https://github.com/JSBSim-Team/jsbsim jsbsim")
            set(JSBSIM_ENABLED OFF)
        endif()
    endif()
endif()

# ---------------------------------------------------------------------------
# Extension shared library
# ---------------------------------------------------------------------------
add_library(jsbsim_gdextension SHARED
    src/jsbsim_extension.cpp
    src/jsbsim_extension.h
)

target_include_directories(jsbsim_gdextension PRIVATE
    src/
    ${GODOT_CPP_DIR}/include
    ${GODOT_CPP_DIR}/gen/include
)

target_link_libraries(jsbsim_gdextension PRIVATE godot-cpp)

if(JSBSIM_ENABLED)
    target_compile_definitions(jsbsim_gdextension PRIVATE HAS_JSBSIM)
    target_include_directories(jsbsim_gdextension PRIVATE ${JSBSIM_INCLUDE_DIRS})
    target_link_libraries(jsbsim_gdextension PRIVATE ${JSBSIM_LIBRARIES})
endif()

# ---------------------------------------------------------------------------
# Platform output naming
# ---------------------------------------------------------------------------
set_target_properties(jsbsim_gdextension PROPERTIES
    OUTPUT_NAME "jsbsim_gdextension"
    PREFIX      ""
)

if(WIN32)
    set_target_properties(jsbsim_gdextension PROPERTIES SUFFIX ".dll")
elseif(APPLE)
    set_target_properties(jsbsim_gdextension PROPERTIES SUFFIX ".dylib")
else()
    set_target_properties(jsbsim_gdextension PROPERTIES SUFFIX ".so")
endif()

# ---------------------------------------------------------------------------
# Post-build: copy to Godot bin/ directory
# ---------------------------------------------------------------------------
set(GODOT_BIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../bin" CACHE PATH "Godot extension bin output dir")

add_custom_command(TARGET jsbsim_gdextension POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${GODOT_BIN_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:jsbsim_gdextension> "${GODOT_BIN_DIR}/"
    COMMENT "Copying jsbsim_gdextension to ${GODOT_BIN_DIR}"
)
