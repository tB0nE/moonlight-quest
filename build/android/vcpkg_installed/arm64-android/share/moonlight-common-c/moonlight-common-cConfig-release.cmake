#----------------------------------------------------------------
# Generated CMake target import file for configuration "Release".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "moonlight-common-c::moonlight-common-c" for configuration "Release"
set_property(TARGET moonlight-common-c::moonlight-common-c APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(moonlight-common-c::moonlight-common-c PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELEASE "C"
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib/libmoonlight-common-c.a"
  )

list(APPEND _cmake_import_check_targets moonlight-common-c::moonlight-common-c )
list(APPEND _cmake_import_check_files_for_moonlight-common-c::moonlight-common-c "${_IMPORT_PREFIX}/lib/libmoonlight-common-c.a" )

# Import target "moonlight-common-c::enet" for configuration "Release"
set_property(TARGET moonlight-common-c::enet APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(moonlight-common-c::enet PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELEASE "C"
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib/libenet.a"
  )

list(APPEND _cmake_import_check_targets moonlight-common-c::enet )
list(APPEND _cmake_import_check_files_for_moonlight-common-c::enet "${_IMPORT_PREFIX}/lib/libenet.a" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
