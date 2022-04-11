# P4FPGA


## 1. Getting Started
```
$ git clone https://github.com/RC4ML/Shuhai.git
$ git submodule update --init --recursive
```

## 2. Build P4 Project
```
$ cd hw/
```
According to p4/README.md, build SDE project and program the P4 switch.

## 2. Build Driver Project
```
$ cd sw/
```
According to driver/README.md, complier the driver and insmod the driver

## 3. Build FPGA Project
```
$ cd hw/
```
According to hw/README.md, build vivado project and program the FPGA with the generated bitstream.

## 4. Build Software Project
```
$ cd sw/
```
According to sw/README.md, build the software project and run the application



