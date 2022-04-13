cmake_minimum_required(VERSION 3.7)
project(P4FPGA)

set(CMAKE_INSTALL_PREFIX $ENV{SDE_INSTALL})
set(CMAKE_MODULE_PATH    $ENV{SDE}/cmake)

set(P4_NAME P4FPGA)
set(P4_PATH ${CMAKE_CURRENT_SOURCE_DIR}/p4fpga.p4)

set(P4_BUILD_DIRECTORY p4build)

add_subdirectory($ENV{SDE}/p4studio/ ${P4_BUILD_DIRECTORY} EXCLUDE_FROM_ALL)

add_custom_target(p4_build # for SDE version after 9.6.0
                  COMMAND make clean && make install
                  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${P4_BUILD_DIRECTORY})
