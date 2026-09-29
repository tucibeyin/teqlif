# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-07-24                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 16 10:26:54 UTC 2026

Basic System Information:
---------------------------------
Uptime     : 3 days, 3 hours, 40 minutes
Processor  : Intel Core Processor (Haswell, no TSX)
CPU cores  : 6 @ 3099.996 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 11.4 GiB
Swap       : 2.0 GiB
Disk       : 98.3 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.100+deb13-cloud-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ✔ Online
IPv4       : 51.75.74.124

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
Read       | 123.21 MB/s  (30.0k) | 1.25 GB/s    (19.0k)
Write      | 123.53 MB/s  (30.1k) | 1.25 GB/s    (19.1k)
Total      | 246.75 MB/s  (60.2k) | 2.50 GB/s    (38.2k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 1.25 GB/s     (2.3k) | 1.30 GB/s     (1.2k)
Write      | 1.32 GB/s     (2.5k) | 1.38 GB/s     (1.3k)
Total      | 2.57 GB/s     (4.9k) | 2.69 GB/s     (2.5k)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 1.94 Gbits/sec  | 1.94 Gbits/sec  | 19.0 ms        
Eranium         | Amsterdam, NL (100G)      | 1.95 Gbits/sec  | 1.95 Gbits/sec  | 9.18 ms        
Uztelecom       | Tashkent, UZ (10G)        | 1.83 Gbits/sec  | 1.84 Gbits/sec  | 93.3 ms        
Leaseweb        | Singapore, SG (10G)       | 1.28 Gbits/sec  | 1.40 Gbits/sec  | 164 ms         
Clouvider       | Los Angeles, CA, US (10G) | 263 Mbits/sec   | 1.41 Gbits/sec  | 150 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.83 Gbits/sec  | 1.84 Gbits/sec  | 89.8 ms        
Edgoo           | Sao Paulo, BR (1G)        | 908 Mbits/sec   | 1000 Mbits/sec  | 211 ms         

iperf3 Network Speed Tests (IPv6):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 1.91 Gbits/sec  | 1.92 Gbits/sec  | 18.9 ms        
Eranium         | Amsterdam, NL (100G)      | 1.92 Gbits/sec  | 1.93 Gbits/sec  | 9.18 ms        
Uztelecom       | Tashkent, UZ (10G)        | 1.80 Gbits/sec  | 1.81 Gbits/sec  | 100 ms         
Leaseweb        | Singapore, SG (10G)       | 1.22 Gbits/sec  | 1.41 Gbits/sec  | 164 ms         
Clouvider       | Los Angeles, CA, US (10G) | 313 Mbits/sec   | 1.48 Gbits/sec  | 150 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.80 Gbits/sec  | 1.82 Gbits/sec  | 87.6 ms        
Edgoo           | Sao Paulo, BR (1G)        | 840 Mbits/sec   | 1.03 Gbits/sec  | 213 ms