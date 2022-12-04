# Copyright (c) 2022, Cedric Velandres
# SPDX-License-Identifier: MIT

include_guard(GLOBAL)
if(__KCONFIG_CMAKE_INCLUDE_GUARD__)
    return()
endif()
set(__KCONFIG_CMAKE_INCLUDE_GUARD__ TRUE)

# Minimum version
cmake_minimum_required(VERSION 3.19)

# Module needs git
find_package(Git)
if(NOT GIT_FOUND)
    message(FATAL_ERROR "Could not find Git")
endif()

# scripts needs python (and prefer python3)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# #######################################################################
# kconfig_check_variable <name> <message>
#
# Helper macro to check if variable is set
# name: variable name
# message: error message
function(kconfig_check_variable name message)
    if(NOT ${name})
        message(FATAL_ERROR "${name} not set, ${message}")
    endif()
endfunction()

# #######################################################################
# kconfig_default_variable <name> <default>
#
# Helper macro to set default values to variables
# name: variable name
# default: default value
macro(kconfig_default_variable name default)
    if(NOT DEFINED ${name})
        set(${name} "${default}")
        message(DEBUG "${name} not set, defaulting to ${default}")
    endif()
endmacro()

# #######################################################################
# kconfig_make_directory <path>
#
# Helper macro to create directories
# path: path to root kconfig
macro(kconfig_make_directory path)
    # Create parent directory, since genconfig does not create it
    get_filename_component(parent_dir "${path}" DIRECTORY)
    file(MAKE_DIRECTORY "${parent_dir}")
endmacro()

# #######################################################################
# kconfig_find_bin <paths> <name> <bin [...]>
#
# Finds program with name bin... and stores it to name
# paths: program path to search
# name: variable name to store path to program
# bin...: binary to find
macro(kconfig_find_bin paths name bin)
    message(CHECK_START "Finding ${bin}")

    if(NOT ${name})
        find_program(${name} NAMES ${bin} ${ARGN} PATHS ${paths} HINTS ${paths} )

        if(NOT ${name})
            set(${name}_FOUND 0)
            message(CHECK_FAIL "not found")
        else()
            set(${name}_FOUND 1)
            message(CHECK_PASS "found: ${${name}}")
        endif()
    elseif(NOT EXISTS "${${name}}")
        set(${name}_FOUND 0)
        message(CHECK_FAIL "not found")
    else()
        set(${name}_FOUND 1)
        message(CHECK_PASS "found: ${${name}}")
    endif()
endmacro()

# #######################################################################
# kconfig_build_tools <build_dir>
#
# Builds the needed tools by kconfig
# build_dir: directory to place tools
function(kconfig_build_tools repo_link build_dir)

    message(DEBUG "kconfig_build_tools")
    message(DEBUG "   build_dir: ${build_dir}")
    message(DEBUG "   git_repo:  ${repo_link}")
    set(_build_dir ${KCONFIG_BINARY_DIR}/kbuild-standalone)

    if(NOT EXISTS ${_build_dir})
        # clone kbuild-standalone
        execute_process(
            COMMAND ${GIT_EXECUTABLE} clone --depth 1 ${repo_link} ${_build_dir}
            WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
            RESULT_VARIABLE ret)
        if(NOT "${ret}" STREQUAL "0")
            message(FATAL_ERROR "Could not clone kbuild-standalone: ${ret}")
        endif()
    endif()

    # create output dir
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E make_directory "${build_dir}"
        WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
        RESULT_VARIABLE ret)
    if(NOT "${ret}" STREQUAL "0")
        message(FATAL_ERROR "Could not build kbuild-standalone: ${ret}")
    endif()

    # build tools
    execute_process(
        COMMAND make -f ${_build_dir}/Makefile.sample O=${build_dir} -j
        WORKING_DIRECTORY "${_build_dir}"
        RESULT_VARIABLE ret)
    if(NOT "${ret}" STREQUAL "0")
        message(FATAL_ERROR "Could not build kbuild-standalone: ${ret}")
    endif()

    # clean up kbuild sources
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E rm -r "${_build_dir}"
        WORKING_DIRECTORY "${KCONFIG_BINARY_DIR}"
        RESULT_VARIABLE ret)
    if(NOT "${ret}" STREQUAL "0")
        message(FATAL_ERROR "Could not build kbuild-standalone: ${ret}")
    endif()
