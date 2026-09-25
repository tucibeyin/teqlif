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

Geekbench 6 Benchmark Test:
---------------------------------
Test            | Value                         
                |                               
Single Core     |                               
Multi Core      |                               
Full Test       | https://browser.geekbench.com/v6/cpu/19245571

YABS completed in 18 min 16 sec


QEMU Standard PC (i440FX + PIIX, 1996)
This result is from Geekbench 6, a legacy version of Geekbench, and can only be compared with other Geekbench 6 results. We recommend Geekbench 7 for testing modern hardware.
559
Single-Core Score
1021
Multi-Core Score
Geekbench 6.7.1 for Linux AVX2
Result Information
Upload Date	September 23 2026 10:51 PM
Views	1
System Information
System Information	
Operating System	Debian GNU/Linux 13 (trixie)
Model	QEMU Standard PC (i440FX + PIIX, 1996)
Motherboard	N/A
CPU Information	
Name	Intel(R) Xeon(R) Platinum 8173M CPU @ 2.00GHz
Topology	2 Processors, 2 Cores
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
Single-Core Score	559
File Compression	640
  91.9 MB/sec
Navigation	708
  4.26 routes/sec
HTML5 Browser	398
  8.14 pages/sec
PDF Renderer	696
  16.1 Mpixels/sec
Photo Library	503
  6.83 images/sec
Clang	593
  2.92 Klines/sec
Text Processing	381
  30.5 pages/sec
Asset Compression	565
  17.5 MB/sec
Object Detection	260
  7.78 images/sec
Background Blur	860
  3.56 images/sec
Horizon Detection	891
  27.7 Mpixels/sec
Object Remover	467
  35.9 Mpixels/sec
HDR	623
  18.3 Mpixels/sec
Photo Filter	814
  8.08 images/sec
Ray Tracer	532
  514.9 Kpixels/sec
Structure from Motion	692
  21.9 Kpixels/sec
Multi-Core Performance
Multi-Core Score	1021
File Compression	851
  122.2 MB/sec
Navigation	1461
  8.80 routes/sec
HTML5 Browser	860
  17.6 pages/sec
PDF Renderer	1478
  34.1 Mpixels/sec
Photo Library	1042
  14.1 images/sec
Clang	1238
  6.10 Klines/sec
Text Processing	395
  31.7 pages/sec
Asset Compression	1130
  35.0 MB/sec
Object Detection	477
  14.3 images/sec
Background Blur	1607
  6.65 images/sec
Horizon Detection	1608
  50.0 Mpixels/sec
Object Remover	894
  68.7 Mpixels/sec
HDR	1186
  34.8 Mpixels/sec
Photo Filter	1483
  14.7 images/sec
Ray Tracer	982
  949.9 Kpixels/sec
Structure from Motion	1285
  40.7 Kpixels/sec
