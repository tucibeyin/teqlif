# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-07-24                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 16 04:36:21 AM EDT 2026

Basic System Information:
---------------------------------
Uptime     : 0 days, 0 hours, 1 minutes
Processor  : AMD EPYC 7763 64-Core Processor
CPU cores  : 4 @ 2449.998 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 7.8 GiB
Swap       : 8.0 GiB
Disk       : 49.1 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.41+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ❌ Offline
IPv4       : 45.146.252.165

IPv4 Network Information:
---------------------------------
ISP        : ZAP-Hosting GmbH
ASN        : AS206996 ZAP-Hosting GmbH
Host       : ZAP-Hosting GmbH
Location   : Münster, North Rhine-Westphalia (NW)
Country    : Germany

fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/sda1):
---------------------------------
Block Size | 4k            (IOPS) | 64k           (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 72.66 MB/s   (17.7k) | 764.67 MB/s  (11.6k)
Write      | 72.85 MB/s   (17.7k) | 768.69 MB/s  (11.7k)
Total      | 145.52 MB/s  (35.5k) | 1.53 GB/s    (23.3k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 1.68 GB/s     (3.2k) | 1.35 GB/s     (1.2k)
Write      | 1.77 GB/s     (3.3k) | 1.44 GB/s     (1.3k)
Total      | 3.45 GB/s     (6.5k) | 2.79 GB/s     (2.6k)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 1.03 Gbits/sec  | 978 Mbits/sec   | 9.12 ms        
Eranium         | Amsterdam, NL (100G)      | 1.04 Gbits/sec  | 993 Mbits/sec   | 3.96 ms        
Uztelecom       | Tashkent, UZ (10G)        | 570 Mbits/sec   | 942 Mbits/sec   | 93.8 ms        
Leaseweb        | Singapore, SG (10G)       | 269 Mbits/sec   | 884 Mbits/sec   | 168 ms         
Clouvider       | Los Angeles, CA, US (10G) | 359 Mbits/sec   | 292 Mbits/sec   | 141 ms         
Leaseweb        | NYC, NY, US (10G)         | 334 Mbits/sec   | 928 Mbits/sec   | 86.8 ms        
Edgoo           | Sao Paulo, BR (1G)        | 326 Mbits/sec   | 815 Mbits/sec   | 207 ms         

Geekbench 6 Benchmark Test:
---------------------------------
Test            | Value                         
                |                               
Single Core     |                               
Multi Core      |                               
Full Test       | https://browser.geekbench.com/v6/cpu/19187575

QEMU Standard PC (i440FX + PIIX, 1996)
This result is from Geekbench 6, a legacy version of Geekbench, and can only be compared with other Geekbench 6 results. We recommend Geekbench 7 for testing modern hardware.
1299
Single-Core Score
4251
Multi-Core Score
Geekbench 6.7.1 for Linux AVX2
Result Information
Upload Date	September 16 2026 08:47 AM
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
Size	7.76 GB
Single-Core Performance
Single-Core Score	1299
File Compression	1396
    200.4 MB/sec
Navigation	1173
    7.07 routes/sec
HTML5 Browser	1285
    26.3 pages/sec
PDF Renderer	1335
    30.8 Mpixels/sec
Photo Library	1204
    16.3 images/sec
Clang	1211
    5.96 Klines/sec
Text Processing	1244
    99.6 pages/sec
Asset Compression	1372
    42.5 MB/sec
Object Detection	700
    21.0 images/sec
Background Blur	1759
    7.28 images/sec
Horizon Detection	1802
    56.1 Mpixels/sec
Object Remover	1129
    86.8 Mpixels/sec
HDR	1447
    42.4 Mpixels/sec
Photo Filter	1817
    18.0 images/sec
Ray Tracer	1335
    1.29 Mpixels/sec
Structure from Motion	1515
    48.0 Kpixels/sec
Multi-Core Performance
Multi-Core Score	4251
File Compression	3661
    525.7 MB/sec
Navigation	4271
    25.7 routes/sec
HTML5 Browser	4537
    92.9 pages/sec
PDF Renderer	5353
    123.5 Mpixels/sec
Photo Library	4519
    61.3 images/sec
Clang	4719
    23.2 Klines/sec
Text Processing	1521
    121.8 pages/sec
Asset Compression	5142
    159.3 MB/sec
Object Detection	2470
    73.9 images/sec
Background Blur	5923
    24.5 images/sec
Horizon Detection	5868
    182.6 Mpixels/sec
Object Remover	3751
    288.4 Mpixels/sec
HDR	5016
    147.2 Mpixels/sec
Photo Filter	5974
    59.3 images/sec
Ray Tracer	5287
    5.12 Mpixels/sec
Structure from Motion	5661
    179.2 Kpixels/sec
