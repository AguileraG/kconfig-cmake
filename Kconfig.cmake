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
        find_program(${name} NAMES ${bin} ${ARGN} PATHS ${paths} HINTS ${paths})

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
# kconfig_get_option
#
# Checks if the kconfig conf binary supports needed options
# paths: program path to conf
function(kconfig_get_option path option _option)
    message(DEBUG "Checking kconfig targets")
    set(_TARGET_menuconfig menuconfig)
    set(_TARGET_savedefconfig savedefconfig)
    set(_TARGET_defconfig defconfig)
    set(_TARGET_oldconfig syncconfig silentoldconfig oldconfig)
    set(_TARGET_allyesconfig allyesconfig)
    set(_TARGET_allnoconfig allnoconfig)
    set(_TARGET_allmodconfig allmodconfig)
    set(_TARGET_alldefconfig alldefconfig)

    if(NOT _TARGET_${option})
        message(FATAL_ERROR "Invalid kconfig option")
    endif()

    execute_process(COMMAND ${path} --help
        OUTPUT_VARIABLE help_string)

    foreach(opt ${_TARGET_${option}})
        string(FIND "${help_string}" "--${opt}" _TARGET_${option}_FOUND)

        if(NOT ${_TARGET_${option}_FOUND} EQUAL -1)
            set(${_option} ${opt} PARENT_SCOPE)
            set(${_option}_FOUND 1 PARENT_SCOPE)
            return()
        endif()
    endforeach()

    message(DEBUG "kconfig tool does not support option: ${option}")
    unset(${_option} PARENT_SCOPE)
    unset(${_option}_FOUND PARENT_SCOPE)
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

    kconfig_get_option(${KCONFIG_CONF_BIN} defconfig KCONFIG_DEFCONFIG_OPT)
    message(DEBUG "Using ${KCONFIG_DEFCONFIG_OPT} for kconfig_defconfig")

    if(KCONFIG_DEFCONFIG_OPT_FOUND)
        execute_process(COMMAND
            ${CMAKE_COMMAND} -E env
            KCONFIG_AUTOHEADER=${autoheader}
            KCONFIG_AUTOCONFIG=${autoconf}
            KCONFIG_TRISTATE=${tristate}
            KCONFIG_CONFIG=${dotconfig}
            CONFIG_=${KCONFIG_CONFIG_PREFIX}
            ${KCONFIG_CONF_BIN}
            -s
            --${KCONFIG_DEFCONFIG_OPT} ${defconfig}
            ${kconfig_file}
            WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
            OUTPUT_QUIET ERROR_QUIET
            RESULT_VARIABLE ret
        )

        if(NOT "${ret}" STREQUAL "0")
            message(FATAL_ERROR "could not create initial .config: ${ret}")
        endif()
    else()
        message(FATAL_ERROR "kconfig tool does not support required option: defconfig")
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
        OUTPUT_QUIET ERROR_QUIET
        RESULT_VARIABLE ret
    )

    if(NOT "${ret}" STREQUAL "0")
        message(FATAL_ERROR "error during kconfig merge: ${ret}")
    endif()
endfunction()

# #######################################################################
# kconfig_create_cache_fragment <cache_fragment>
#
# Parse cmake cache variables for cli given kconfig settings
# retrieves cache fragments from global property: KCONFIG_CACHE_CONFIGS
# cache_fragment file to write config fragment
#
function(kconfig_create_cache_fragment cache_fragment)
    message(STATUS "Generating cache kconfig fragment: ${cache_fragment}")
    message(DEBUG "kconfig_create_fragment:")
    message(DEBUG "\t config_list:  ${config_list}")
    message(DEBUG "\t cache_fragment: ${cache_fragment}")

    get_property(_configs GLOBAL PROPERTY KCONFIG_CACHE_CONFIGS)

    file(WRITE ${cache_fragment} "${_configs}")
endfunction()

# #######################################################################
# kconfig_import_cache_variables <config_prefix> <cache_fragment> <config_list>
#
# Parse cmake cache variables for cli given kconfig settings
# kconfig cache keys are stored in global property: KCONFIG_CACHE_CONFIGS
# config_prefix config prefix
# config_list: variable store cache config keys
function(kconfig_import_cache_variables config_prefix)
    message(DEBUG "kconfig_import_cache_variables:")
    message(DEBUG "\t config_prefix:  ${config_prefix}")
    get_cmake_property(cache_variables CACHE_VARIABLES)

    foreach(var ${cache_variables})
        if("${var}" MATCHES "^${config_prefix}")
            list(APPEND _kconfig_cache "${var}=${${var}}\n")

            if(KCONFIG_USE_VARIABLES)
                # unset the cache config, will create a config fragment instead
                unset(${var} CACHE)
            endif()
        endif()
    endforeach()

    set_property(GLOBAL PROPERTY KCONFIG_CACHE_CONFIGS ${_kconfig_cache})
