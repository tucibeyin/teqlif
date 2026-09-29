# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-07-24                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 16 05:16:34 AM EDT 2026

Basic System Information:
---------------------------------
Uptime     : 4 days, 3 hours, 30 minutes
Processor  : AMD EPYC 7763 64-Core Processor
CPU cores  : 4 @ 2450.000 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 3.8 GiB
Swap       : 4.0 GiB
Disk       : 49.1 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.107+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ❌ Offline
IPv4       : 5.249.165.10

IPv4 Network Information:
---------------------------------
ISP        : ZAP-Hosting GmbH
ASN        : AS206996 ZAP-Hosting GmbH
Host       : ZAP-Hosting GmbH
Location   : Reston, Virginia (VA)
Country    : United States

fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/sda1):
---------------------------------
Block Size | 4k            (IOPS) | 64k           (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 111.57 MB/s  (27.2k) | 157.53 MB/s   (2.4k)
Write      | 111.87 MB/s  (27.3k) | 158.36 MB/s   (2.4k)
Total      | 223.45 MB/s  (54.5k) | 315.89 MB/s   (4.8k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 150.39 MB/s    (286) | 148.48 MB/s    (141)
Write      | 158.39 MB/s    (302) | 158.36 MB/s    (151)
Total      | 308.78 MB/s    (588) | 306.84 MB/s    (292)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 519 Mbits/sec   | 889 Mbits/sec   | 76.8 ms        
Eranium         | Amsterdam, NL (100G)      | 386 Mbits/sec   | 869 Mbits/sec   | 84.9 ms        
Uztelecom       | Tashkent, UZ (10G)        | 308 Mbits/sec   | 720 Mbits/sec   | 171 ms         
Leaseweb        | Singapore, SG (10G)       | 284 Mbits/sec   | 759 Mbits/sec   | 287 ms         
Clouvider       | Los Angeles, CA, US (10G) | 542 Mbits/sec   | 924 Mbits/sec   | 52.1 ms        
Leaseweb        | NYC, NY, US (10G)         | 1.04 Gbits/sec  | 970 Mbits/sec   | 7.55 ms        
Edgoo           | Sao Paulo, BR (1G)        | 324 Mbits/sec   | 846 Mbits/sec   | 125 ms