# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-09-20                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 30 20:00:37 UTC 2026

Basic System Information:
---------------------------------
Uptime     : 0 days, 2 hours, 15 minutes
Processor  : Intel(R) Xeon(R) E-2236 CPU @ 3.40GHz
CPU cores  : 12 @ 800.000 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 31.1 GiB
Swap       : 1024.0 MiB
Disk       : 467.8 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.111+deb13-amd64
VM Type    : NONE
IPv4/IPv6  : ✔ Online / ✔ Online

IPv6 Network Information:
---------------------------------
ISP        : OVH SAS
ASN        : AS16276 OVH SAS
Host       : OVH
Location   : Gravelines, Hauts-de-France (HDF)
Country    : France

fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/md3):
---------------------------------
Block Size | 4k            (IOPS) | 64k           (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 675.05 MB/s (164.8k) | 1.22 GB/s    (18.6k)
Write      | 676.83 MB/s (165.2k) | 1.22 GB/s    (18.7k)
Total      | 1.35 GB/s   (330.0k) | 2.44 GB/s    (37.3k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 834.42 MB/s   (1.5k) | 890.43 MB/s    (849)
Write      | 878.76 MB/s   (1.6k) | 949.73 MB/s    (905)
Total      | 1.71 GB/s     (3.2k) | 1.84 GB/s     (1.7k)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 940 Mbits/sec   | 941 Mbits/sec   | 3.91 ms        
Eranium         | Amsterdam, NL (100G)      | 939 Mbits/sec   | 940 Mbits/sec   | 6.65 ms        
Uztelecom       | Tashkent, UZ (10G)        | 879 Mbits/sec   | 815 Mbits/sec   | 101 ms         
Leaseweb        | Singapore, SG (10G)       | 826 Mbits/sec   | 634 Mbits/sec   | 165 ms         
Clouvider       | Los Angeles, CA, US (10G) | 127 Mbits/sec   | 476 Mbits/sec   | 144 ms         
Leaseweb        | NYC, NY, US (10G)         | 895 Mbits/sec   | 760 Mbits/sec   | 77.5 ms        
Edgoo           | Sao Paulo, BR (1G)        | 701 Mbits/sec   | 464 Mbits/sec   | 213 ms         

iperf3 Network Speed Tests (IPv6):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 927 Mbits/sec   | 928 Mbits/sec   | 3.82 ms        
Eranium         | Amsterdam, NL (100G)      | 926 Mbits/sec   | 927 Mbits/sec   | 6.51 ms        
Uztelecom       | Tashkent, UZ (10G)        | 806 Mbits/sec   | 742 Mbits/sec   | 99.5 ms        
Leaseweb        | Singapore, SG (10G)       | 815 Mbits/sec   | 642 Mbits/sec   | 165 ms         
Clouvider       | Los Angeles, CA, US (10G) | 206 Mbits/sec   | 636 Mbits/sec   | 144 ms         
Leaseweb        | NYC, NY, US (10G)         | 884 Mbits/sec   | 747 Mbits/sec   | 81.0 ms        
Edgoo           | Sao Paulo, BR (1G)        | 677 Mbits/sec   | 526 Mbits/sec   | 253 ms         

Geekbench 6 Benchmark Test:
---------------------------------
Test            | Value                         
                |                               
Single Core     |                               
Multi Core      |                               
Full Test       | https://browser.geekbench.com/v6/cpu/19279963

YABS completed in 12 min 13 sec

Smart Log for NVME device:nvme0n1 namespace-id:ffffffff
critical_warning			: 0
temperature				: 38 °C (311 K)
available_spare				: 100%
available_spare_threshold		: 10%
percentage_used				: 9%
endurance group critical warning summary: 0
Data Units Read				: 70810925 (36.26 TB)
Data Units Written			: 52204224 (26.73 TB)
host_read_commands			: 455052962
host_write_commands			: 2308544624
controller_busy_time			: 5655
power_cycles				: 61
power_on_hours				: 39603
unsafe_shutdowns			: 55
media_errors				: 0
num_err_log_entries			: 0
Warning Temperature Time		: 0
Critical Composite Temperature Time	: 0
Thermal Management T1 Trans Count	: 0
Thermal Management T2 Trans Count	: 0
Thermal Management T1 Total Time	: 0
Thermal Management T2 Total Time	: 0
Smart Log for NVME device:nvme1n1 namespace-id:ffffffff
critical_warning			: 0
temperature				: 37 °C (310 K)
available_spare				: 100%
available_spare_threshold		: 10%
percentage_used				: 37%
endurance group critical warning summary: 0
Data Units Read				: 106989159 (54.78 TB)
Data Units Written			: 432211994 (221.29 TB)
host_read_commands			: 499651210
host_write_commands			: 2900182143
controller_busy_time			: 7364
power_cycles				: 69
power_on_hours				: 48522
unsafe_shutdowns			: 66
media_errors				: 0
num_err_log_entries			: 0
Warning Temperature Time		: 0
Critical Composite Temperature Time	: 0
Thermal Management T1 Trans Count	: 0
Thermal Management T2 Trans Count	: 0
Thermal Management T1 Total Time	: 0
Thermal Management T2 Total Time	: 0
