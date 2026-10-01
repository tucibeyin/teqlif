# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-09-20                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 30 05:18:03 PM EDT 2026

Basic System Information:
---------------------------------
Uptime     : 0 days, 0 hours, 18 minutes
Processor  : AMD EPYC 7763 64-Core Processor
CPU cores  : 4 @ 2450.000 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 3.8 GiB
Swap       : 4.0 GiB
Disk       : 49.1 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.41+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online ( 5.249.165.10 ) / ❌ Offline

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
Read       | 110.95 MB/s  (27.0k) | 150.23 MB/s   (2.2k)
Write      | 111.24 MB/s  (27.1k) | 151.02 MB/s   (2.3k)
Total      | 222.20 MB/s  (54.2k) | 301.25 MB/s   (4.5k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 150.42 MB/s    (286) | 137.60 MB/s    (131)
Write      | 158.41 MB/s    (302) | 146.77 MB/s    (139)
Total      | 308.83 MB/s    (588) | 284.37 MB/s    (270)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | busy            | 786 Mbits/sec   | 77.2 ms        
Eranium         | Amsterdam, NL (100G)      | 475 Mbits/sec   | 835 Mbits/sec   | 82.4 ms        
Uztelecom       | Tashkent, UZ (10G)        | 286 Mbits/sec   | 750 Mbits/sec   | 173 ms         
Leaseweb        | Singapore, SG (10G)       | 271 Mbits/sec   | 663 Mbits/sec   | 219 ms         
Clouvider       | Los Angeles, CA, US (10G) | busy            | 822 Mbits/sec   | 54.2 ms        
Leaseweb        | NYC, NY, US (10G)         | busy            | 882 Mbits/sec   | 10.4 ms        
Edgoo           | Sao Paulo, BR (1G)        | 269 Mbits/sec   | 842 Mbits/sec   | 140 ms