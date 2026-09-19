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
Swap       : 0.0 KiB
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

Geekbench 6 Benchmark Test:
---------------------------------
Test            | Value                         
                |                               
Single Core     |                               
Multi Core      |                               
Full Test       | https://browser.geekbench.com/v6/cpu/19188195

OpenStack Foundation OpenStack Nova
This result is from Geekbench 6, a legacy version of Geekbench, and can only be compared with other Geekbench 6 results. We recommend Geekbench 7 for testing modern hardware.
1079
Single-Core Score
4660
Multi-Core Score
Geekbench 6.7.1 for Linux AVX2
Result Information
Upload Date	September 16 2026 10:40 AM
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
Single-Core Score	1079
File Compression	1177
    169.1 MB/sec
Navigation	1299
    7.83 routes/sec
HTML5 Browser	1207
    24.7 pages/sec
PDF Renderer	1162
    26.8 Mpixels/sec
Photo Library	777
    10.6 images/sec
Clang	1272
    6.27 Klines/sec
Text Processing	1229
    98.4 pages/sec
Asset Compression	1260
    39.0 MB/sec
Object Detection	361
    10.8 images/sec
Background Blur	1156
    4.78 images/sec
Horizon Detection	1716
    53.4 Mpixels/sec
Object Remover	864
    66.4 Mpixels/sec
HDR	1180
    34.6 Mpixels/sec
Photo Filter	1307
    13.0 images/sec
Ray Tracer	1209
    1.17 Mpixels/sec
Structure from Motion	1124
    35.6 Kpixels/sec
Multi-Core Performance
Multi-Core Score	4660
File Compression	3037
    436.1 MB/sec
Navigation	6102
    36.8 routes/sec
HTML5 Browser	5547
    113.6 pages/sec
PDF Renderer	5942
    137.0 Mpixels/sec
Photo Library	4134
    56.1 images/sec
Clang	6851
    33.7 Klines/sec
Text Processing	1500
    120.1 pages/sec
Asset Compression	6926
    214.6 MB/sec
Object Detection	1877
    56.2 images/sec
Background Blur	5457
    22.6 images/sec
Horizon Detection	7518
    233.9 Mpixels/sec
Object Remover	4321
    332.2 Mpixels/sec
HDR	5883
    172.6 Mpixels/sec
Photo Filter	5455
    54.1 images/sec
Ray Tracer	7127
    6.90 Mpixels/sec
Structure from Motion	5959
    188.7 Kpixels/sec
---
## Güncellemeler
- **Swap:** Benchmark sonrası 8 GiB swap eklendi (2026-09-19)
