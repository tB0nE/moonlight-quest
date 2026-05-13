#----------------------------------------------------------------
# Generated CMake target import file for configuration "Debug".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "unofficial::godot::cpp" for configuration "Debug"
set_property(TARGET unofficial::godot::cpp APPEND PROPERTY IMPORTED_CONFIGURATIONS DEBUG)
set_target_properties(unofficial::godot::cpp PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_DEBUG "CXX"
  IMPORTED_LOCATION_DEBUG "${_IMPORT_PREFIX}/debug/lib/libgodot-cpp.android.arm64-v8a.template_debug.arm64.a"
  )

list(APPEND _cmake_import_check_targets unofficial::godot::cpp )
list(APPEND _cmake_import_check_files_for_unofficial::godot::cpp "${_IMPORT_PREFIX}/debug/lib/libgodot-cpp.android.arm64-v8a.template_debug.arm64.a" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
