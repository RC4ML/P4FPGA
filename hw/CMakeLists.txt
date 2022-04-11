# Author:   Huang hongjing (21515069@zju.edu.cn)

cmake_minimum_required(VERSION 3.0)

project(example_module)

# Include custom Find<Module>.cmake scripts to enable searching for Vivado HLS                                
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CMAKE_SOURCE_DIR}/cmake)  

# Check if parent directory
get_directory_property(hasParent PARENT_DIRECTORY)

if (DEFINED ENV{IPREPO_DIR})
   set(IPREPO_DIR $ENV{IPREPO_DIR})
elseif (NOT IPREPO_DIR)
   set(IPREPO_DIR ${CMAKE_CURRENT_SOURCE_DIR}/iprepo)
   message("set iprepor dir ${IPREPO_DIR}")
endif()



###VIVADO project
# Find Xilinx Vivado
find_package(Vivado REQUIRED)
if (NOT VIVADO_FOUND)
   message(FATAL_ERROR "Vivado not found.")
endif()
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/scripts/create_common_ip.tcl.in ${CMAKE_BINARY_DIR}/create_common_ip.tcl)

configure_file(${CMAKE_CURRENT_SOURCE_DIR}/scripts/create_project.tcl.in ${CMAKE_BINARY_DIR}/create_project.tcl)



set (PROJECT_DEPENDS
      ${CMAKE_CURRENT_SOURCE_DIR}/rtl/new/sgd_defines.vh
      ${CMAKE_CURRENT_SOURCE_DIR}/scripts/create_project.tcl.in
      ${CMAKE_CURRENT_SOURCE_DIR}/scripts/create_common_ip.tcl.in)      

add_custom_target(project
   COMMAND ${VIVADO_BINARY} -mode batch -source ${CMAKE_BINARY_DIR}/create_project.tcl
   DEPENDS ${PROJECT_DEPENDS})
