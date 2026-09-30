# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-09-20                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 30 05:11:42 PM EDT 2026

Basic System Information:
---------------------------------
Uptime     : 0 days, 0 hours, 29 minutes
Processor  : AMD EPYC 7763 64-Core Processor
CPU cores  : 4 @ 2449.998 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 7.8 GiB
Swap       : 4.0 GiB
Disk       : 49.1 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.41+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ❌ Offline

IPv4 Network Information:
---------------------------------
ISP        : ZAP-Hosting GmbH
ASN        : AS206996 ZAP-Hosting GmbH
Host       : ZAP-Hosting GmbH
Location   : Münster, North Rhine-Westphalia (NW)
Country    : Germany

fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/sda1):
---------------------------------
Block Size | 4k            (IOPS) | 64k           (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 66.64 MB/s   (16.2k) | 737.04 MB/s  (11.2k)
Write      | 66.76 MB/s   (16.3k) | 740.92 MB/s  (11.3k)
Total      | 133.41 MB/s  (32.5k) | 1.47 GB/s    (22.5k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 1.67 GB/s     (3.1k) | 1.40 GB/s     (1.3k)
Write      | 1.76 GB/s     (3.3k) | 1.49 GB/s     (1.4k)
Total      | 3.44 GB/s     (6.5k) | 2.90 GB/s     (2.7k)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | busy            | 983 Mbits/sec   | 9.56 ms        
Eranium         | Amsterdam, NL (100G)      | 1.01 Gbits/sec  | 987 Mbits/sec   | 3.86 ms        
Uztelecom       | Tashkent, UZ (10G)        | 534 Mbits/sec   | 939 Mbits/sec   | 93.4 ms        
Leaseweb        | Singapore, SG (10G)       | 305 Mbits/sec   | 886 Mbits/sec   | --             
Clouvider       | Los Angeles, CA, US (10G) | 216 Mbits/sec   | busy            | 145 ms         
Leaseweb        | NYC, NY, US (10G)         | 641 Mbits/sec   | 929 Mbits/sec   | 86.5 ms        
Edgoo           | Sao Paulo, BR (1G)        | 241 Mbits/sec   | 849 Mbits/sec   | 205 ms