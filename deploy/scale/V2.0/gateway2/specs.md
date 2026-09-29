# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-09-20                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 23 11:33:44 PM BST 2026

Basic System Information:
---------------------------------
Uptime     : 0 days, 0 hours, 47 minutes
Processor  : Intel(R) Xeon(R) Platinum 8173M CPU @ 2.00GHz
CPU cores  : 2 @ 1995.312 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 9.0 GiB
Swap       : 4.0 GiB
Disk       : 78.7 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.38+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ❌ Offline
IPv4.      : 185.205.194.232

IPv4 Network Information:
---------------------------------
ISP        : Matteo Martelloni trading as DELUXHOST
ASN        : AS214677 Matteo Martelloni trading as DELUXHOST
Host       : DELUXHOST
Location   : Amsterdam, North Holland (NH)
Country    : The Netherlands

fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/vda3):
---------------------------------
Block Size | 4k            (IOPS) | 64k           (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 103.66 MB/s  (25.3k) | 167.73 MB/s   (2.5k)
Write      | 103.93 MB/s  (25.3k) | 168.62 MB/s   (2.5k)
Total      | 207.59 MB/s  (50.6k) | 336.35 MB/s   (5.1k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 203.35 MB/s    (387) | 209.71 MB/s    (200)
Write      | 214.15 MB/s    (408) | 223.68 MB/s    (213)
Total      | 417.51 MB/s    (795) | 433.39 MB/s    (413)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 6.96 Gbits/sec  | 2.05 Gbits/sec  | 14.0 ms        
Eranium         | Amsterdam, NL (100G)      | 4.44 Gbits/sec  | 4.22 Gbits/sec  | 6.98 ms        
Uztelecom       | Tashkent, UZ (10G)        | 2.12 Gbits/sec  | 375 Mbits/sec   | 94.3 ms        
Leaseweb        | Singapore, SG (10G)       | 1.03 Gbits/sec  | 789 Mbits/sec   | 178 ms         
Clouvider       | Los Angeles, CA, US (10G) | 1.18 Gbits/sec  | 259 Mbits/sec   | 143 ms         
Leaseweb        | NYC, NY, US (10G)         | 2.12 Gbits/sec  | 2.05 Gbits/sec  | 95.5 ms        
Edgoo           | Sao Paulo, BR (1G)        | 886 Mbits/sec   | 518 Mbits/sec   | 209 ms