endfunction()

# #######################################################################
# kconfig_split_config <in> <name> <value>
#
# Parse input string and split config to name and value
# in: config string 
# name: variable name to store name
# value: variable name to store value
function(kconfig_split_config in name value)
    
    if("${in}" MATCHES "^([^=]+)=(.+)$")
        set(${name} ${CMAKE_MATCH_1} PARENT_SCOPE)
        set(${value} ${CMAKE_MATCH_2} PARENT_SCOPE)
    else()
        message(FATAL_ERROR "Could not parse config string: ${in}")
    endif()
endfunction()

# #######################################################################
# kconfig_parse_defconfig <config_prefix> <config_file> <config_list> <cache>
#
# Parse kconfig defconfig and store to global property KCONFIG_KEYS
# import all config to cmake variable namespace
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

    # clear property
    set_property(GLOBAL PROPERTY KCONFIG_KEYS )

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

        if(KCONFIG_USE_VARIABLES)
            set("${CONFIG_NAME}" ${CONFIG_VALUE} PARENT_SCOPE)
        endif()

        # add to list
        list(APPEND CONFIG_DEFCONFIG_LIST "${CONFIG_NAME}")
        set_property(GLOBAL APPEND PROPERTY KCONFIG_KEYS "${CONFIG_NAME}=${CONFIG_VALUE}")
    endforeach()

    if(KCONFIG_USE_VARIABLES)
        # set config list
        set(${config_list} ${CONFIG_DEFCONFIG_LIST} PARENT_SCOPE)
    endif()
endfunction()

# #######################################################################
# kconfig_add_kconfig <kconfig_file>
#
# add kconfig file to project
# Stores list of all kconfigs to global property: KCONFIG_CONFIG_SOURCES
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
# keys are retrieved from global property: KCONFIG_KEYS
# keys to configure targets: target to configure
function(kconfig_configure_targets config_keys)
    message(DEBUG "kconfig_configure_targets")
    message(DEBUG "   config_keys:   ${config_keys}")
    get_property(_kconfig_targets GLOBAL PROPERTY KCONFIG_TARGETS)
    get_property(_keys GLOBAL PROPERTY KCONFIG_KEYS)
    message(DEBUG "   targets:   ${_kconfig_targets}")

    foreach(tgt ${_kconfig_targets})
        foreach(key ${_keys})
            kconfig_split_config("${key}" name value)
            set_target_properties(${tgt} PROPERTIES ${name} ${value})
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

    # Use oldconfig
    kconfig_get_option(${KCONFIG_CONF_BIN} oldconfig KCONFIG_OLDCONFIG_OPT)
    message(DEBUG "Using ${KCONFIG_OLDCONFIG_OPT} for kconfig_oldconfig")

    if(KCONFIG_OLDCONFIG_OPT_FOUND)
        execute_process(COMMAND
            ${CMAKE_COMMAND} -E env
            KCONFIG_AUTOHEADER=${autoheader}
            KCONFIG_AUTOCONFIG=${autoconf}
            KCONFIG_TRISTATE=${tristate}
            KCONFIG_CONFIG=${dotconfig}
            CONFIG_=${KCONFIG_CONFIG_PREFIX}
            ${KCONFIG_CONF_BIN}
            --${KCONFIG_OLDCONFIG_OPT}
            ${kconfig_file}
            WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
            OUTPUT_QUIET ERROR_QUIET
            RESULT_VARIABLE ret
        )
    else()
        message(FATAL_ERROR "kconfig tool does not support required option: oldconfig")
    endif()

    if(NOT "${ret}" STREQUAL "0")
        message(FATAL_ERROR "could not generate config header: ${ret}")
    endif()
endfunction()

# #######################################################################
# kconfig_print_configs
#
# Print all configs stored in global property KCONFIG_KEYS
function(kconfig_print_configs)
    message(DEBUG "kconfig_print_configs:")

    get_property(_keys GLOBAL PROPERTY KCONFIG_KEYS)

    message(STATUS "Kconfig final config list")

    foreach(key ${_keys})
        kconfig_split_config("${key}" name value)
        message(STATUS "\t ${name}: ${value}")
    endforeach()
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
kconfig_default_variable(KCONFIG_INCLUDE_PATH "${KCONFIG_BINARY_DIR}/include")
kconfig_default_variable(KCONFIG_TRISTATE_PATH "${KCONFIG_INCLUDE_PATH}/config/tristate.conf")
kconfig_default_variable(KCONFIG_AUTOCONFIG_PATH "${KCONFIG_INCLUDE_PATH}/config/auto.conf")
kconfig_default_variable(KCONFIG_AUTOHEADER_PATH "${KCONFIG_INCLUDE_PATH}/generated/config.h")
kconfig_default_variable(KCONFIG_MERGED_KCONFIG_PATH "${KCONFIG_BINARY_DIR}/Kconfig")
kconfig_default_variable(KCONFIG_DOTCONFIG_PATH "${KCONFIG_BINARY_DIR}/.config")
kconfig_default_variable(KCONFIG_PREINCLUDE_AUTOCONF ON)
kconfig_default_variable(KCONFIG_USE_VARIABLES OFF)

