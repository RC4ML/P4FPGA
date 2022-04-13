# P4

The SwitchML P4 program is written in P4-16 for the [Tofino Native Architecture (TNA)](https://github.com/barefootnetworks/Open-Tofino).

## Requirements

The P4 code has been tested on Intel P4 Studio 9.6.0.

For details on how to obtain and compile P4 Studio, we refer you to the official [Intel documentation](https://www.intel.com/content/www/us/en/products/network-io/programmable-ethernet-switch.html).

## Build

Assuming that the `SDE` and `SDE_INSTALL` environment variables are set properly, you can use the following commands to build the P4 code:

``` bash
mkdir build && cd build
cmake ./
make && make install
```

## Run

``` bash
$SDE/run_switchd.sh -p P4FPGA
```
