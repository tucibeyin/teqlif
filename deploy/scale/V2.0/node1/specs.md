# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-07-24                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 16 11:04:42 UTC 2026

Basic System Information:
---------------------------------
Uptime     : 12 days, 1 hours, 55 minutes
Processor  : Intel Core Processor (Haswell, no TSX)
CPU cores  : 6 @ 3099.996 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 11.4 GiB
Swap       : 2.0 GiB
Disk       : 98.3 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.107+deb13-cloud-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ✔ Online
IPv4       : 135.125.175.223

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
Read       | 123.12 MB/s  (30.0k) | 1.01 GB/s    (15.5k)
Write      | 123.45 MB/s  (30.1k) | 1.02 GB/s    (15.5k)
Total      | 246.58 MB/s  (60.2k) | 2.03 GB/s    (31.0k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 1.03 GB/s     (1.9k) | 1.02 GB/s      (974)
Write      | 1.08 GB/s     (2.0k) | 1.08 GB/s     (1.0k)
Total      | 2.12 GB/s     (4.0k) | 2.11 GB/s     (2.0k)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 1.94 Gbits/sec  | 1.94 Gbits/sec  | 18.9 ms        
Eranium         | Amsterdam, NL (100G)      | 1.95 Gbits/sec  | 1.95 Gbits/sec  | 9.21 ms        
Uztelecom       | Tashkent, UZ (10G)        | 1.82 Gbits/sec  | 1.83 Gbits/sec  | 90.6 ms        
Leaseweb        | Singapore, SG (10G)       | 1.26 Gbits/sec  | 1.39 Gbits/sec  | 164 ms         
Clouvider       | Los Angeles, CA, US (10G) | 384 Mbits/sec   | 1.38 Gbits/sec  | 150 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.83 Gbits/sec  | 1.85 Gbits/sec  | 87.4 ms        
Edgoo           | Sao Paulo, BR (1G)        | 918 Mbits/sec   | 1.06 Gbits/sec  | 209 ms         

iperf3 Network Speed Tests (IPv6):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 1.91 Gbits/sec  | 1.92 Gbits/sec  | 19.0 ms        
Eranium         | Amsterdam, NL (100G)      | 1.93 Gbits/sec  | 1.93 Gbits/sec  | 9.22 ms        
Uztelecom       | Tashkent, UZ (10G)        | 1.74 Gbits/sec  | 1.81 Gbits/sec  | 90.6 ms        
Leaseweb        | Singapore, SG (10G)       | 1.23 Gbits/sec  | 1.38 Gbits/sec  | 163 ms         
Clouvider       | Los Angeles, CA, US (10G) | 517 Mbits/sec   | 1.37 Gbits/sec  | 150 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.81 Gbits/sec  | 1.82 Gbits/sec  | 84.7 ms        
Edgoo           | Sao Paulo, BR (1G)        | 872 Mbits/sec   | 980 Mbits/sec   | 216 ms