endfunction()

# #######################################################################
# kconfig_defconfig <kconfig_file> <defconfig> <dotconfig> <autoheader> <autoconf> <tristate>
#
# Generate .config from given defconfig
# kconfig_file: path to root kconfig
# defconfig: path to defconfig
# dotconfig: path to .config
# autoheader: path to write "autoconf.h"
# autoconf: path to write "auto.conf" file
# tristate: path to write "tristate.conf"
function(kconfig_defconfig kconfig_file defconfig dotconfig autoheader autoconf tristate)
    message(DEBUG "kconfig_defconfig:")
    message(DEBUG "\t KCONFIG:            ${kconfig_file}")
    message(DEBUG "\t DEFCONFIG:          ${defconfig}")
    message(DEBUG "\t KCONFIG_CONFIG:     ${dotconfig}")
    message(DEBUG "\t KCONFIG_AUTOHEADER: ${autoheader}")
    message(DEBUG "\t KCONFIG_AUTOCONFIG: ${autoconf}")
    message(DEBUG "\t KCONFIG_TRISTATE:   ${tristate}")
    execute_process(COMMAND
        ${CMAKE_COMMAND} -E env
        KCONFIG_AUTOHEADER=${autoheader}
        KCONFIG_AUTOCONFIG=${autoconf}
        KCONFIG_TRISTATE=${tristate}
        KCONFIG_CONFIG=${dotconfig}
        CONFIG_=${KCONFIG_CONFIG_PREFIX}
        ${KCONFIG_CONF_BIN}
        -s
        --defconfig ${defconfig}
        ${kconfig_file}
        WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
        RESULT_VARIABLE ret
    )

    if(NOT "${ret}" STREQUAL "0")
        message(FATAL_ERROR "could not create initial .config: ${ret}")
    endif()
endfunction()

# #######################################################################
# kconfig_merge_kconfigs <merged_path> <source_prop>
#
# Generate merged root kconfig for all kconfig in project added via kconfig_add_kconfig
# merged_path: path to write merged kconfig
# source_prop: name of global property holding all kconfig paths
function(kconfig_merge_kconfigs merged_path source_var)
    message(DEBUG "kconfig_merge_kconfigs:")
    message(STATUS "Generating merged Kconfig:")
    message(DEBUG "\t merged_path:     ${merged_path}")
    message(DEBUG "\t source_var:      ${source_var}")
    get_property(kconfig_sources GLOBAL PROPERTY ${source_var})
    message(DEBUG "\t kconfig_sources: ${kconfig_sources}")
    execute_process(COMMAND
        ${CMAKE_COMMAND} -E env
        ${Python3_EXECUTABLE}
        ${KCONFIG_MERGE_PYBIN}
        --silent
        --kconfig ${merged_path}
        --title ${PROJECT_NAME}
        --sources ${kconfig_sources}
        WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
        RESULT_VARIABLE ret
    )

    if(NOT "${ret}" STREQUAL "0")
        message(FATAL_ERROR "error during kconfig merge: ${ret}")
    endif()
endfunction()

# #######################################################################
# kconfig_create_fragment <config_list> <cache_fragment>
# 
# Parse cmake cache variables for cli given kconfig settings
# config_list: list storing cache config key=value
# cache_fragment file to write config fragment
# 
function(kconfig_create_fragment config_list cache_fragment)
    message(STATUS "Generating cache kconfig fragment: ${cache_fragment}")
    message(DEBUG "kconfig_create_fragment:")
    message(DEBUG "\t config_list:  ${config_list}")
    message(DEBUG "\t cache_fragment: ${cache_fragment}")

    file(WRITE ${cache_fragment} ${${config_list}})
endfunction()

