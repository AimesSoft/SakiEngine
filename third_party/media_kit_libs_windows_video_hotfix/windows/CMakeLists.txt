# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright (c) 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)

# This option is read by the other packages which are part of package:media_kit.
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

# Deal with MSVC incompatibility.
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

set(MEDIA_KIT_DOWNLOAD_TIMEOUT_SECONDS "180")
if(DEFINED ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_DOWNLOAD_TIMEOUT_SECONDS} AND NOT "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_DOWNLOAD_TIMEOUT_SECONDS}" STREQUAL "")
  set(MEDIA_KIT_DOWNLOAD_TIMEOUT_SECONDS "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_DOWNLOAD_TIMEOUT_SECONDS}")
endif()

set(MEDIA_KIT_DOWNLOAD_INACTIVITY_TIMEOUT_SECONDS "30")
if(DEFINED ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_DOWNLOAD_INACTIVITY_TIMEOUT_SECONDS} AND NOT "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_DOWNLOAD_INACTIVITY_TIMEOUT_SECONDS}" STREQUAL "")
  set(MEDIA_KIT_DOWNLOAD_INACTIVITY_TIMEOUT_SECONDS "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_DOWNLOAD_INACTIVITY_TIMEOUT_SECONDS}")
endif()

set(MEDIA_KIT_DOWNLOAD_RETRY_COUNT "2")
if(DEFINED ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_DOWNLOAD_RETRY_COUNT} AND NOT "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_DOWNLOAD_RETRY_COUNT}" STREQUAL "")
  set(MEDIA_KIT_DOWNLOAD_RETRY_COUNT "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_DOWNLOAD_RETRY_COUNT}")
endif()
if(MEDIA_KIT_DOWNLOAD_RETRY_COUNT LESS 1)
  set(MEDIA_KIT_DOWNLOAD_RETRY_COUNT "1")
endif()

function(first_existing_path outputVar)
  set(FOUND_PATH "")
  foreach(candidatePath IN LISTS ARGN)
    if(NOT "${candidatePath}" STREQUAL "" AND EXISTS "${candidatePath}")
      set(FOUND_PATH "${candidatePath}")
      break()
    endif()
  endforeach()
  set(${outputVar} "${FOUND_PATH}" PARENT_SCOPE)
endfunction()

