#----------------------------------------------------------------
# Generated CMake target import file for configuration "Debug".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "moonlight-common-c::moonlight-common-c" for configuration "Debug"
set_property(TARGET moonlight-common-c::moonlight-common-c APPEND PROPERTY IMPORTED_CONFIGURATIONS DEBUG)
set_target_properties(moonlight-common-c::moonlight-common-c PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_DEBUG "C"
  IMPORTED_LOCATION_DEBUG "${_IMPORT_PREFIX}/debug/lib/libmoonlight-common-c.a"
  )

list(APPEND _cmake_import_check_targets moonlight-common-c::moonlight-common-c )
list(APPEND _cmake_import_check_files_for_moonlight-common-c::moonlight-common-c "${_IMPORT_PREFIX}/debug/lib/libmoonlight-common-c.a" )

# Import target "moonlight-common-c::enet" for configuration "Debug"
set_property(TARGET moonlight-common-c::enet APPEND PROPERTY IMPORTED_CONFIGURATIONS DEBUG)
set_target_properties(moonlight-common-c::enet PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_DEBUG "C"
  IMPORTED_LOCATION_DEBUG "${_IMPORT_PREFIX}/debug/lib/libenet.a"
  )

list(APPEND _cmake_import_check_targets moonlight-common-c::enet )
list(APPEND _cmake_import_check_files_for_moonlight-common-c::enet "${_IMPORT_PREFIX}/debug/lib/libenet.a" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
