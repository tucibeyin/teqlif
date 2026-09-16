# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-07-24                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 16 05:16:34 AM EDT 2026

Basic System Information:
---------------------------------
Uptime     : 4 days, 3 hours, 30 minutes
Processor  : AMD EPYC 7763 64-Core Processor
CPU cores  : 4 @ 2450.000 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 3.8 GiB
Swap       : 4.0 GiB
Disk       : 49.1 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.107+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ❌ Offline

IPv4 Network Information:
---------------------------------
ISP        : ZAP-Hosting GmbH
ASN        : AS206996 ZAP-Hosting GmbH
Host       : ZAP-Hosting GmbH
Location   : Reston, Virginia (VA)
Country    : United States

fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/sda1):
---------------------------------
Block Size | 4k            (IOPS) | 64k           (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 111.57 MB/s  (27.2k) | 157.53 MB/s   (2.4k)
Write      | 111.87 MB/s  (27.3k) | 158.36 MB/s   (2.4k)
Total      | 223.45 MB/s  (54.5k) | 315.89 MB/s   (4.8k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 150.39 MB/s    (286) | 148.48 MB/s    (141)
Write      | 158.39 MB/s    (302) | 158.36 MB/s    (151)
Total      | 308.78 MB/s    (588) | 306.84 MB/s    (292)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 519 Mbits/sec   | 889 Mbits/sec   | 76.8 ms        
Eranium         | Amsterdam, NL (100G)      | 386 Mbits/sec   | 869 Mbits/sec   | 84.9 ms        
Uztelecom       | Tashkent, UZ (10G)        | 308 Mbits/sec   | 720 Mbits/sec   | 171 ms         
Leaseweb        | Singapore, SG (10G)       | 284 Mbits/sec   | 759 Mbits/sec   | 287 ms         
Clouvider       | Los Angeles, CA, US (10G) | 542 Mbits/sec   | 924 Mbits/sec   | 52.1 ms        
Leaseweb        | NYC, NY, US (10G)         | 1.04 Gbits/sec  | 970 Mbits/sec   | 7.55 ms        
Edgoo           | Sao Paulo, BR (1G)        | 324 Mbits/sec   | 846 Mbits/sec   | 125 ms         

Geekbench 6 Benchmark Test:
---------------------------------
Test            | Value                         
                |                               
Single Core     |                               
Multi Core      |                               
Full Test       | https://browser.geekbench.com/v6/cpu/19187829


QEMU Standard PC (i440FX + PIIX, 1996)
This result is from Geekbench 6, a legacy version of Geekbench, and can only be compared with other Geekbench 6 results. We recommend Geekbench 7 for testing modern hardware.
1134
Single-Core Score
3515
Multi-Core Score
Geekbench 6.7.1 for Linux AVX2
Result Information
Upload Date	September 16 2026 09:28 AM
Views	1
System Information
System Information	
Operating System	Debian GNU/Linux 13 (trixie)
Model	QEMU Standard PC (i440FX + PIIX, 1996)
Motherboard	N/A
CPU Information	
Name	AMD EPYC 7763
Topology	1 Processor, 4 Cores
Identifier	AuthenticAMD Family 25 Model 1 Stepping 1
Base Frequency	2.45 GHz
Cluster 1	0 Cores
L1 Instruction Cache	64.0 KB x 4
L1 Data Cache	64.0 KB x 4
L2 Cache	512 KB x 4
L3 Cache	16.0 MB x 1
Instruction Sets	sse2 sse3 pclmul fma3 sse41 aesni avx avx2 shani vaes
Memory Information	
Size	3.83 GB
Single-Core Performance
Single-Core Score	1134
File Compression	1023
    146.9 MB/sec
Navigation	792
    4.77 routes/sec
HTML5 Browser	1120
    22.9 pages/sec
PDF Renderer	1177
    27.1 Mpixels/sec
Photo Library	1111
    15.1 images/sec
Clang	1182
    5.82 Klines/sec
Text Processing	1175
    94.1 pages/sec
Asset Compression	1333
    41.3 MB/sec
Object Detection	680
    20.3 images/sec
Background Blur	1677
    6.94 images/sec
Horizon Detection	1638
    51.0 Mpixels/sec
Object Remover	851
    65.5 Mpixels/sec
HDR	1315
    38.6 Mpixels/sec
Photo Filter	1236
    12.3 images/sec
Ray Tracer	1320
    1.28 Mpixels/sec
Structure from Motion	1388
    43.9 Kpixels/sec
Multi-Core Performance
Multi-Core Score	3515
File Compression	2452
    352.1 MB/sec
Navigation	2943
    17.7 routes/sec
HTML5 Browser	3864
    79.1 pages/sec
PDF Renderer	4016
    92.6 Mpixels/sec
Photo Library	4077
    55.3 images/sec
Clang	4473
    22.0 Klines/sec
Text Processing	1610
    129.0 pages/sec
Asset Compression	4963
    153.8 MB/sec
Object Detection	2255
    67.5 images/sec
Background Blur	5772
    23.9 images/sec
Horizon Detection	5248
    163.3 Mpixels/sec
Object Remover	2727
    209.7 Mpixels/sec
HDR	3909
    114.7 Mpixels/sec
Photo Filter	2824
    28.0 images/sec
Ray Tracer	5031
    4.87 Mpixels/sec
Structure from Motion	4588
    145.3 Kpixels/sec