# #######################################################################
# kconfig_import_cache_variables <config_prefix> <cache_fragment> <config_list>
#
# Parse cmake cache variables for cli given kconfig settings
# config_prefix config prefix
# config_list: variable store cache config keys
function(kconfig_import_cache_variables config_prefix config_list)
    message(DEBUG "kconfig_import_cache_variables:")
    message(DEBUG "\t config_prefix:  ${config_prefix}")
    get_cmake_property(cache_variables CACHE_VARIABLES)

    foreach(var ${cache_variables})
        if("${var}" MATCHES "^${config_prefix}")
            list(APPEND _kconfig_cache "${var}=${${var}}\n")
            # unset the cache config, will create a config fragment instead
            unset(${var} CACHE)
        endif()
    endforeach()

    set(${config_list} ${_kconfig_cache} PARENT_SCOPE)
endfunction()

# #######################################################################
# kconfig_parse_defconfig <config_prefix> <config_file> <config_list> <cache>
#
# Parse kconfig defconfig and import all config to cmake variable namespace
# config_prefix config prefix in file
# config_file file to parse
# config_list will contain all configs parsed from file
# cache controls whether keys are declared as cache variable
function(kconfig_import_config config_prefix config_file config_list cache)
    # Imports defconfig with format CONFIG_* to cmake variables
    # ie. CONFIG_OPTION_X=y -> set(CONFIG_OPTION_X "ON")
    # ie. CONFIG_OPTION_X=n -> set(CONFIG_OPTION_X "OFF")
    message(DEBUG "kconfig_import_config")
    message(DEBUG "   config_prefix: ${config_prefix}")
    message(DEBUG "   config_file:   ${config_file}")
    message(DEBUG "   config_list:   ${config_list}")
    message(DEBUG "   cache:         ${cache}")
    file(STRINGS ${config_file} DEFCONFIG_LIST)

    foreach(CONFIG ${DEFCONFIG_LIST})
        # each CONFIG line should look like: <PREFIX>_OPTION=y
        if("${CONFIG}" MATCHES "^#[ \t\r\n]*([^ ]+) is not set")
            set(CONFIG_NAME "${CMAKE_MATCH_1}")
            set(CONFIG_VALUE "N")
        elseif("${CONFIG}" MATCHES "^([^=]+)=(.+)$")
            set(CONFIG_NAME "${CMAKE_MATCH_1}")
            set(CONFIG_VALUE "${CMAKE_MATCH_2}")
        else()
            # skip comments
            continue()
        endif()

        string(TOUPPER "${CONFIG_VALUE}" CONFIG_VALUE)
        message(DEBUG "\t ${CONFIG_NAME}: ${CONFIG_VALUE}")

        # Convert Y -> ON, N -> OFF
        if("${CONFIG_VALUE}" MATCHES "Y")
            set(CONFIG_VALUE ON)
        elseif("${CONFIG_VALUE}" MATCHES "N")
            set(CONFIG_VALUE OFF)
        endif()

        set("${CONFIG_NAME}" ${CONFIG_VALUE} PARENT_SCOPE)

        # add to list
        list(APPEND CONFIG_DEFCONFIG_LIST "${CONFIG_NAME}")
    endforeach()

    # # set config list
    set(${config_list} ${CONFIG_DEFCONFIG_LIST} PARENT_SCOPE)
endfunction()

# #######################################################################
# kconfig_add_kconfig <kconfig_file>
#
# add kconfig file to project
# kconfig_file: path to kconfig file to add
function(kconfig_add_kconfig kconfig_file)
    message(DEBUG "kconfig_add_kconfig")
    message(DEBUG "   kconfig_file:   ${kconfig_file}")

    if(NOT IS_ABSOLUTE ${kconfig_file})
        set(_kconfig_file "${CMAKE_CURRENT_SOURCE_DIR}/${kconfig_file}")
    else()
        set(_kconfig_file "${kconfig_file}")
    endif()

    # add kconfig file to project
    set_property(GLOBAL APPEND PROPERTY KCONFIG_CONFIG_SOURCES "${_kconfig_file}")

    # reconfigure cmake when kconfig file changes
    set_property(GLOBAL APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_kconfig_file}")
endfunction()

# #######################################################################
# kconfig_add_target <target>
#
# setup target with kconfig
# target: target to configure
function(kconfig_add_target target)
    message(DEBUG "kconfig_add_target")
    message(DEBUG "   target:   ${target}")

    # add target to list of kconfig targets
    set_property(GLOBAL APPEND PROPERTY KCONFIG_TARGETS "${target}")
