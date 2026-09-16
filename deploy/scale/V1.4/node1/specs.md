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

Geekbench 6 Benchmark Test:
---------------------------------
Test            | Value                         
                |                               
Single Core     |                               
Multi Core      |                               
Full Test       | https://browser.geekbench.com/v6/cpu/19188443

OpenStack Foundation OpenStack Nova
This result is from Geekbench 6, a legacy version of Geekbench, and can only be compared with other Geekbench 6 results. We recommend Geekbench 7 for testing modern hardware.
974
Single-Core Score
3734
Multi-Core Score
Geekbench 6.7.1 for Linux AVX2
Result Information
Upload Date	September 16 2026 11:18 AM
Views	1
System Information
System Information	
Operating System	Debian GNU/Linux 13 (trixie)
Model	OpenStack Foundation OpenStack Nova
Motherboard	N/A
CPU Information	
Name	Intel Core Processor (Haswell, no TSX)
Topology	6 Processors, 6 Cores
Identifier	GenuineIntel Family 6 Model 60 Stepping 1
Base Frequency	3.10 GHz
Cluster 1	0 Cores
L1 Instruction Cache	32.0 KB x 1
L1 Data Cache	32.0 KB x 1
L2 Cache	4.00 MB x 1
L3 Cache	16.0 MB x 1
Instruction Sets	sse2 sse3 pclmul fma3 sse41 aesni avx avx2
Memory Information	
Size	11.41 GB
Single-Core Performance
Single-Core Score	974
File Compression	937
    134.6 MB/sec
Navigation	985
    5.93 routes/sec
HTML5 Browser	1085
    22.2 pages/sec
PDF Renderer	1133
    26.1 Mpixels/sec
Photo Library	739
    10.0 images/sec
Clang	1147
    5.65 Klines/sec
Text Processing	1131
    90.6 pages/sec
Asset Compression	1233
    38.2 MB/sec
Object Detection	356
    10.7 images/sec
Background Blur	1100
    4.55 images/sec
Horizon Detection	1571
    48.9 Mpixels/sec
Object Remover	671
    51.6 Mpixels/sec
HDR	1143
    33.5 Mpixels/sec
Photo Filter	1015
    10.1 images/sec
Ray Tracer	1189
    1.15 Mpixels/sec
Structure from Motion	1079
    34.2 Kpixels/sec
Multi-Core Performance
Multi-Core Score	3734
File Compression	2084
    299.3 MB/sec
Navigation	4256
    25.6 routes/sec
HTML5 Browser	4284
    87.7 pages/sec
PDF Renderer	5028
    116.0 Mpixels/sec
Photo Library	3577
    48.6 images/sec
Clang	6063
    29.9 Klines/sec
Text Processing	1446
    115.8 pages/sec
Asset Compression	5713
    177.0 MB/sec
Object Detection	1514
    45.3 images/sec
Background Blur	4448
    18.4 images/sec
Horizon Detection	5918
    184.1 Mpixels/sec
Object Remover	2960
    227.6 Mpixels/sec
HDR	4585
    134.5 Mpixels/sec
Photo Filter	3888
    38.6 images/sec
Ray Tracer	6632
    6.42 Mpixels/sec
Structure from Motion	4674
    148.0 Kpixels/sec