# Create paths
file(MAKE_DIRECTORY ${KCONFIG_BINARY_DIR} ${KCONFIG_CONFIG_FRAGMENT_DIR})
kconfig_make_directory(KCONFIG_TRISTATE_PATH)
kconfig_make_directory(KCONFIG_AUTOCONFIG_PATH)
kconfig_make_directory(KCONFIG_AUTOHEADER_PATH)
kconfig_make_directory(KCONFIG_MERGED_KCONFIG_PATH)
kconfig_make_directory(KCONFIG_DOTCONFIG_PATH)

# Search for kconfig-* binaries
kconfig_find_bin("${KCONFIG_KBUILD_DIR}" KCONFIG_CONF_BIN kconfig-conf conf)
kconfig_find_bin("${KCONFIG_KBUILD_DIR}" KCONFIG_MCONF_BIN kconfig-mconf mconf)

# Check if binaries are found
if(NOT KCONFIG_CONF_BIN_FOUND OR NOT KCONFIG_MCONF_BIN_FOUND)
    message(FATAL_ERROR "Kconfig binaries not found, try setting KCONFIG_KBUILD_DIR")
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

# Add kconfig include dir to include directories
include_directories("${KCONFIG_INCLUDE_PATH}")

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
kconfig_get_option(${KCONFIG_CONF_BIN} savedefconfig KCONFIG_SAVEDEFCONFIG_OPT)

if(KCONFIG_SAVEDEFCONFIG_OPT_FOUND)
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
        --${KCONFIG_SAVEDEFCONFIG_OPT} ${KCONFIG_DEFCONFIG}
        ${KCONFIG_MERGED_KCONFIG_PATH}
        WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
        USES_TERMINAL
    )
else()
    message(FATAL_ERROR "kconfig tool does not support required option: savedefconfig")
endif()

# Add allyesconfig target
kconfig_get_option(${KCONFIG_CONF_BIN} allyesconfig KCONFIG_ALLYESCONFIG_OPT)

if(KCONFIG_ALLYESCONFIG_OPT_FOUND)
    add_custom_target(
        allyesconfig
        COMMAND ${CMAKE_COMMAND} -E echo "Saving defconfig to ${KCONFIG_DEFCONFIG}"
        COMMAND ${CMAKE_COMMAND} -E env
        KCONFIG_AUTOHEADER=${KCONFIG_AUTOHEADER_PATH}
        KCONFIG_AUTOCONFIG=${KCONFIG_AUTOCONFIG_PATH}
        KCONFIG_TRISTATE=${KCONFIG_TRISTATE_PATH}
        KCONFIG_CONFIG=${KCONFIG_DOTCONFIG_PATH}
        CONFIG_=${KCONFIG_CONFIG_PREFIX}
        ${KCONFIG_CONF_BIN}
        --${KCONFIG_ALLYESCONFIG_OPT}
        ${KCONFIG_MERGED_KCONFIG_PATH}
        WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
        USES_TERMINAL
    )
else()
    message(STATUS "kconfig tool does not support option: allyesconfig")
endif()

# Add allmodconfig target
kconfig_get_option(${KCONFIG_CONF_BIN} allnoconfig KCONFIG_ALLNOCONFIG_OPT)

if(KCONFIG_ALLNOCONFIG_OPT_FOUND)
    add_custom_target(
        allnoconfig
        COMMAND ${CMAKE_COMMAND} -E echo "Saving defconfig to ${KCONFIG_DEFCONFIG}"
        COMMAND ${CMAKE_COMMAND} -E env
        KCONFIG_AUTOHEADER=${KCONFIG_AUTOHEADER_PATH}
        KCONFIG_AUTOCONFIG=${KCONFIG_AUTOCONFIG_PATH}
        KCONFIG_TRISTATE=${KCONFIG_TRISTATE_PATH}
        KCONFIG_CONFIG=${KCONFIG_DOTCONFIG_PATH}
        CONFIG_=${KCONFIG_CONFIG_PREFIX}
        ${KCONFIG_CONF_BIN}
        --${KCONFIG_ALLNOCONFIG_OPT}
        ${KCONFIG_MERGED_KCONFIG_PATH}
        WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
        USES_TERMINAL
    )
