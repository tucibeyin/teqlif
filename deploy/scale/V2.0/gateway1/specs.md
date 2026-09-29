# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-07-24                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 16 12:42:29 PM CEST 2026

Basic System Information:
---------------------------------
Uptime     : 9 days, 1 hours, 52 minutes
Processor  : QEMU Virtual CPU version 2.5+
CPU cores  : 2 @ 2294.606 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ❌ Disabled
RAM        : 1.9 GiB
Swap       : 4.0 GiB
Disk       : 58.9 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.107+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ✔ Online
IPv4       : 94.16.105.135

IPv6 Network Information:
---------------------------------
ISP        : netcup GmbH
ASN        : AS197540 netcup GmbH
Host       : NETCUP-GMBH
Location   : Nuremberg, Bavaria (BY)
Country    : Germany

fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/vda4):
---------------------------------
Block Size | 4k            (IOPS) | 64k           (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 65.44 MB/s   (15.9k) | 936.94 MB/s  (14.2k)
Write      | 65.58 MB/s   (16.0k) | 941.87 MB/s  (14.3k)
Total      | 131.02 MB/s  (31.9k) | 1.87 GB/s    (28.6k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 894.36 MB/s   (1.7k) | 922.85 MB/s    (880)
Write      | 941.88 MB/s   (1.7k) | 984.32 MB/s    (938)
Total      | 1.83 GB/s     (3.5k) | 1.90 GB/s     (1.8k)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 781 Mbits/sec   | 924 Mbits/sec   | 25.5 ms        
Eranium         | Amsterdam, NL (100G)      | 1.09 Gbits/sec  | 941 Mbits/sec   | 16.6 ms        
Uztelecom       | Tashkent, UZ (10G)        | 1.05 Gbits/sec  | 852 Mbits/sec   | 70.9 ms        
Leaseweb        | Singapore, SG (10G)       | 961 Mbits/sec   | 732 Mbits/sec   | 162 ms         
Clouvider       | Los Angeles, CA, US (10G) | 921 Mbits/sec   | 315 Mbits/sec   | 174 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.02 Gbits/sec  | 809 Mbits/sec   | 96.9 ms        
Edgoo           | Sao Paulo, BR (1G)        | 873 Mbits/sec   | 445 Mbits/sec   | 220 ms         

iperf3 Network Speed Tests (IPv6):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 1.08 Gbits/sec  | 920 Mbits/sec   | 21.0 ms        
Eranium         | Amsterdam, NL (100G)      | 1.09 Gbits/sec  | 927 Mbits/sec   | 16.6 ms        
Uztelecom       | Tashkent, UZ (10G)        | 1.02 Gbits/sec  | 844 Mbits/sec   | 71.7 ms        
Leaseweb        | Singapore, SG (10G)       | 955 Mbits/sec   | 735 Mbits/sec   | 151 ms         
Clouvider       | Los Angeles, CA, US (10G) | 943 Mbits/sec   | 408 Mbits/sec   | 168 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.03 Gbits/sec  | 774 Mbits/sec   | 99.4 ms        
Edgoo           | Sao Paulo, BR (1G)        | 886 Mbits/sec   | 249 Mbits/sec   | 218 ms