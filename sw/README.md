# software

## 1. Kernel Part
Loading PCIe kernel module if not loaded yet. 
```
$ cd driver
$ make clean
$ make
$ sudo insmod xdma_driver.ko
```
Please make sure your kernel module is successfully installed for Ubuntu.

## 2. Application Part
### a. Compile application code
```
$ cd ..
$ mkdir build && cd build
$ cmake ../src
$ make
```

### b.Build Application
1. Install prerequisites, e.g. on Ubuntu install the following packages:
```
$ apt install libboost-program-options-dev cmake
```
2. Compile example application
```
$ cd sw
$ mkdir build && cd build
$ cmake ../src
$ make
```

### c.Run Application/Benchmark

Run the Application (requires root permission)
```
$ cd sw/build
$ ./Test_sgd_top -n 6 -t 1 -w 5
```
