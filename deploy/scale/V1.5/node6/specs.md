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
 
Geekbench 6 Benchmark Test:
---------------------------------
Test            | Value                         
                |                               
Single Core     |                               
Multi Core      |                               
Full Test       | https://browser.geekbench.com/v6/cpu/19244923

 
QEMU Standard PC (i440FX + PIIX, 1996)
This result is from Geekbench 6, a legacy version of Geekbench, and can only be compared with other Geekbench 6 results. We recommend Geekbench 7 for testing modern hardware.
606
Single-Core Score
1390
Multi-Core Score
Geekbench 6.7.1 for Linux AVX2
Result Information
Upload Date	September 23 2026 07:41 PM
Views	1
System Information
System Information	 
Operating System	Debian GNU/Linux 13 (trixie)
Model	QEMU Standard PC (i440FX + PIIX, 1996)
Motherboard	N/A
CPU Information	 
Name	Intel(R) Xeon(R) Platinum 8173M CPU @ 2.00GHz
Topology	3 Processors, 3 Cores
Identifier	GenuineIntel Family 6 Model 85 Stepping 4
Base Frequency	2.00 GHz
Cluster 1	0 Cores
L1 Instruction Cache	32.0 KB x 1
L1 Data Cache	32.0 KB x 1
L2 Cache	1.00 MB x 1
L3 Cache	38.5 MB x 1
Instruction Sets	sse2 sse3 pclmul fma3 sse41 aesni avx avx2 avx512-f avx512-dq avx512-bw avx512-vl
Memory Information	 
Size	7.72 GB
Single-Core Performance
Single-Core Score	606
File Compression	676
    97.1 MB/sec
Navigation	772
    4.65 routes/sec
HTML5 Browser	421
    8.61 pages/sec
PDF Renderer	735
    16.9 Mpixels/sec
Photo Library	570
    7.73 images/sec
Clang	668
    3.29 Klines/sec
Text Processing	366
    29.3 pages/sec
Asset Compression	621
    19.2 MB/sec
Object Detection	297
    8.87 images/sec
Background Blur	923
    3.82 images/sec
Horizon Detection	909
    28.3 Mpixels/sec
Object Remover	547
    42.0 Mpixels/sec
HDR	691
    20.3 Mpixels/sec
Photo Filter	885
    8.78 images/sec
Ray Tracer	552
    534.4 Kpixels/sec
Structure from Motion	776
    24.6 Kpixels/sec
Multi-Core Performance
Multi-Core Score	1390
File Compression	1281
    184.0 MB/sec
Navigation	1963
    11.8 routes/sec
HTML5 Browser	1112
    22.8 pages/sec
PDF Renderer	1978
    45.6 Mpixels/sec
Photo Library	1378
    18.7 images/sec
Clang	1714
    8.44 Klines/sec
Text Processing	446
    35.7 pages/sec
Asset Compression	1514
    46.9 MB/sec
Object Detection	661
    19.8 images/sec
Background Blur	2174
    9.00 images/sec
Horizon Detection	2209
    68.7 Mpixels/sec
Object Remover	1396
    107.3 Mpixels/sec
HDR	1675
    49.2 Mpixels/sec
Photo Filter	1976
    19.6 images/sec
Ray Tracer	1366
    1.32 Mpixels/sec
Structure from Motion	1882
    59.6 Kpixels/sec
