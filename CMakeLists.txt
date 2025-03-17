cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    set(CMAKE_CUDA_ARCHITECTURES all-major CACHE STRING "CUDA architectures")
    message(WARNING "CMAKE_CUDA_ARCHITECTURES set to \"all-major\".\
 This option will generate PTX code for all major CUDA architectures, which may increase the build time.\
 Consider setting CMAKE_CUDA_ARCHITECTURES to a specific architecture (e.g. 70) or a list of architectures (e.g. 70;75;86) to reduce the build time.")
endif()

project(UAMMDstructured LANGUAGES CXX CUDA)

set(CMAKE_BUILD_TYPE Release CACHE STRING "Choose the type of build." FORCE)

# Add option for Python package installation
option(INSTALL_PYTHON_PACKAGE "Install Python package during make install" OFF)

# Add option for Python wrapper (only available if INSTALL_PYTHON_PACKAGE is ON)
option(BUILD_PYTHON_WRAPPER "Build Python wrapper for UAMMDlauncher" OFF)

# Add option for building .deb package
option(BUILD_DEB_PACKAGE "Build .deb package" OFF)

# Add option for setting ccbin for nvcc
set(CUDA_HOST_COMPILER "DEFAULT" CACHE STRING "Path to the host compiler for CUDA (DEFAULT to use default compiler)")

# Ensure BUILD_PYTHON_WRAPPER is OFF if INSTALL_PYTHON_PACKAGE is OFF
if(BUILD_PYTHON_WRAPPER AND NOT INSTALL_PYTHON_PACKAGE)
    message(FATAL_ERROR "BUILD_PYTHON_WRAPPER is ON but INSTALL_PYTHON_PACKAGE is OFF. "
                        "Please enable INSTALL_PYTHON_PACKAGE to build the Python wrapper.")
endif()

# BUILD_DEB_PACKAGE is only available if BUILD_PYTHON_WRAPPER and INSTALL_PYTHON_PACKAGE are OFF
if(BUILD_DEB_PACKAGE AND (BUILD_PYTHON_WRAPPER OR INSTALL_PYTHON_PACKAGE))
    message(FATAL_ERROR "BUILD_DEB_PACKAGE is ON but BUILD_PYTHON_WRAPPER or INSTALL_PYTHON_PACKAGE are ON. "
                        "Please disable BUILD_PYTHON_WRAPPER and INSTALL_PYTHON_PACKAGE to build the .deb package.")
endif()

set(UAMMD_REPO_URL "https://github.com/RaulPPelaez/UAMMD.git")
set(UAMMD_TAG "pablo")

###############################################################
# Download UAMMD
set(UAMMD_STRUCTURED_PATH "${CMAKE_BINARY_DIR}/UAMMDstructured")
include(FetchContent)
FetchContent_Declare(
  uammd
  GIT_REPOSITORY https://github.com/RaulPPelaez/uammd/
  GIT_TAG        pablo
  # Put it in UAMMDstructured/uammd
  SOURCE_DIR ${UAMMD_STRUCTURED_PATH}/uammd
  UPDATE_DISCONNECTED 1
)
FetchContent_MakeAvailable(uammd)
###############################################################
# Create UAMMDstructured folder
#file(MAKE_DIRECTORY ${UAMMD_STRUCTURED_PATH})
file(MAKE_DIRECTORY ${UAMMD_STRUCTURED_PATH}/extensions)

set(UAMMD_COMPONENTS_PATH "${CMAKE_CURRENT_SOURCE_DIR}/structured/Components.json")
set(UAMMD_DATA_PATH "${CMAKE_CURRENT_SOURCE_DIR}/structured/Data.json")
set(UAMMD_COMPUTABLES_PATH "${CMAKE_CURRENT_SOURCE_DIR}/structured/Computables.json")
###############################################################
# Copy structured/ folder to UAMMDstructured/
file(CREATE_LINK ${CMAKE_CURRENT_SOURCE_DIR}/structured ${UAMMD_STRUCTURED_PATH}/extensions/structured SYMBOLIC)
include_directories(${UAMMD_STRUCTURED_PATH}/extensions/structured/include)
include_directories(${UAMMD_STRUCTURED_PATH}/extensions/structured/src)
# Copy ${UAMMD_STRUCTURED_PATH}/extensions/structured/preamble.h to uammd/extensions/preamble.h
file(COPY ${UAMMD_STRUCTURED_PATH}/extensions/structured/preamble.h DESTINATION ${UAMMD_STRUCTURED_PATH}/uammd/extensions/)