function(resolve_saki_media_kit_prebuilt_dir resultVar)
  set(PREBUILT_DIR "")
  if(DEFINED SAKI_MEDIA_KIT_WINDOWS_PREBUILT_DIR AND NOT "${SAKI_MEDIA_KIT_WINDOWS_PREBUILT_DIR}" STREQUAL "")
    set(PREBUILT_DIR "${SAKI_MEDIA_KIT_WINDOWS_PREBUILT_DIR}")
  elseif(DEFINED ENV{SAKI_MEDIA_KIT_WINDOWS_PREBUILT_DIR} AND NOT "$ENV{SAKI_MEDIA_KIT_WINDOWS_PREBUILT_DIR}" STREQUAL "")
    set(PREBUILT_DIR "$ENV{SAKI_MEDIA_KIT_WINDOWS_PREBUILT_DIR}")
  else()
    get_filename_component(PACKAGE_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
    set(PREBUILT_DIR "${PACKAGE_ROOT_DIR}/prebuilt")
  endif()
  set(${resultVar} "${PREBUILT_DIR}" PARENT_SCOPE)
endfunction()

function(find_archive_in_workspace_cache archiveFileName resultVar)
  set(ARCHIVE_CANDIDATES "")

  get_filename_component(REPO_ROOT_FROM_GAME_LAYOUT "${CMAKE_BINARY_DIR}/../../../../.." ABSOLUTE)
  get_filename_component(REPO_ROOT_FROM_ENGINE_LAYOUT "${CMAKE_BINARY_DIR}/../../../.." ABSOLUTE)

  file(
    GLOB GAME_LAYOUT_ARCHIVES
    "${REPO_ROOT_FROM_GAME_LAYOUT}/Game/*/build/windows/x64/${archiveFileName}"
    "${REPO_ROOT_FROM_GAME_LAYOUT}/Engine/build/windows/x64/${archiveFileName}"
  )
  file(
    GLOB ENGINE_LAYOUT_ARCHIVES
    "${REPO_ROOT_FROM_ENGINE_LAYOUT}/Game/*/build/windows/x64/${archiveFileName}"
    "${REPO_ROOT_FROM_ENGINE_LAYOUT}/Engine/build/windows/x64/${archiveFileName}"
  )

  list(APPEND ARCHIVE_CANDIDATES ${GAME_LAYOUT_ARCHIVES})
  list(APPEND ARCHIVE_CANDIDATES ${ENGINE_LAYOUT_ARCHIVES})
  list(REMOVE_DUPLICATES ARCHIVE_CANDIDATES)

  if(ARCHIVE_CANDIDATES)
    list(GET ARCHIVE_CANDIDATES 0 FIRST_ARCHIVE_CANDIDATE)
    set(${resultVar} "${FIRST_ARCHIVE_CANDIDATE}" PARENT_SCOPE)
  else()
    set(${resultVar} "" PARENT_SCOPE)
  endif()
endfunction()

# ------------------------------------------------------------------------------
function(copy_archive_override_and_verify localArchivePath md5 locationForArchive archiveLabel)
  if(NOT "${localArchivePath}" STREQUAL "")
    if(NOT EXISTS "${localArchivePath}")
      message(FATAL_ERROR "Local archive override not found for ${archiveLabel}: ${localArchivePath}")
    endif()

    configure_file("${localArchivePath}" "${locationForArchive}" COPYONLY)

    file(MD5 "${locationForArchive}" ARCHIVE_MD5)
    if(NOT md5 STREQUAL ARCHIVE_MD5)
      file(REMOVE "${locationForArchive}")
      message(FATAL_ERROR "Local archive override MD5 mismatch for ${archiveLabel}. expected=${md5}, actual=${ARCHIVE_MD5}, path=${localArchivePath}")
    endif()

    message(STATUS "Using local archive override for ${archiveLabel}: ${localArchivePath}")
  endif()
endfunction()

function(download_and_verify urlCandidates md5 locationForArchive archiveLabel)
  # Check if the archive exists.
  if(EXISTS "${locationForArchive}")
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    # If MD5 doesn't match, delete the archive to download again.
    if(NOT md5 STREQUAL ARCHIVE_MD5)
      file(REMOVE "${locationForArchive}")
      message(STATUS "MD5 mismatch. File deleted.")
    endif()
  endif()

  # Download the archive if it doesn't exist.
  if(NOT EXISTS "${locationForArchive}")
    set(URL_CANDIDATES "${urlCandidates}")
    set(DOWNLOAD_SUCCESS FALSE)
    math(EXPR RETRY_INDEX_MAX "${MEDIA_KIT_DOWNLOAD_RETRY_COUNT} - 1")

    foreach(url IN LISTS URL_CANDIDATES)
      if(DOWNLOAD_SUCCESS)
        break()
      endif()

      foreach(retryIndex RANGE 0 ${RETRY_INDEX_MAX})
        if(DOWNLOAD_SUCCESS)
          break()
        endif()

        math(EXPR humanTry "${retryIndex} + 1")
        message(STATUS "Downloading ${archiveLabel} from ${url} (attempt ${humanTry}/${MEDIA_KIT_DOWNLOAD_RETRY_COUNT})...")
        file(
          DOWNLOAD "${url}" "${locationForArchive}"
          SHOW_PROGRESS
          TIMEOUT ${MEDIA_KIT_DOWNLOAD_TIMEOUT_SECONDS}
          INACTIVITY_TIMEOUT ${MEDIA_KIT_DOWNLOAD_INACTIVITY_TIMEOUT_SECONDS}
          STATUS DOWNLOAD_STATUS
          LOG DOWNLOAD_LOG
        )
        list(GET DOWNLOAD_STATUS 0 DOWNLOAD_STATUS_CODE)
        list(GET DOWNLOAD_STATUS 1 DOWNLOAD_STATUS_MESSAGE)

        if(NOT DOWNLOAD_STATUS_CODE EQUAL 0)
          # Prevent future builds from reusing a zero-byte/partial archive.
          file(REMOVE "${locationForArchive}")
          message(WARNING "Download failed from ${url}. code=${DOWNLOAD_STATUS_CODE}, message=${DOWNLOAD_STATUS_MESSAGE}")
          continue()
        endif()

        # Verify MD5 of the downloaded file.
        file(MD5 "${locationForArchive}" ARCHIVE_MD5)
        if(md5 STREQUAL ARCHIVE_MD5)
          set(DOWNLOAD_SUCCESS TRUE)
          message(STATUS "${locationForArchive} Verification successful.")
        else()
          file(REMOVE "${locationForArchive}")
          message(WARNING "${archiveLabel} integrity check failed for ${url}. expected=${md5}, actual=${ARCHIVE_MD5}")
        endif()
      endforeach()
    endforeach()

    if(NOT DOWNLOAD_SUCCESS)
      message(FATAL_ERROR "Failed to download ${archiveLabel} from all candidates. Last error was printed above.")
    endif()
  endif()
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  # Check if the directory exists.
  if(EXISTS "${dir}")
    # Check if the directory is not empty.
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

# libmpv archive containing the pre-built shared libraries & headers.
set(LIBMPV "mpv-dev-x86_64-20230924-git-652a1dd.7z")

# Download URL & MD5 hash of the libmpv archive.
set(LIBMPV_DEFAULT_URL "https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/${LIBMPV}")
set(LIBMPV_FALLBACK_URL "https://ghproxy.com/${LIBMPV_DEFAULT_URL}")
set(LIBMPV_URL_CANDIDATES "${LIBMPV_DEFAULT_URL};${LIBMPV_FALLBACK_URL}")
if(DEFINED ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_LIBMPV_URL} AND NOT "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_LIBMPV_URL}" STREQUAL "")
  set(LIBMPV_URL_CANDIDATES "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_LIBMPV_URL};${LIBMPV_URL_CANDIDATES}")
