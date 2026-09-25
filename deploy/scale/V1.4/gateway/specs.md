# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-07-24                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 16 12:42:29 PM CEST 2026

Basic System Information:
---------------------------------
Uptime     : 9 days, 1 hours, 52 minutes
Processor  : QEMU Virtual CPU version 2.5+
CPU cores  : 2 @ 2294.606 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ❌ Disabled
RAM        : 1.9 GiB
Swap       : 1024.0 MiB
Disk       : 58.9 GiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.107+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ✔ Online
IPv4       : 94.16.105.135

IPv6 Network Information:
---------------------------------
ISP        : netcup GmbH
ASN        : AS197540 netcup GmbH
Host       : NETCUP-GMBH
Location   : Nuremberg, Bavaria (BY)
Country    : Germany

fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/vda4):
---------------------------------
Block Size | 4k            (IOPS) | 64k           (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 65.44 MB/s   (15.9k) | 936.94 MB/s  (14.2k)
Write      | 65.58 MB/s   (16.0k) | 941.87 MB/s  (14.3k)
Total      | 131.02 MB/s  (31.9k) | 1.87 GB/s    (28.6k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 894.36 MB/s   (1.7k) | 922.85 MB/s    (880)
Write      | 941.88 MB/s   (1.7k) | 984.32 MB/s    (938)
Total      | 1.83 GB/s     (3.5k) | 1.90 GB/s     (1.8k)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 781 Mbits/sec   | 924 Mbits/sec   | 25.5 ms        
Eranium         | Amsterdam, NL (100G)      | 1.09 Gbits/sec  | 941 Mbits/sec   | 16.6 ms        
Uztelecom       | Tashkent, UZ (10G)        | 1.05 Gbits/sec  | 852 Mbits/sec   | 70.9 ms        
Leaseweb        | Singapore, SG (10G)       | 961 Mbits/sec   | 732 Mbits/sec   | 162 ms         
Clouvider       | Los Angeles, CA, US (10G) | 921 Mbits/sec   | 315 Mbits/sec   | 174 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.02 Gbits/sec  | 809 Mbits/sec   | 96.9 ms        
Edgoo           | Sao Paulo, BR (1G)        | 873 Mbits/sec   | 445 Mbits/sec   | 220 ms         

iperf3 Network Speed Tests (IPv6):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 1.08 Gbits/sec  | 920 Mbits/sec   | 21.0 ms        
Eranium         | Amsterdam, NL (100G)      | 1.09 Gbits/sec  | 927 Mbits/sec   | 16.6 ms        
Uztelecom       | Tashkent, UZ (10G)        | 1.02 Gbits/sec  | 844 Mbits/sec   | 71.7 ms        
Leaseweb        | Singapore, SG (10G)       | 955 Mbits/sec   | 735 Mbits/sec   | 151 ms         
Clouvider       | Los Angeles, CA, US (10G) | 943 Mbits/sec   | 408 Mbits/sec   | 168 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.03 Gbits/sec  | 774 Mbits/sec   | 99.4 ms        
Edgoo           | Sao Paulo, BR (1G)        | 886 Mbits/sec   | 249 Mbits/sec   | 218 ms         

Geekbench 6 Benchmark Test:
---------------------------------
Test            | Value                         
                |                               
Single Core     |                               
Multi Core      |                               
Full Test       | https://browser.geekbench.com/v6/cpu/19188316


netcup KVM Server
This result is from Geekbench 6, a legacy version of Geekbench, and can only be compared with other Geekbench 6 results. We recommend Geekbench 7 for testing modern hardware.
586
Single-Core Score
1121
Multi-Core Score
Geekbench 6.7.1 for Linux AVX2
Result Information
Upload Date	September 16 2026 11:02 AM
Views	1
System Information
System Information	
Operating System	Debian GNU/Linux 13 (trixie)
Model	netcup KVM Server
Motherboard	N/A
CPU Information	
Name	QEMU Virtual CPU version 2.5+
Topology	2 Processors, 2 Cores
Identifier	GenuineIntel Family 15 Model 107 Stepping 1
Base Frequency	2.29 GHz
Cluster 1	0 Cores
L1 Instruction Cache	32.0 KB x 1
L1 Data Cache	32.0 KB x 1
L2 Cache	4.00 MB x 1
L3 Cache	16.0 MB x 1
Instruction Sets	sse2 sse3 pclmul fma3 sse41 aesni avx avx2
Memory Information	
Size	1.93 GB
Single-Core Performance
Single-Core Score	586
File Compression	622
    89.4 MB/sec
Navigation	616
    3.71 routes/sec
HTML5 Browser	422
    8.64 pages/sec
PDF Renderer	707
    16.3 Mpixels/sec
Photo Library	597
    8.10 images/sec
Clang	682
    3.36 Klines/sec
Text Processing	378
    30.3 pages/sec
Asset Compression	733
    22.7 MB/sec
Object Detection	301
    9.01 images/sec
Background Blur	918
    3.80 images/sec
Horizon Detection	831
    25.9 Mpixels/sec
Object Remover	493
    37.9 Mpixels/sec
HDR	618
    18.1 Mpixels/sec
Photo Filter	597
    5.93 images/sec
Ray Tracer	682
    660.0 Kpixels/sec
Structure from Motion	722
    22.9 Kpixels/sec
Multi-Core Performance
Multi-Core Score	1121
File Compression	726
    104.2 MB/sec
Navigation	1502
    9.05 routes/sec
HTML5 Browser	810
    16.6 pages/sec
PDF Renderer	1500
    34.6 Mpixels/sec
Photo Library	1177
    16.0 images/sec
Clang	1395
    6.87 Klines/sec
Text Processing	459
    36.8 pages/sec
Asset Compression	1452
    45.0 MB/sec
Object Detection	528
    15.8 images/sec
Background Blur	1850
    7.66 images/sec
Horizon Detection	2112
    65.7 Mpixels/sec
Object Remover	974
    74.9 Mpixels/sec
HDR	1306
    38.3 Mpixels/sec
Photo Filter	1499
    14.9 images/sec
Ray Tracer	1346
    1.30 Mpixels/sec
Structure from Motion	1429
    45.2 Kpixels/sec