# Set the precision of UAMMD, SINGLE or DOUBLE
set(UAMMD_PRECISION "SINGLE" CACHE STRING "Choose the precision of UAMMD, SINGLE or DOUBLE")

# If UAMMD_PRECISION is not SINGLE or DOUBLE, set it to SINGLE
if(NOT UAMMD_PRECISION STREQUAL "SINGLE" AND NOT UAMMD_PRECISION STREQUAL "DOUBLE")
  set(UAMMD_PRECISION "SINGLE")
  message(WARNING "UAMMD_PRECISION is not SINGLE or DOUBLE, set it to SINGLE")
endif()

################################################################
# Set Compiler Standards
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

################################################################
# CUDA Compiler options

# Set CMAKE_CUDA_HOST_COMPILER if CUDA_HOST_COMPILER is provided and not DEFAULT
if(NOT "${CUDA_HOST_COMPILER}" STREQUAL "DEFAULT")
    set(CMAKE_CUDA_HOST_COMPILER "${CUDA_HOST_COMPILER}")
endif()

################################################################
# Packages
find_package(BLAS REQUIRED)

set(LIBRARIES stdc++fs)

if(INSTALL_PYTHON_PACKAGE)
    find_package(Python COMPONENTS Interpreter REQUIRED)
endif()

if(BUILD_PYTHON_WRAPPER)
    find_package(Python COMPONENTS Interpreter Development REQUIRED)
    find_package(pybind11 REQUIRED)
endif()

################################################################
# Files generation

set(UAMMD_STRUCTURED_INCLUDE_PATH "${UAMMD_STRUCTURED_PATH}/extensions/structured/include")

# Function to parse JSON and generate property definitions
function(generate_property_definitions json_file section output_var)
  file(READ ${json_file} json_content)
  string(JSON section_data GET ${json_content} ${section})

  set(properties "")
  string(JSON array_length LENGTH ${section_data})
  math(EXPR array_length "${array_length} - 1")

  foreach(index RANGE ${array_length})
    string(JSON item GET ${section_data} ${index})
    string(JSON name GET ${item} 0)
    string(JSON cpp_type GET ${item} 1)
    string(JSON c_type GET ${item} 2)
    string(APPEND properties "((${cpp_type})(${name})(${c_type}))\\\n")
  endforeach()

  # Remove the last newline and backslash
  string(REGEX REPLACE "\\\\n$" "" properties "${properties}")

  set(${output_var} "${properties}" PARENT_SCOPE)
endfunction()

# List of sections to process
set(SECTIONS ParticleData State Units Fundamental Ensemble)

