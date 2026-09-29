# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-07-24                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep  9 08:47:58 PM IST 2026

Basic System Information:
---------------------------------
Uptime     : 0 days, 17 hours, 37 minutes
Processor  : Intel(R) Xeon(R) CPU E5-2670 v2 @ 2.50GHz
CPU cores  : 1 @ 2499.992 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 1.4 GiB
Swap       : 2.0 GiB
Disk       : 14.7 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.41+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ❌ Offline
IPv4       : 198.12.123.33

IPv4 Network Information:
---------------------------------
ISP        : HostPapa
ASN        : AS36352 HostPapa
Host       : RackNerd LLC
Location   : Buffalo, New York (NY)
Country    : United States

fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/vda1):
---------------------------------
Block Size | 4k            (IOPS) | 64k           (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 16.10 MB/s    (3.9k) | 177.51 MB/s   (2.7k)
Write      | 16.12 MB/s    (3.9k) | 178.44 MB/s   (2.7k)
Total      | 32.23 MB/s    (7.8k) | 355.95 MB/s   (5.4k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 377.66 MB/s    (720) | 397.45 MB/s    (379)
Write      | 397.73 MB/s    (758) | 423.92 MB/s    (404)
Total      | 775.40 MB/s   (1.4k) | 821.37 MB/s    (783)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 334 Mbits/sec   | 163 Mbits/sec   | 86.1 ms        
Eranium         | Amsterdam, NL (100G)      | 237 Mbits/sec   | 435 Mbits/sec   | 82.7 ms        
Uztelecom       | Tashkent, UZ (10G)        | busy            | 267 Mbits/sec   | 169 ms         
Leaseweb        | Singapore, SG (10G)       | 19.7 Mbits/sec  | 291 Mbits/sec   | 246 ms         
Clouvider       | Los Angeles, CA, US (10G) | 296 Mbits/sec   | 222 Mbits/sec   | 72.2 ms        
Leaseweb        | NYC, NY, US (10G)         | 449 Mbits/sec   | 325 Mbits/sec   | 12.4 ms        
Edgoo           | Sao Paulo, BR (1G)        | 166 Mbits/sec   | 104 Mbits/sec   | 121 ms