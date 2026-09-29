# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-09-20                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
 
Wed Sep 23 08:24:42 PM BST 2026
 
Basic System Information:
---------------------------------
Uptime     : 0 days, 0 hours, 2 minutes
Processor  : Intel(R) Xeon(R) Platinum 8173M CPU @ 2.00GHz
CPU cores  : 3 @ 1995.312 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 7.7 GiB
Swap       : 8.0 GiB
Disk       : 78.7 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.107+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ❌ Offline
IPv4       : 185.205.194.173
 
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
Read       | 78.27 MB/s   (19.1k) | 166.78 MB/s   (2.5k)
Write      | 78.47 MB/s   (19.1k) | 167.66 MB/s   (2.5k)
Total      | 156.75 MB/s  (38.2k) | 334.44 MB/s   (5.1k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 204.40 MB/s    (389) | 221.21 MB/s    (210)
Write      | 215.26 MB/s    (410) | 235.94 MB/s    (225)
Total      | 419.67 MB/s    (799) | 457.15 MB/s    (435)
 
iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 3.89 Gbits/sec  | 2.55 Gbits/sec  | 13.6 ms        
Eranium         | Amsterdam, NL (100G)      | 824 Mbits/sec   | 4.11 Gbits/sec  | 7.35 ms        
Uztelecom       | Tashkent, UZ (10G)        | 2.10 Gbits/sec  | 544 Mbits/sec   | 99.2 ms        
Leaseweb        | Singapore, SG (10G)       | 423 Mbits/sec   | 483 Mbits/sec   | 284 ms         
Clouvider       | Los Angeles, CA, US (10G) | 1.09 Gbits/sec  | 247 Mbits/sec   | 143 ms         
Leaseweb        | NYC, NY, US (10G)         | 2.18 Gbits/sec  | 961 Mbits/sec   | 96.1 ms        
Edgoo           | Sao Paulo, BR (1G)        | 887 Mbits/sec   | 322 Mbits/sec   | 259 ms