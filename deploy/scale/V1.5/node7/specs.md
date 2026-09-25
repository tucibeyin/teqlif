# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-09-20                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Thu Sep 24 12:27:03 AM BST 2026

Basic System Information:
---------------------------------
Uptime     : 0 days, 0 hours, 18 minutes
Processor  : Intel(R) Xeon(R) CPU E5-2699 v4 @ 2.20GHz
CPU cores  : 2 @ 2197.454 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ❌ Disabled
RAM        : 2.9 GiB
Swap       : 4.0 GiB
Disk       : 993.0 GiB ( 10 GiB SSD + 1TB SATA HDD )
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.38+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ❌ Offline
IPv4       : 82.39.86.94

IPv4 Network Information:
---------------------------------
ISP        : Matteo Martelloni trading as DELUXHOST
ASN        : AS214677 Matteo Martelloni trading as DELUXHOST
Host       : DELUXHOST
Location   : Kerkrade, Limburg (LI)
Country    : The Netherlands

fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/vda3):
---------------------------------
Block Size | 4k            (IOPS) | 64k           (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 180.22 MB/s  (43.9k) | 295.59 MB/s   (4.5k)
Write      | 180.69 MB/s  (44.1k) | 297.14 MB/s   (4.5k)
Total      | 360.92 MB/s  (88.1k) | 592.73 MB/s   (9.0k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 379.10 MB/s    (723) | 1.19 GB/s     (1.1k)
Write      | 399.24 MB/s    (761) | 1.26 GB/s     (1.2k)
Total      | 778.35 MB/s   (1.4k) | 2.45 GB/s     (2.3k)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 1.09 Gbits/sec  | 920 Mbits/sec   | 9.51 ms        
Eranium         | Amsterdam, NL (100G)      | 1.10 Gbits/sec  | 919 Mbits/sec   | 3.66 ms        
Uztelecom       | Tashkent, UZ (10G)        | 942 Mbits/sec   | 677 Mbits/sec   | 91.6 ms        
Leaseweb        | Singapore, SG (10G)       | 903 Mbits/sec   | 717 Mbits/sec   | 167 ms         
Clouvider       | Los Angeles, CA, US (10G) | 972 Mbits/sec   | 174 Mbits/sec   | 141 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.02 Gbits/sec  | 842 Mbits/sec   | 98.9 ms        
Edgoo           | Sao Paulo, BR (1G)        | 785 Mbits/sec   | 191 Mbits/sec   | 205 ms         

Geekbench 6 Benchmark Test:
---------------------------------
Test            | Value                         
                |                               
Single Core     |                               
Multi Core      |                               
Full Test       | https://browser.geekbench.com/v6/cpu/19245738

YABS completed in 17 min 16 sec


QEMU Standard PC (i440FX + PIIX, 1996)
This result is from Geekbench 6, a legacy version of Geekbench, and can only be compared with other Geekbench 6 results. We recommend Geekbench 7 for testing modern hardware.
766
Single-Core Score
1328
Multi-Core Score
Geekbench 6.7.1 for Linux AVX2
Result Information
Upload Date	September 23 2026 11:44 PM
Views	1
System Information
System Information	
Operating System	Debian GNU/Linux 13 (trixie)
Model	QEMU Standard PC (i440FX + PIIX, 1996)
Motherboard	N/A
CPU Information	
Name	Intel Xeon E5-2699 v4
Topology	2 Processors, 2 Cores
Identifier	GenuineIntel Family 6 Model 79 Stepping 1
Base Frequency	2.20 GHz
Cluster 1	0 Cores
L1 Instruction Cache	32.0 KB x 1
L1 Data Cache	32.0 KB x 1
L2 Cache	256 KB x 1
L3 Cache	55.0 MB x 1
Instruction Sets	sse2 sse3 pclmul fma3 sse41 aesni avx avx2
Memory Information	
Size	2.87 GB
Single-Core Performance
Single-Core Score	766
File Compression	764
    109.7 MB/sec
Navigation	839
    5.06 routes/sec
HTML5 Browser	847
    17.3 pages/sec
PDF Renderer	848
    19.6 Mpixels/sec
Photo Library	577
    7.83 images/sec
Clang	896
    4.42 Klines/sec
Text Processing	788
    63.1 pages/sec
Asset Compression	941
    29.2 MB/sec
Object Detection	296
    8.87 images/sec
Background Blur	876
    3.63 images/sec
Horizon Detection	1093
    34.0 Mpixels/sec
Object Remover	590
    45.4 Mpixels/sec
HDR	847
    24.8 Mpixels/sec
Photo Filter	966
    9.58 images/sec
Ray Tracer	841
    813.7 Kpixels/sec
Structure from Motion	891
    28.2 Kpixels/sec
Multi-Core Performance
Multi-Core Score	1328
File Compression	719
    103.3 MB/sec
Navigation	1628
    9.81 routes/sec
HTML5 Browser	1584
    32.4 pages/sec
PDF Renderer	1757
    40.5 Mpixels/sec
Photo Library	1089
    14.8 images/sec
Clang	1830
    9.01 Klines/sec
Text Processing	893
    71.6 pages/sec
Asset Compression	1822
    56.5 MB/sec
Object Detection	503
    15.0 images/sec
Background Blur	1728
    7.15 images/sec
Horizon Detection	1718
    53.5 Mpixels/sec
Object Remover	1143
    87.9 Mpixels/sec
HDR	1560
    45.8 Mpixels/sec
Photo Filter	1658
    16.5 images/sec
Ray Tracer	1795
    1.74 Mpixels/sec
Structure from Motion	1649
    52.2 Kpixels/sec
