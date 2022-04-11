#!/usr/bin/expect -f
set user "amax8"
set ip "192.168.189.14"
set pass "Rc4ml0624@17$\n"

spawn ssh "$user@$ip" ; log_user 0;
expect "]*"
send "sudo rm -rf /home/$user/transfer/$user\n"
expect "]*"
send "exit\n"
expect eof

spawn scp -r /home/amax/hhj/distribute_sw/sw "$user@$ip:/home/$user/transfer/$user"; log_user 0;
expect "]*"
spawn ssh "$user@$ip"
expect "]*"
send "cd /home/$user/transfer/$user/src\n" ;log_user 1;
expect "]*"
send "mkdir build\n"
expect "]*"
send "cd build\n"
expect "]*"
send "cmake ..\n"
expect "]*"
send "make Test_sgd_top\n"
expect eof
expect eof
send "sudo ./Test_sgd_top -n 8 -t 1 -w 0\n"
expect "]*"
interact

# #!/bin/bash
# ssh amax8@192.168.189.14 "echo Rc4ml0624@17$ | sudo -S rm -rf /home/amax8/transfer/amax8; exit"
# # name=inc_indian_news1exi
# #inc_gisette_scale  inc_indian_news1
# # cd /home/amax/cj/sparse_64_optimize/data/dataset;
# # cp $name'_data_64.ddr' ../../sw/sparse_sw/data/;
# # cp $name'_index_64.ddr' ../../sw/sparse_sw/data/;
# # cp $name'_aid_64.ddr' ../../sw/sparse_sw/data/;

# cd sw;
# scp -r ./sw $amax8/amax8
# # rm ../sw/sparse_sw/data/*;
# echo "transfer done!"
# # ssh amax8@192.168.189.14 "cd /home/amax8/transfer/amax8; cd src ;mkdir build; cd build; echo Rc4ml0624@17$ | sudo -S cmake ..;echo Rc4ml0624@17$ | sudo -S make amax8 && echo Rc4ml0624@17$ | sudo -S ./amax8 ; exit"
# # ssh amax8@192.168.189.14 "cd /home/amax8/transfer/amax8; cd src ;mkdir build; cd build; echo Rc4ml0624@17$ | sudo -S cmake ..;echo Rc4ml0624@17$ | sudo -S make amax8_tcpbenchmark && echo Rc4ml0624@17$ | sudo -S ./amax8_tcpbenchmark ; exit"
# # ssh amax8@192.168.189.14 "cd /home/amax8/transfer/amax8; cd src ;mkdir build; cd build; echo Rc4ml0624@17$ | sudo -S cmake ..;echo Rc4ml0624@17$ | sudo -S make amax8_tcp_latency8 && echo Rc4ml0624@17$ | sudo -S ./amax8_tcp_latency8 ; exit"
# ssh amax8@192.168.189.14 "cd /home/amax8/transfer/amax8; cd src ;mkdir build; cd build; echo Rc4ml0624@17$ | sudo -S cmake ..;echo Rc4ml0624@17$ | sudo -S make amax8_mpireduce && echo Rc4ml0624@17$ | sudo -S ./amax8_mpireduce ; exit"





# #!/bin/bash
# ssh amax2@192.168.189.8 "echo Rc4ml0624@5$ | sudo -S rm -rf /home/amax2/transfer/amax2; exit"
# # name=inc_indian_news1exi
# #inc_gisette_scale  inc_indian_news1
# # cd /home/amax/cj/sparse_64_optimize/data/dataset;
# # cp $name'_data_64.ddr' ../../sw/sparse_sw/data/;
# # cp $name'_index_64.ddr' ../../sw/sparse_sw/data/;
# # cp $name'_aid_64.ddr' ../../sw/sparse_sw/data/;

# cd /home/amax/hhj/davos_dev;
# scp -r ./sw $amax2/amax2
# # rm ../sw/sparse_sw/data/*;
# echo "transfer done!"
# # ssh amax2@192.168.189.8 "cd /home/amax6/transfer/amax2; cd src ;mkdir build; cd build; echo Rc4ml0624@5$ | sudo -S cmake ..;echo Rc4ml0624@5$ | sudo -S make dma-example && echo Rc4ml0624@13$ | sudo -S ./dma-example ; exit"
# # ssh amax2@192.168.189.8 "cd /home/amax2/transfer/amax2; cd src ;mkdir build; cd build; echo Rc4ml0624@5$ | sudo -S cmake ..;echo Rc4ml0624@5$ | sudo -S make hyperloglog && echo Rc4ml0624@13$ | sudo -S ./hyperloglog ; exit"
# ssh amax2@192.168.189.8 "cd /home/amax2/transfer/amax2; cd src ;mkdir build; cd build; echo Rc4ml0624@5$ | sudo -S cmake ..;echo Rc4ml0624@5$ | sudo -S make amax2_mpireduce && echo Rc4ml0624@13$ | sudo -S ./amax2_mpireduce ; exit"
# # ssh amax6@192.168.189.12 "cd /home/amax6/transfer/amax6; cd src ;mkdir build; cd build; echo Rc4ml0624@13$ | sudo -S cmake ..;echo Rc4ml0624@13$ | sudo -S make amax6 && echo Rc4ml0624@13$ | sudo -S ./amax6 ; exit"
# # ssh amax6@192.168.189.12 "cd /home/amax6/transfer/amax6; cd src ;mkdir build; cd build; echo Rc4ml0624@13$ | sudo -S cmake ..;echo Rc4ml0624@13$ | sudo -S make amax6_tcpbenchmark && echo Rc4ml0624@13$ | sudo -S ./amax6_tcpbenchmark ; exit"
# # ssh amax6@192.168.189.12 "cd /home/amax6/transfer/amax6; cd src ;mkdir build; cd build; echo Rc4ml0624@13$ | sudo -S cmake ..;echo Rc4ml0624@13$ | sudo -S make amax6_tcp_latency6 && echo Rc4ml0624@13$ | sudo -S ./amax6_tcp_latency6 ; exit"
# #		ssh -t amax6@192.168.189.12 " echo Rc4ml0624@13$ | sudo -S reboot"
# #		cd /home/amax4/xdma/sw/src/build && make && sudo ./dma-example