endif()
set(LIBMPV_MD5 "a832ef24b3a6ff97cd2560b5b9d04cd8")

# Download location of the libmpv archive.
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")
set(LIBMPV_ARCHIVE_OVERRIDE "")
resolve_saki_media_kit_prebuilt_dir(SAKI_MEDIA_KIT_WINDOWS_PREBUILT_DIR_RESOLVED)
if(DEFINED ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_LIBMPV_ARCHIVE} AND NOT "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_LIBMPV_ARCHIVE}" STREQUAL "")
  set(LIBMPV_ARCHIVE_OVERRIDE "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_LIBMPV_ARCHIVE}")
endif()
set(LIBMPV_PREBUILT_ARCHIVE "${SAKI_MEDIA_KIT_WINDOWS_PREBUILT_DIR_RESOLVED}/${LIBMPV}")
set(LIBMPV_WORKSPACE_CACHE_ARCHIVE "")
find_archive_in_workspace_cache("${LIBMPV}" LIBMPV_WORKSPACE_CACHE_ARCHIVE)
if("${LIBMPV_ARCHIVE_OVERRIDE}" STREQUAL "")
  first_existing_path(
    LIBMPV_ARCHIVE_OVERRIDE
    "${LIBMPV_PREBUILT_ARCHIVE}"
    "${LIBMPV_WORKSPACE_CACHE_ARCHIVE}"
  )
endif()

copy_archive_override_and_verify(
  "${LIBMPV_ARCHIVE_OVERRIDE}"
  ${LIBMPV_MD5}
  "${LIBMPV_ARCHIVE}"
  "libmpv archive"
)

download_and_verify(
  "${LIBMPV_URL_CANDIDATES}"
  ${LIBMPV_MD5}
  "${LIBMPV_ARCHIVE}"
  "libmpv archive"
)

check_directory_exists_and_not_empty(${LIBMPV_SRC} LIBMPV_SRC_VALID)

# Extract the libmpv archive.
if(NOT LIBMPV_SRC_VALID)
  message(STATUS "Extracting ${LIBMPV}...")
  make_directory("${LIBMPV_SRC}")
  add_custom_target("${PROJECT_NAME}_LIBMPV_EXTRACT" ALL)
  add_custom_command(
    TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT"
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${LIBMPV_ARCHIVE}\""
    COMMAND xcopy "\"${LIBMPV_SRC}/include/mpv\"" "\"${LIBMPV_SRC}/mpv\"" /E /H /C /I
    COMMAND rmdir "\"${LIBMPV_SRC}/include\"" /S /Q
    COMMAND ren "\"${LIBMPV_SRC}/mpv\"" "\"include\""
    WORKING_DIRECTORY "${LIBMPV_SRC}"
  )