else()
    message(STATUS "kconfig tool does not support option: allnoconfig")
endif()

# Add allmodconfig target
kconfig_get_option(${KCONFIG_CONF_BIN} allmodconfig KCONFIG_ALLMODCONFIG_OPT)

if(KCONFIG_ALLMODCONFIG_OPT_FOUND)
    add_custom_target(
        allmodconfig
        COMMAND ${CMAKE_COMMAND} -E echo "Saving defconfig to ${KCONFIG_DEFCONFIG}"
        COMMAND ${CMAKE_COMMAND} -E env
        KCONFIG_AUTOHEADER=${KCONFIG_AUTOHEADER_PATH}
        KCONFIG_AUTOCONFIG=${KCONFIG_AUTOCONFIG_PATH}
        KCONFIG_TRISTATE=${KCONFIG_TRISTATE_PATH}
        KCONFIG_CONFIG=${KCONFIG_DOTCONFIG_PATH}
        CONFIG_=${KCONFIG_CONFIG_PREFIX}
        ${KCONFIG_CONF_BIN}
        --${KCONFIG_ALLMODCONFIG_OPT}
        ${KCONFIG_MERGED_KCONFIG_PATH}
        WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
        USES_TERMINAL
    )
else()
    message(STATUS "kconfig tool does not support option: allmodconfig")
endif()

# Add alldefconfig target
kconfig_get_option(${KCONFIG_CONF_BIN} alldefconfig KCONFIG_ALLDEFCONFIG_OPT)

if(KCONFIG_ALLDEFCONFIG_OPT_FOUND)
    add_custom_target(
        alldefconfig
        COMMAND ${CMAKE_COMMAND} -E echo "Saving defconfig to ${KCONFIG_DEFCONFIG}"
        COMMAND ${CMAKE_COMMAND} -E env
        KCONFIG_AUTOHEADER=${KCONFIG_AUTOHEADER_PATH}
        KCONFIG_AUTOCONFIG=${KCONFIG_AUTOCONFIG_PATH}
        KCONFIG_TRISTATE=${KCONFIG_TRISTATE_PATH}
        KCONFIG_CONFIG=${KCONFIG_DOTCONFIG_PATH}
        CONFIG_=${KCONFIG_CONFIG_PREFIX}
        ${KCONFIG_CONF_BIN}
        --${KCONFIG_ALLDEFCONFIG_OPT}
        ${KCONFIG_MERGED_KCONFIG_PATH}
        WORKING_DIRECTORY ${KCONFIG_BINARY_DIR}
        USES_TERMINAL
    )
else()
    message(STATUS "kconfig tool does not support option: alldefconfig")
endif()

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

# Add Kconfig binary dir to clean targets
set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${KCONFIG_BINARY_DIR}")

# Convert to cache config variables to config fragment
kconfig_import_cache_variables("${KCONFIG_CONFIG_PREFIX}" KCONFIG_CACHE_CONFIGS)
kconfig_create_cache_fragment("${KCONFIG_CONFIG_FRAGMENT_DIR}/cache.fragment")

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

    # Use tmp paths for .config and autoheader to prevent recompiling targets
    set(dotconfig_tmp "${KCONFIG_DOTCONFIG_PATH}_tmp")
    set(autoheader_tmp "${KCONFIG_AUTOHEADER_PATH}_tmp")
    file(COPY_FILE ${KCONFIG_DOTCONFIG_PATH} ${dotconfig_tmp})

    # Generate config headers
    kconfig_oldconfig(
        "${KCONFIG_MERGED_KCONFIG_PATH}"
        "${dotconfig_tmp}"
        "${autoheader_tmp}"
        "${KCONFIG_AUTOCONFIG_PATH}"
        "${KCONFIG_TRISTATE_PATH}"
    )

    # reimport dotconfig file
    kconfig_import_config("${KCONFIG_CONFIG_PREFIX}" "${KCONFIG_DOTCONFIG_PATH}" KCONFIG_KEYS ON)

    # Update .config and autoheader if new files are different
    file(COPY_FILE ${dotconfig_tmp} ${KCONFIG_DOTCONFIG_PATH} ONLY_IF_DIFFERENT)
    file(COPY_FILE ${autoheader_tmp} ${KCONFIG_AUTOHEADER_PATH} ONLY_IF_DIFFERENT)

    # Configure targets
    kconfig_configure_targets(KCONFIG_KEYS)

    # print configs
    kconfig_print_configs()
endmacro()

# Add deferred call to kconfig_post_configure
cmake_language(DEFER CALL kconfig_post_configure)
