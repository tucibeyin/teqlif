# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-07-24                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 16 04:36:21 AM EDT 2026

Basic System Information:
---------------------------------
Uptime     : 0 days, 0 hours, 1 minutes
Processor  : AMD EPYC 7763 64-Core Processor
CPU cores  : 4 @ 2449.998 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 7.8 GiB
Swap       : 8.0 GiB
Disk       : 49.1 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.41+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ❌ Offline
IPv4       : 45.146.252.165

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
Read       | 72.66 MB/s   (17.7k) | 764.67 MB/s  (11.6k)
Write      | 72.85 MB/s   (17.7k) | 768.69 MB/s  (11.7k)
Total      | 145.52 MB/s  (35.5k) | 1.53 GB/s    (23.3k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 1.68 GB/s     (3.2k) | 1.35 GB/s     (1.2k)
Write      | 1.77 GB/s     (3.3k) | 1.44 GB/s     (1.3k)
Total      | 3.45 GB/s     (6.5k) | 2.79 GB/s     (2.6k)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 1.03 Gbits/sec  | 978 Mbits/sec   | 9.12 ms        
Eranium         | Amsterdam, NL (100G)      | 1.04 Gbits/sec  | 993 Mbits/sec   | 3.96 ms        
Uztelecom       | Tashkent, UZ (10G)        | 570 Mbits/sec   | 942 Mbits/sec   | 93.8 ms        
Leaseweb        | Singapore, SG (10G)       | 269 Mbits/sec   | 884 Mbits/sec   | 168 ms         
Clouvider       | Los Angeles, CA, US (10G) | 359 Mbits/sec   | 292 Mbits/sec   | 141 ms         
Leaseweb        | NYC, NY, US (10G)         | 334 Mbits/sec   | 928 Mbits/sec   | 86.8 ms        
Edgoo           | Sao Paulo, BR (1G)        | 326 Mbits/sec   | 815 Mbits/sec   | 207 ms