endif()

# ------------------------------------------------------------------------------

# ANGLE archive containing the pre-built shared libraries & headers.
set(ANGLE "ANGLE.7z")

# Download URL & MD5 hash of the ANGLE archive.
set(ANGLE_DEFAULT_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z")
set(ANGLE_FALLBACK_URL "https://ghproxy.com/${ANGLE_DEFAULT_URL}")
set(ANGLE_URL_CANDIDATES "${ANGLE_DEFAULT_URL};${ANGLE_FALLBACK_URL}")
if(DEFINED ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_ANGLE_URL} AND NOT "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_ANGLE_URL}" STREQUAL "")
  set(ANGLE_URL_CANDIDATES "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_ANGLE_URL};${ANGLE_URL_CANDIDATES}")
endif()
set(ANGLE_MD5 "e866f13e8d552348058afaafe869b1ed")

# Download location of the ANGLE archive.
set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")
set(ANGLE_ARCHIVE_OVERRIDE "")
set(ANGLE_REPO_LOCAL_ARCHIVE "${CMAKE_CURRENT_SOURCE_DIR}/ANGLE.7z")
set(ANGLE_PREBUILT_ARCHIVE "${SAKI_MEDIA_KIT_WINDOWS_PREBUILT_DIR_RESOLVED}/${ANGLE}")
set(ANGLE_WORKSPACE_CACHE_ARCHIVE "")
find_archive_in_workspace_cache("${ANGLE}" ANGLE_WORKSPACE_CACHE_ARCHIVE)
if(EXISTS "${ANGLE_REPO_LOCAL_ARCHIVE}")
  set(ANGLE_ARCHIVE_OVERRIDE "${ANGLE_REPO_LOCAL_ARCHIVE}")
endif()
if("${ANGLE_ARCHIVE_OVERRIDE}" STREQUAL "")
  first_existing_path(
    ANGLE_ARCHIVE_OVERRIDE
    "${ANGLE_PREBUILT_ARCHIVE}"
    "${ANGLE_WORKSPACE_CACHE_ARCHIVE}"
  )
endif()
if(DEFINED ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_ANGLE_ARCHIVE} AND NOT "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_ANGLE_ARCHIVE}" STREQUAL "")
  set(ANGLE_ARCHIVE_OVERRIDE "$ENV{MEDIA_KIT_LIBS_WINDOWS_VIDEO_ANGLE_ARCHIVE}")
endif()

copy_archive_override_and_verify(
  "${ANGLE_ARCHIVE_OVERRIDE}"
  ${ANGLE_MD5}
  "${ANGLE_ARCHIVE}"
  "ANGLE archive"
)

download_and_verify(
  "${ANGLE_URL_CANDIDATES}"
  ${ANGLE_MD5}
  "${ANGLE_ARCHIVE}"
  "ANGLE archive"
)

check_directory_exists_and_not_empty(${ANGLE_SRC} ANGLE_SRC_VALID)

# Extract the ANGLE archive.
if(NOT ANGLE_SRC_VALID)
  message(STATUS "Extracting ${ANGLE}...")
  make_directory("${ANGLE_SRC}")
  add_custom_target("${PROJECT_NAME}_ANGLE_EXTRACT" ALL)
  add_custom_command(
    TARGET "${PROJECT_NAME}_ANGLE_EXTRACT"
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${ANGLE_ARCHIVE}\""
    WORKING_DIRECTORY "${ANGLE_SRC}"
  )
endif()

# ------------------------------------------------------------------------------
set(PLUGIN_NAME "media_kit_libs_windows_video_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h"
  "media_kit_libs_windows_video_plugin_c_api.cpp"
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
  media_kit_libs_windows_video_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  "${ANGLE_SRC}/d3dcompiler_47.dll"
  "${ANGLE_SRC}/libEGL.dll"
  "${ANGLE_SRC}/libGLESv2.dll"
  "${ANGLE_SRC}/vk_swiftshader.dll"
  "${ANGLE_SRC}/vulkan-1.dll"
  "${ANGLE_SRC}/zlib.dll"
  PARENT_SCOPE
)