endfunction()

# #######################################################################
# kconfig_configure_targets <config_keys>
#
# setup target with kconfig
# keys to configure targets: target to configure
function(kconfig_configure_targets config_keys)
    message(DEBUG "kconfig_configure_targets")
    message(DEBUG "   config_keys:   ${config_keys}")
    get_property(_kconfig_targets GLOBAL PROPERTY KCONFIG_TARGETS)
    message(DEBUG "   targets:   ${_kconfig_targets}")

    foreach(tgt ${_kconfig_targets})
        foreach(key ${KCONFIG_KEYS})
            set_target_properties(${tgt} PROPERTIES ${key} ${${key}})
        endforeach()

        # if preinclude is enabled
        if(KCONFIG_PREINCLUDE_AUTOCONF)
            target_precompile_headers(${tgt} PUBLIC "${KCONFIG_AUTOHEADER_PATH}")
        endif()
    endforeach()
endfunction()

# #######################################################################
# kconfig_oldconfig <kconfig_root> <dotconfig> <autoheader> <autoconf> <tristate>
#
# kconfig_file: path to root kconfig
# dotconfig: path to .config
# autoheader: path to write "autoconf.h"
# autoconf: path to write "auto.conf" file
# tristate: path to write "tristate.conf"
function(kconfig_oldconfig kconfig_file dotconfig autoheader autoconf tristate)
    message(DEBUG "kconfig_oldconfig:")
    message(DEBUG "\t KCONFIG:            ${kconfig_file}")
    message(DEBUG "\t KCONFIG_CONFIG:     ${dotconfig}")
    message(DEBUG "\t KCONFIG_AUTOHEADER: ${autoheader}")
    message(DEBUG "\t KCONFIG_AUTOCONFIG: ${autoconf}")
    message(DEBUG "\t KCONFIG_TRISTATE:   ${tristate}")

    execute_process(COMMAND
        ${CMAKE_COMMAND} -E env
        KCONFIG_AUTOHEADER=${autoheader}
        KCONFIG_AUTOCONFIG=${autoconf}
        KCONFIG_TRISTATE=${tristate}
        KCONFIG_CONFIG=${dotconfig}
        CONFIG_=${KCONFIG_CONFIG_PREFIX}
        ${KCONFIG_CONF_BIN}
        --syncconfig
        ${kconfig_file}
        WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
        RESULT_VARIABLE ret
    )

    if(NOT "${ret}" STREQUAL "0")
        message(FATAL_ERROR "could not generate config header: ${ret}")
    endif()
endfunction()

# #######################################################################
# Kconfig setup

# Check defaults for variable
kconfig_default_variable(KCONFIG_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}")
kconfig_default_variable(KCONFIG_BINARY_DIR "${CMAKE_BINARY_DIR}/Kconfig")
kconfig_default_variable(KCONFIG_KBUILD_DIR "${KCONFIG_BINARY_DIR}/tools")
kconfig_default_variable(KCONFIG_CONFIGS_DIR "${CMAKE_SOURCE_DIR}/configs")
kconfig_default_variable(KCONFIG_CONFIG_PREFIX "CONFIG_")
kconfig_default_variable(KCONFIG_CONFIG_FRAGMENT_DIR "${KCONFIG_BINARY_DIR}/fragments")
kconfig_default_variable(KCONFIG_TRISTATE_PATH "${KCONFIG_BINARY_DIR}/include/config/tristate.conf")
kconfig_default_variable(KCONFIG_AUTOCONFIG_PATH "${KCONFIG_BINARY_DIR}/include/config/auto.conf")
kconfig_default_variable(KCONFIG_AUTOHEADER_PATH "${KCONFIG_BINARY_DIR}/include/generated/config.h")
kconfig_default_variable(KCONFIG_MERGED_KCONFIG_PATH "${KCONFIG_BINARY_DIR}/Kconfig")
kconfig_default_variable(KCONFIG_DOTCONFIG_PATH "${KCONFIG_BINARY_DIR}/.config")
kconfig_default_variable(KCONFIG_PREINCLUDE_AUTOCONF ON)
kconfig_default_variable(KCONFIG_NO_BUILD_TOOLS OFF)
kconfig_default_variable(KBUILD_STANDALONE_GIT_REPO "https://github.com/ccvelandres/kbuild-standalone")

