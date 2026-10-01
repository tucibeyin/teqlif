# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-09-20                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 30 20:44:21 UTC 2026

Basic System Information:
---------------------------------
Uptime     : 0 days, 0 hours, 20 minutes
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
IPv4/IPv6  : ✔ Online ( 51.75.74.124 ) / ✔ Online

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
Read       | 123.24 MB/s  (30.0k) | 960.46 MB/s  (14.6k)
Write      | 123.56 MB/s  (30.1k) | 965.52 MB/s  (14.7k)
Total      | 246.80 MB/s  (60.2k) | 1.92 GB/s    (29.3k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 1.07 GB/s     (2.0k) | 1.18 GB/s     (1.1k)
Write      | 1.12 GB/s     (2.1k) | 1.26 GB/s     (1.2k)
Total      | 2.20 GB/s     (4.1k) | 2.45 GB/s     (2.3k)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 923 Mbits/sec   | 1.93 Gbits/sec  | 19.1 ms        
Eranium         | Amsterdam, NL (100G)      | 1.95 Gbits/sec  | 1.95 Gbits/sec  | 9.25 ms        
Uztelecom       | Tashkent, UZ (10G)        | 1.83 Gbits/sec  | 1.84 Gbits/sec  | 94.3 ms        
Leaseweb        | Singapore, SG (10G)       | 1.27 Gbits/sec  | 1.43 Gbits/sec  | 163 ms         
Clouvider       | Los Angeles, CA, US (10G) | 157 Mbits/sec   | 1.38 Gbits/sec  | 150 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.83 Gbits/sec  | 1.83 Gbits/sec  | 90.9 ms        
Edgoo           | Sao Paulo, BR (1G)        | 179 Mbits/sec   | 952 Mbits/sec   | 208 ms         

iperf3 Network Speed Tests (IPv6):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 1.91 Gbits/sec  | 1.92 Gbits/sec  | 19.1 ms        
Eranium         | Amsterdam, NL (100G)      | 1.92 Gbits/sec  | 1.92 Gbits/sec  | 9.25 ms        
Uztelecom       | Tashkent, UZ (10G)        | 1.80 Gbits/sec  | 1.81 Gbits/sec  | 89.2 ms        
Leaseweb        | Singapore, SG (10G)       | 1.28 Gbits/sec  | 1.37 Gbits/sec  | 163 ms         
Clouvider       | Los Angeles, CA, US (10G) | 166 Mbits/sec   | 1.31 Gbits/sec  | 150 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.81 Gbits/sec  | 1.82 Gbits/sec  | 89.7 ms        
Edgoo           | Sao Paulo, BR (1G)        | 878 Mbits/sec   | 953 Mbits/sec   | 242 ms