# Generate header files for each section
foreach(SECTION ${SECTIONS})
  string(TOUPPER ${SECTION} SECTION_UPPER)
  set(HEADER_FILE "${UAMMD_STRUCTURED_INCLUDE_PATH}/Definitions/${SECTION}.cuh")

  generate_property_definitions(${UAMMD_DATA_PATH} ${SECTION} PROPERTIES)

  file(WRITE ${HEADER_FILE}
"#pragma once

#define ${SECTION_UPPER}_PROPERTIES \\
${PROPERTIES}
")

  # Add a custom target for generating the header file
  add_custom_target(
    Generate${SECTION}Data ALL
    DEPENDS ${HEADER_FILE}
  )
endforeach()

# Generate computables

# Function to generate Computables.cuh
function(generate_computables_header json_file output_file)
  file(READ ${json_file} json_content)

  # Parse Computables
  string(JSON computables GET ${json_content} Computables)
  set(computables_list "")
  string(JSON computables_length LENGTH ${computables})
  math(EXPR computables_length "${computables_length} - 1")
  foreach(index RANGE ${computables_length})
    string(JSON item GET ${computables} ${index})
    string(JSON name GET ${item} 0)
    string(JSON type GET ${item} 1)
    string(APPEND computables_list "((${name})(${type}))\\\n")
  endforeach()

  # Remove the last newline and backslash
  string(REGEX REPLACE "\\\\n$" "" computables_list "${computables_list}")

  # Parse ComputablesCombinations
  string(JSON combinations GET ${json_content} ComputablesCombinations)
  set(combinations_list "")
  string(JSON combinations_length LENGTH ${combinations})
  math(EXPR combinations_length "${combinations_length} - 1")
  foreach(index RANGE ${combinations_length})
    string(JSON item GET ${combinations} ${index})
    string(JSON item_length LENGTH ${item})
    set(combination "")
    math(EXPR item_length "${item_length} - 1")

    foreach(item_index RANGE ${item_length})
      string(JSON element GET ${item} ${item_index})
      string(APPEND combination "(${element})")
    endforeach()

    string(APPEND combinations_list "(${combination})\\\n")
  endforeach()

  # Remove the last newline and backslash
  string(REGEX REPLACE "\\\\n$" "" combinations_list "${combinations_list}")

  #Write the header file
  file(WRITE ${output_file}
"#pragma once

#define COMPUTABLES \\
${computables_list}

#define COMPUTABLES_COMBINATIONS \\
${combinations_list}
")

endfunction()

set(COMPUTABLES_HEADER_FILE "${UAMMD_STRUCTURED_INCLUDE_PATH}/Definitions/Computables.cuh")

generate_computables_header(${UAMMD_COMPUTABLES_PATH} ${COMPUTABLES_HEADER_FILE})

# Add a custom target for generating the header file
add_custom_target(
  GenerateComputablesData ALL
  DEPENDS ${COMPUTABLES_HEADER_FILE}
)

################################################################
set(UAMMD_STRUCTURED_SRC_PATH "${UAMMD_STRUCTURED_PATH}/extensions/structured/src")
# Add backbone files to STRUCTURED_BACKBONE_FILES
# USe glob to find any .cu or .cpp file in the hierarchy
#file(GLOB_RECURSE STRUCTURED_BACKBONE_FILES ${UAMMD_STRUCTURED_SRC_PATH} "*.cu")

list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Input/Input.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Input/InputEntryManager.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/System/ExtendedSystem.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/GlobalData/GlobalData.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/GlobalData/Units/UnitsLoaders.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/GlobalData/Ensemble/EnsembleLoaders.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/GlobalData/Types/TypesLoaders.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/GlobalData/Fundamental/FundamentalLoaders.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/ParticleData/ExtendedParticleData.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/ParticleData/StateLoader.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/ParticleGroup/ParticleGroupUtils.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Interactor/InteractorLoader.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Interactor/Patches/PatchInteractorLoader.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Interactor/PatchyParticles/PatchyParticlesInteractor.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Integrator/IntegratorBase.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Integrator/IntegratorManager.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Integrator/IntegratorLoaders.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Integrator/IntegratorUtils.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/ForceFields/ForceFields.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Topology/Topology.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/SimulationStep/SimulationStep.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/SimulationStep/SimulationStepManager.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/SimulationStep/GenericSimulationStepLoader.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Simulation/Simulation.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/DataStructures/VerletConditionalListSet/VerletConditionalListSetUtils.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/DataStructures/VerletConditionalListSet/VerletConditionalListSetLoaders.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/DataStructures/GroupsList/GroupsList.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/DataStructures/ExclusionsList/ExclusionsList.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Utils/String/StringUtils.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Utils/Output/Output.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Utils/Backup/Backup.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Utils/Backup/BackupStep.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Utils/Measures/MeasuresBasic.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Utils/ParameterHandler/CheckDataConsistency.cu")
list(APPEND STRUCTURED_BACKBONE_FILES "${UAMMD_STRUCTURED_SRC_PATH}/Utils/Containers/SetUtils.cu")

# Define STRUCTURED_COMPONENTS as a global variable
set(STRUCTURED_COMPONENTS "")

# Add this function to parse the JSON and populate STRUCTURED_COMPONENTS
function(parse_json_and_add_files json_file base_path)
  file(READ ${json_file} json_content)
  string(JSON json_object ERROR_VARIABLE json_error GET ${json_content})

  if(json_error)
    message(FATAL_ERROR "Error parsing JSON: ${json_error}")
  endif()

  parse_json_object("" ${json_object})

  set(STRUCTURED_COMPONENTS ${STRUCTURED_COMPONENTS} PARENT_SCOPE)
endfunction()

function(parse_json_object current_path object)
  string(JSON num_elements LENGTH ${object})
  math(EXPR num_elements "${num_elements} - 1")

  foreach(i RANGE ${num_elements})
    string(JSON key MEMBER ${object} ${i})
    string(JSON value GET ${object} ${key})

    if("${value}" MATCHES "^\\[")
      parse_json_array("${current_path}/${key}" ${value})
    elseif("${value}" MATCHES "^\\{")
      parse_json_object("${current_path}/${key}" ${value})
    endif()
  endforeach()

  set(STRUCTURED_COMPONENTS ${STRUCTURED_COMPONENTS} PARENT_SCOPE)
endfunction()

function(parse_json_array current_path array)
  string(JSON num_elements LENGTH ${array})
  math(EXPR num_elements "${num_elements} - 1")

  foreach(i RANGE ${num_elements})
    string(JSON value GET ${array} ${i})
    if("${value}" MATCHES "^\\[")
      string(JSON inner_array_length LENGTH ${value})
      if(inner_array_length GREATER 2)
        string(JSON component_type GET ${value} 0)
        string(JSON component_name GET ${value} 1)
        string(JSON component_file GET ${value} 2)
        if(component_file MATCHES "\\.cu$")
          set(file_path "${base_path}${current_path}/${component_type}/${component_file}")
          list(APPEND STRUCTURED_COMPONENTS ${file_path})
          set(STRUCTURED_COMPONENTS ${STRUCTURED_COMPONENTS} PARENT_SCOPE)
        else()
          message(FATAL_ERROR "Error parsing JSON: ${value} is not a valid file")
        endif()
      endif()
    endif()
  endforeach()
  set(STRUCTURED_COMPONENTS ${STRUCTURED_COMPONENTS} PARENT_SCOPE)
endfunction()

parse_json_and_add_files(${UAMMD_COMPONENTS_PATH} ${UAMMD_STRUCTURED_PATH}/extensions/structured/src/)

list(REMOVE_DUPLICATES STRUCTURED_COMPONENTS)

set(COMPONENT_LIBRARIES "")
foreach(SOURCE_FILE ${STRUCTURED_COMPONENTS} ${STRUCTURED_BACKBONE_FILES})
  get_filename_component(FILE_NAME ${SOURCE_FILE} NAME_WE)
  get_filename_component(DIR_PATH ${SOURCE_FILE} DIRECTORY)
  file(RELATIVE_PATH REL_DIR_PATH "${UAMMD_STRUCTURED_PATH}/extensions/structured/src" ${DIR_PATH})
  string(REPLACE "/" "_" REL_DIR_PATH ${REL_DIR_PATH})
  set(LIB_NAME "${REL_DIR_PATH}_${FILE_NAME}")
  add_library(${LIB_NAME} STATIC ${SOURCE_FILE})
  list(APPEND COMPONENT_LIBRARIES ${LIB_NAME})
  uammd_setup_target(${LIB_NAME})
  target_compile_options(${LIB_NAME} PRIVATE
    $<$<COMPILE_LANGUAGE:CUDA>:--expt-relaxed-constexpr --expt-extended-lambda -O3 -Xcompiler=-O3,-fPIC -w>
  )
  target_compile_definitions(${LIB_NAME} PRIVATE UAMMD_EXTENSIONS MAXLOGLEVEL=5)
endforeach()
add_library(structured_objects_i INTERFACE)
target_link_libraries(structured_objects_i INTERFACE ${COMPONENT_LIBRARIES})

if(UAMMD_PRECISION STREQUAL "DOUBLE")
    target_compile_definitions(structured_objects PRIVATE DOUBLE_PRECISION)
endif()

# Define the executable
add_executable(UAMMDlauncher ${CMAKE_CURRENT_SOURCE_DIR}/main/UAMMDlauncher.cu)
uammd_setup_target(UAMMDlauncher)

if(UAMMD_PRECISION STREQUAL "DOUBLE")
    target_compile_definitions(UAMMDlauncher PRIVATE DOUBLE_PRECISION)
endif()

# Set include directories for UAMMDlauncher
target_include_directories(UAMMDlauncher PRIVATE
    ${UAMMD_STRUCTURED_PATH}/extensions/structured/include/
    ${UAMMD_STRUCTURED_PATH}/extensions/structured/src/
)

# Set compile options for UAMMDlauncher
target_compile_options(UAMMDlauncher PRIVATE
    $<$<COMPILE_LANGUAGE:CUDA>:--expt-relaxed-constexpr --expt-extended-lambda -O3 -Xcompiler=-O3,-fPIC -w>
)

# Set definitions for UAMMDlauncher
target_compile_definitions(UAMMDlauncher PRIVATE  UAMMD_EXTENSIONS MAXLOGLEVEL=5)

# Link libraries
target_link_libraries(UAMMDlauncher PRIVATE
                      structured_objects_i)

foreach(SECTION ${SECTIONS})
    add_dependencies(UAMMDlauncher Generate${SECTION}Data)
endforeach()

if(BUILD_PYTHON_WRAPPER)
    # Add the Python module target
    pybind11_add_module(pyUAMMDlauncher ${CMAKE_CURRENT_SOURCE_DIR}/pyUAMMD/utils/launcher/UAMMDlauncher.cu)
    uammd_setup_target(pyUAMMDlauncher)
    # Link libraries
    target_link_libraries(pyUAMMDlauncher PRIVATE
                          structured_objects_i)

    # Set include directories for pyUAMMDlauncher
    target_include_directories(pyUAMMDlauncher PRIVATE
        ${UAMMD_STRUCTURED_PATH}/extensions/structured/include/
        ${UAMMD_STRUCTURED_PATH}/extensions/structured/src/
    )

    # Set compile options for pyUAMMDlauncher
    target_compile_options(pyUAMMDlauncher PRIVATE
        $<$<COMPILE_LANGUAGE:CUDA>:--expt-relaxed-constexpr --expt-extended-lambda -O3 -Xcompiler=-O3,-fPIC -w>
    )

    # Set definitions for pyUAMMDlauncher
    target_compile_definitions(pyUAMMDlauncher PRIVATE MAXLOGLEVEL=5)

    if(UAMMD_PRECISION STREQUAL "DOUBLE")
        target_compile_definitions(pyUAMMDlauncher PRIVATE DOUBLE_PRECISION)
    endif()

    # Set properties for pyUAMMDlauncher
    set_target_properties(pyUAMMDlauncher PROPERTIES
        POSITION_INDEPENDENT_CODE ON
        CXX_STANDARD 17
        CUDA_STANDARD 17
    )

    foreach(SECTION ${SECTIONS})
        add_dependencies(pyUAMMDlauncher Generate${SECTION}Data)
    endforeach()
endif()

################################################################
# Build .deb package
if(BUILD_DEB_PACKAGE)
    include(InstallRequiredSystemLibraries)

    set(CPACK_PACKAGE_NAME "uammdstructured")
    set(CPACK_PACKAGE_VERSION "1.0.0")
    set(CPACK_PACKAGE_CONTACT "Pablo Ibanez Freire <p.ibanez.fre@gmail.com>")
    set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "UAMMDstructured")
    set(CPACK_PACKAGE_VENDOR "Universidad Autonoma de Madrid")

    set(CPACK_GENERATOR "DEB")
    set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "amd64")

    include(CPack)

    install(TARGETS UAMMDlauncher
            RUNTIME DESTINATION bin)
endif()
if(NOT BUILD_DEB_PACKAGE)

    install(TARGETS UAMMDlauncher
            RUNTIME DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)

    if(INSTALL_PYTHON_PACKAGE)
        add_custom_target(
            install_python_package
            COMMAND ${CMAKE_COMMAND} -E echo "Installing Python package..."
            COMMAND ${Python_EXECUTABLE} -m pip install ${CMAKE_SOURCE_DIR}
            WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        )

        # Make sure the Python package is installed after the main target and Python wrapper (if built)
        add_dependencies(install_python_package UAMMDlauncher)
        if(BUILD_PYTHON_WRAPPER)
            add_dependencies(install_python_package pyUAMMDlauncher)
        endif()

        # Add the Python package installation to the default install target
        install(CODE "execute_process(COMMAND ${CMAKE_COMMAND} --build . --target install_python_package)")
        if(BUILD_PYTHON_WRAPPER)
            # Installation rules for Python module
            install(TARGETS pyUAMMDlauncher
                    LIBRARY DESTINATION ${Python_SITELIB}/pyUAMMD/utils/launcher)
        endif()
    endif()
endif()