# Create paths
file(MAKE_DIRECTORY ${KCONFIG_BINARY_DIR})
kconfig_make_directory(KCONFIG_CONFIG_FRAGMENT_DIR)
kconfig_make_directory(KCONFIG_TRISTATE_PATH)
kconfig_make_directory(KCONFIG_AUTOCONFIG_PATH)
kconfig_make_directory(KCONFIG_AUTOHEADER_PATH)
kconfig_make_directory(KCONFIG_MERGED_KCONFIG_PATH)
kconfig_make_directory(KCONFIG_DOTCONFIG_PATH)

# Search for kconfig-* binaries
kconfig_find_bin("${KCONFIG_KBUILD_DIR}" KCONFIG_CONF_BIN kconfig-conf conf )
kconfig_find_bin("${KCONFIG_KBUILD_DIR}" KCONFIG_MCONF_BIN kconfig-mconf mconf )

# Check if binaries are found
if(NOT KCONFIG_CONF_BIN_FOUND OR NOT KCONFIG_MCONF_BIN_FOUND )
    if(KCONFIG_NO_BUILD_TOOLS)
        message(FATAL_ERROR "Kconfig binaries not found, try setting KCONFIG_KBUILD_DIR")
    else()
        message(WARNING "Kconfig binaries not found, try setting KCONFIG_KBUILD_DIR")
        message(STATUS "Trying to build tools...")
        kconfig_build_tools("${KBUILD_STANDALONE_GIT_REPO}" ${KCONFIG_KBUILD_DIR})
        kconfig_find_bin("${KCONFIG_KBUILD_DIR}/kconfig" KCONFIG_CONF_BIN conf )
        kconfig_find_bin("${KCONFIG_KBUILD_DIR}/kconfig" KCONFIG_MCONF_BIN mconf )
    endif()
endif()

# Verify if vars are set
kconfig_check_variable(KCONFIG_CONF_BIN "Could not find conf binary")
kconfig_check_variable(KCONFIG_MCONF_BIN "Could not find mconf binary")

# set config path
if(NOT DEFINED KCONFIG_DEFCONFIG)
    set(KCONFIG_DEFCONFIG "${KCONFIG_CONFIGS_DIR}/defconfig")
    message(DEBUG "KCONFIG_DEFCONFIG not set, defaulting to ${KCONFIG_DEFCONFIG}")
else()
    set(KCONFIG_DEFCONFIG "${KCONFIG_CONFIGS_DIR}/${KCONFIG_DEFCONFIG}")
    message(DEBUG "Using config: ${KCONFIG_DEFCONFIG}")
endif()

# check if KCONFIG_DEFCONFIG exists
if(NOT EXISTS "${KCONFIG_DEFCONFIG}")
    message(FATAL_ERROR "KCONFIG_DEFCONFIG does not exist")
endif()

# preinclude autoconf header if enabled
if(KCONFIG_PREINCLUDE_AUTOCONF)
    message(STATUS "Preincluding autoconf header to kconfig targets...")
endif()

include_directories("${KCONFIG_BINARY_DIR}/include")

# Set KConfig binary paths
set(KCONFIG_BIN_MCONF "")
set(KCONFIG_MERGE_PYBIN "${KCONFIG_MODULE_PATH}/kconfig-merge.py")

# Add menuconfig target
add_custom_target(
    menuconfig
    ${CMAKE_COMMAND} -E env
    KCONFIG_AUTOHEADER=${KCONFIG_AUTOHEADER_PATH}
    KCONFIG_AUTOCONFIG=${KCONFIG_AUTOCONFIG_PATH}
    KCONFIG_TRISTATE=${KCONFIG_TRISTATE_PATH}
    KCONFIG_CONFIG=${KCONFIG_DOTCONFIG_PATH}
    CONFIG_=${KCONFIG_CONFIG_PREFIX}
    ${KCONFIG_MCONF_BIN}
    ${KCONFIG_MERGED_KCONFIG_PATH}
    WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
    USES_TERMINAL
)

