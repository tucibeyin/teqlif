# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-09-20                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 30 20:44:27 UTC 2026

Basic System Information:
---------------------------------
Uptime     : 0 days, 0 hours, 19 minutes
Processor  : Intel Core Processor (Haswell, no TSX)
CPU cores  : 6 @ 3099.996 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 11.4 GiB
Swap       : 4.0 GiB
Disk       : 98.3 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.100+deb13-cloud-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ✔ Online

IPv6 Network Information:
---------------------------------
ISP        : OVH SAS
ASN        : AS16276 OVH SAS
Host       : OVH GmbH
Location   : Frankfurt am Main, Hesse (HE)
Country    : Germany

fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/sda1):
---------------------------------
Block Size | 4k            (IOPS) | 64k           (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 123.24 MB/s  (30.0k) | 1.03 GB/s    (15.8k)
Write      | 123.57 MB/s  (30.1k) | 1.04 GB/s    (15.9k)
Total      | 246.82 MB/s  (60.2k) | 2.07 GB/s    (31.7k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 978.44 MB/s   (1.8k) | 1.00 GB/s      (957)
Write      | 1.03 GB/s     (1.9k) | 1.07 GB/s     (1.0k)
Total      | 2.00 GB/s     (3.8k) | 2.07 GB/s     (1.9k)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 189 Mbits/sec   | 1.88 Gbits/sec  | 19.0 ms        
Eranium         | Amsterdam, NL (100G)      | 1.95 Gbits/sec  | 1.95 Gbits/sec  | 9.18 ms        
Uztelecom       | Tashkent, UZ (10G)        | 1.83 Gbits/sec  | 1.84 Gbits/sec  | 92.5 ms        
Leaseweb        | Singapore, SG (10G)       | 1.25 Gbits/sec  | 1.45 Gbits/sec  | 163 ms         
Clouvider       | Los Angeles, CA, US (10G) | 209 Mbits/sec   | 1.33 Gbits/sec  | 150 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.83 Gbits/sec  | 1.84 Gbits/sec  | 87.4 ms        
Edgoo           | Sao Paulo, BR (1G)        | 869 Mbits/sec   | 192 Mbits/sec   | 211 ms         

iperf3 Network Speed Tests (IPv6):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 1.91 Gbits/sec  | 1.92 Gbits/sec  | 19.0 ms        
Eranium         | Amsterdam, NL (100G)      | 1.92 Gbits/sec  | 1.93 Gbits/sec  | 9.24 ms        
Uztelecom       | Tashkent, UZ (10G)        | 1.79 Gbits/sec  | 1.80 Gbits/sec  | 94.0 ms        
Leaseweb        | Singapore, SG (10G)       | 1.23 Gbits/sec  | 1.36 Gbits/sec  | 163 ms         
Clouvider       | Los Angeles, CA, US (10G) | 92.1 Mbits/sec  | 1.43 Gbits/sec  | 149 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.81 Gbits/sec  | 1.82 Gbits/sec  | 84.9 ms        
Edgoo           | Sao Paulo, BR (1G)        | 822 Mbits/sec   | 72.2 Mbits/sec  | 301 ms 