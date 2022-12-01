# kconfig-cmake
# Usage

Copy or add this repository as submodule into the project directory then include `Kconfig.cmake` in the root cmake file. Use the following functions to setup the kconfig environment

- `kconfig_add_kconfig` -> Add Kconfig files to the project
- `kconfig_add_target` -> Configure the target with the configs

To conditionally link targets, add defines, etc depending on certain configs, use cmake generator expressions.

This script also generates a c header that can be preincluded to targets by setting `KCONFIG_PREINCLUDE_AUTOCONF` to `ON`. Alternatively, source files can just include it within the files itself. 

## Kconfig Targets

- menuconfig
  - Target: menuconfig -> `cmake --build <build_dir> -t menuconfig`
- savedefconfig
  - Updates `KCONFIG_DEFCONFIG` with current config
  - Target: savedefconfig -> `cmake --build <build_dir> -t savedefconfig`

# Configuration

- `KCONFIG_DEFCONFIG`
  - defconfig name to use
  - DEFAULT: `defconfig`
- `KCONFIG_BINARY_DIR`
  - Path to create build artifacts (autoconf, autoheader, etc)
  - DEFAULT: `${CMAKE_BINARY_DIR}/Kconfig`
- `KCONFIG_KBUILD_DIR`
  - Path to kconfig binary tools.
  - DEFAULT: `${KCONFIG_BINARY_DIR}/tools`
- `KCONFIG_CONFIGS_DIR`
  - Path to project configs. Requires at least one file named `defconfig`
  - DEFAULT: `${CMAKE_BINARY_DIR}/Kconfig`
- `KCONFIG_CONFIG_PREFIX`
  - Config prefix used by kconfig
  - DEFAULT: `CONFIG_`
- `KCONFIG_CONFIG_FRAGMENT_DIR`
  - Path to binary config fragments
  - DEFAULT: `${KCONFIG_BINARY_DIR}/fragments`
- `KCONFIG_TRISTATE_PATH`
  - Path to create generated tristate file
  - DEFAULT: `${KCONFIG_BINARY_DIR}/include/config/tristate.conf`
- `KCONFIG_AUTOCONFIG_PATH`
  - Path to create generated autoconf files
  - DEFAULT: `${KCONFIG_BINARY_DIR}/include/config/auto.conf`
- `KCONFIG_AUTOHEADER_PATH`
  - Path to create generated autoconf header
  - DEFAULT: `${KCONFIG_BINARY_DIR}/include/generated/config.h`
- `KCONFIG_MERGED_KCONFIG_PATH`
  - Path to create generated root kconfig file for project
  - DEFAULT: `${KCONFIG_BINARY_DIR}/Kconfig`
- `KCONFIG_DOTCONFIG_PATH`
  - Path to create .config file
  - DEFAULT: `${KCONFIG_BINARY_DIR}/.config`
- `KCONFIG_PREINCLUDE_AUTOCONF`
  - Generate pre-compiled header and link to configured targets
  - DEFAULT: `ON`
- `KCONFIG_NO_BUILD_TOOLS`
  - If `ON`, will not build kconfig binary tools if not found
  - DEFAULT: `OFF`

# Sample

## Directory

```
├── cmake            - cmake scripts
│ └── kconfig-cmake  - this repo
├── CMakeLists.txt   - root CMakeLists
├── Kconfig          - Kconfig file
│── configs          - config directory
│ └── defconfig      
└── src              - project sources
```

## Files


### Kconfig
```kconfig
menu "Project Configuration"

config USE_LIBRARY_1
    bool "link library_1 to executable"
    default y

config DEF_FOO
    bool "Define FOO when enabled"
    default n

config PROJECT_NAME
    string "Project name"
    default "PROJECT_NAME"

```


### CMakeLists.txt

```cmake
# root/CMakeLists.txt

# Add path to KConfig to cmake module path
set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake/kconfig-cmake;${CMAKE_MODULE_PATH}")
include(KConfig)

# Add kconfig file to project
kconfig_add_kconfig("${CMAKE_CURRENT_LIST_DIR}/Kconfig")

# create libraries and configure with kconfig
add_library(library_1)
kconfig_add_target(library_1)

# create executables and configure with kconfig
add_executable(executable_1)
kconfig_add_target(executable_1)

# Link library_1 to executable_1 depending on config
target_link_libraries(executable_1 PUBLIC $<$<BOOL:$<TARGET_PROPERTY:CONFIG_USE_LIBRARY_1>>:spdlog>)

# Add custom defines depending on config
target_compile_definitions(executable_1 PUBLIC $<$<BOOL:$<TARGET_PROPERTY:CONFIG_DEF_FOO>>:FOO_DEFINED>)

```

### configs/defconfig

```kconfig
CONFIG_DEF_FOO=y
```