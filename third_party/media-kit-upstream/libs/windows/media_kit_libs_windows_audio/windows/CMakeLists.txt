# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)

# This option is read by the other packages which are part of package:media_kit.
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_audio")
project(${PROJECT_NAME} LANGUAGES CXX)

# ------------------------------------------------------------------------------
function(download_and_verify url md5 locationForArchive)
  set(TMP_ARCHIVE "${locationForArchive}.tmp")

  # Check if the archive exists.
  if(EXISTS "${locationForArchive}")
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    # If MD5 doesn't match, delete the archive to download again.
    if("${md5}" STREQUAL "${ARCHIVE_MD5}")
      message(STATUS "${locationForArchive} Verification successful.")
      return()
    else()
      file(REMOVE "${locationForArchive}")
      message(STATUS "MD5 mismatch for ${locationForArchive}. File deleted.")
    endif()
  endif()

  # Download the archive if it doesn't exist.
  if(NOT EXISTS "${locationForArchive}")
    set(DOWNLOAD_OK FALSE)
    foreach(ATTEMPT RANGE 1 3)
      file(REMOVE "${TMP_ARCHIVE}")
      message(STATUS "Downloading archive from ${url} (attempt ${ATTEMPT}/3)...")
      file(
        DOWNLOAD "${url}" "${TMP_ARCHIVE}"
        STATUS DOWNLOAD_STATUS
        TLS_VERIFY ON
        SHOW_PROGRESS
      )
      list(GET DOWNLOAD_STATUS 0 DOWNLOAD_CODE)
      list(GET DOWNLOAD_STATUS 1 DOWNLOAD_MESSAGE)
      if(NOT DOWNLOAD_CODE EQUAL 0)
        message(STATUS "Download failed (${DOWNLOAD_CODE}): ${DOWNLOAD_MESSAGE}")
        continue()
      endif()

      # Verify MD5 of the newly downloaded file.
      file(MD5 "${TMP_ARCHIVE}" ARCHIVE_MD5)
      if("${md5}" STREQUAL "${ARCHIVE_MD5}")
        file(RENAME "${TMP_ARCHIVE}" "${locationForArchive}")
        message(STATUS "${locationForArchive} Verification successful.")
        set(DOWNLOAD_OK TRUE)
        break()
      endif()

      message(STATUS "MD5 mismatch for downloaded archive. Expected ${md5}, got ${ARCHIVE_MD5}.")
    endforeach()

    file(REMOVE "${TMP_ARCHIVE}")
    if(NOT DOWNLOAD_OK)
      message(FATAL_ERROR "${locationForArchive} Integrity check failed after retries.")
    endif()
  endif()
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  # Check if the directory exists
  if(EXISTS "${dir}")
    # Check if the directory is not empty
    file(GLOB dir_contents "${dir}/*")

    if(dir_contents)
      set(${result_var} TRUE PARENT_SCOPE)
    else()
      set(${result_var} FALSE PARENT_SCOPE)
      message(STATUS "Directory ${dir} exists but is empty!")
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
    message(STATUS "Directory ${dir} does not exist!")
  endif()
endfunction()

# Thanks to Mitchel Stewart (https://github.com/Quackdoc) for providing patches to generate minimal libmpv & FFmpeg audio specific builds.

# Detect architecture and set appropriate libmpv archive
if(${FLUTTER_TARGET_PLATFORM} STREQUAL "windows-x64")
  set(LIBMPV_ARCH "x86_64")
  set(LIBMPV "mpv-dev-x86_64-20251213-git-140ec21.7z")
  set(LIBMPV_MD5 "bf77216724f0f290dd14d2b1bc9826df")
else()
  set(LIBMPV_ARCH "aarch64")
  set(LIBMPV "mpv-dev-aarch64-20251213-git-140ec21.7z")
  set(LIBMPV_MD5 "fc3c09cd5bed08db58f888460da9059f")
endif()

# Download URL for the libmpv archive from the latest release
set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-audio-cmake/releases/download/20251213/${LIBMPV}")

# Download location of the libmpv archive.
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")

download_and_verify(
  ${LIBMPV_URL}
  ${LIBMPV_MD5}
  ${LIBMPV_ARCHIVE}
)

check_directory_exists_and_not_empty(${LIBMPV_SRC} LIBMPV_SRC_VALID)

# Find 7zip for extraction (preferred for .7z files)
find_program(SEVENZ_EXECUTABLE NAMES 7z 7za)

# Extract the libmpv archive.
if(NOT LIBMPV_SRC_VALID)
  message(STATUS "Extracting ${LIBMPV}...")
  make_directory("${LIBMPV_SRC}")
  add_custom_target("${PROJECT_NAME}_LIBMPV_EXTRACT" ALL)
  
  if(SEVENZ_EXECUTABLE)
    message(STATUS "Using 7zip for extraction: ${SEVENZ_EXECUTABLE}")
    add_custom_command(
      TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT"
      COMMAND "${SEVENZ_EXECUTABLE}" x -y "\"${LIBMPV_ARCHIVE}\""
      COMMAND xcopy "\"${LIBMPV_SRC}/include/mpv\"" "\"${LIBMPV_SRC}/mpv\"" /E /H /C /I
      COMMAND rmdir "\"${LIBMPV_SRC}/include\"" /S /Q
      COMMAND ren "\"${LIBMPV_SRC}/mpv\"" "\"include\""
      WORKING_DIRECTORY "${LIBMPV_SRC}"
    )
  else()
    message(STATUS "7zip not found, falling back to CMake tar")
    add_custom_command(
      TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT"
      COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${LIBMPV_ARCHIVE}\""
      COMMAND xcopy "\"${LIBMPV_SRC}/include/mpv\"" "\"${LIBMPV_SRC}/mpv\"" /E /H /C /I
      COMMAND rmdir "\"${LIBMPV_SRC}/include\"" /S /Q
      COMMAND ren "\"${LIBMPV_SRC}/mpv\"" "\"include\""
      WORKING_DIRECTORY "${LIBMPV_SRC}"
    )
  endif()
endif()

# ------------------------------------------------------------------------------
set(PLUGIN_NAME "media_kit_libs_windows_audio_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_audio/media_kit_libs_windows_audio_plugin_c_api.h"
  "media_kit_libs_windows_audio_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES
  CXX_VISIBILITY_PRESET
  hidden
)
target_compile_definitions(
  ${PLUGIN_NAME}
  PRIVATE
  FLUTTER_PLUGIN_IMPL
)

target_include_directories(
  ${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(
  ${PLUGIN_NAME}
  PRIVATE
  flutter
  flutter_wrapper_plugin
)

set(
  media_kit_libs_windows_audio_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  PARENT_SCOPE
)