# Add savedefconfig target
add_custom_target(
    savedefconfig
    COMMAND ${CMAKE_COMMAND} -E echo "Saving defconfig to ${KCONFIG_DEFCONFIG}"
    COMMAND ${CMAKE_COMMAND} -E env
    KCONFIG_AUTOHEADER=${KCONFIG_AUTOHEADER_PATH}
    KCONFIG_AUTOCONFIG=${KCONFIG_AUTOCONFIG_PATH}
    KCONFIG_TRISTATE=${KCONFIG_TRISTATE_PATH}
    KCONFIG_CONFIG=${KCONFIG_DOTCONFIG_PATH}
    CONFIG_=${KCONFIG_CONFIG_PREFIX}
    ${KCONFIG_CONF_BIN}
    --savedefconfig ${KCONFIG_DEFCONFIG}
    ${KCONFIG_MERGED_KCONFIG_PATH}
    WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
    USES_TERMINAL
)

# dummy target to sanity check kconfig generated files
add_custom_target(kconfig_sanity
    DEPENDS
    ${KCONFIG_DOTCONFIG_PATH}
    ${KCONFIG_AUTOHEADER_PATH}
    ${KCONFIG_MERGED_KCONFIG_PATH}
    ${KCONFIG_AUTOCONFIG_PATH}
    ${KCONFIG_TRISTATE_PATH})

# Reconfigure cmake when config changes
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${KCONFIG_DEFCONFIG}")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${KCONFIG_DOTCONFIG_PATH}")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${KCONFIG_AUTOHEADER_PATH}")

# Convert to cache config variables to config fragment
kconfig_import_cache_variables("${KCONFIG_CONFIG_PREFIX}" KCONFIG_CACHE_CONFIGS)
kconfig_create_fragment(KCONFIG_CACHE_CONFIGS "${KCONFIG_CONFIG_FRAGMENT_DIR}/cache.fragment")
# TODO: Add merge of config fragments with defconfig

# Import defconfig initially if dotconfig does not exist
if(NOT EXISTS ${KCONFIG_DOTCONFIG_PATH})
    kconfig_import_config("${KCONFIG_CONFIG_PREFIX}" "${KCONFIG_DEFCONFIG}" KCONFIG_KEYS ON)
else()
    kconfig_import_config("${KCONFIG_CONFIG_PREFIX}" "${KCONFIG_DOTCONFIG_PATH}" KCONFIG_KEYS ON)
endif()

# #######################################################################
# kconfig_post_configure
#
# This macro needs to be called last, preferably by deferred call in top level CMakeLists
macro(kconfig_post_configure)
    # Generate merged root kconfig
    kconfig_merge_kconfigs("${KCONFIG_MERGED_KCONFIG_PATH}" KCONFIG_CONFIG_SOURCES)

    # Generate initial .config file if .config does not exist yet
    if(NOT EXISTS ${KCONFIG_DOTCONFIG_PATH})
        kconfig_defconfig(
            "${KCONFIG_MERGED_KCONFIG_PATH}"
            "${KCONFIG_DEFCONFIG}"
            "${KCONFIG_DOTCONFIG_PATH}"
            "${KCONFIG_AUTOHEADER_PATH}"
            "${KCONFIG_AUTOCONFIG_PATH}"
            "${KCONFIG_TRISTATE_PATH}"
        )
    endif()

    # Generate config headers
    kconfig_oldconfig(
        "${KCONFIG_MERGED_KCONFIG_PATH}"
        "${KCONFIG_DOTCONFIG_PATH}"
        "${KCONFIG_AUTOHEADER_PATH}"
        "${KCONFIG_AUTOCONFIG_PATH}"
        "${KCONFIG_TRISTATE_PATH}"
    )

    # reimport dotconfig file
    kconfig_import_config("${KCONFIG_CONFIG_PREFIX}" "${KCONFIG_DOTCONFIG_PATH}" KCONFIG_KEYS ON)

    # Configure targets
    kconfig_configure_targets(KCONFIG_KEYS)
    message(STATUS "Kconfig final config list")

    foreach(key ${KCONFIG_KEYS})
        message(STATUS "\t ${key}: ${${key}}")
    endforeach()
endmacro()

# Add deferred call to kconfig_post_configure
cmake_language(DEFER CALL kconfig_post_configure)
