# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-09-20                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Sun Sep 27 12:46:27 AM BST 2026

Basic System Information:
---------------------------------
Uptime     : 0 days, 0 hours, 18 minutes
Processor  : Intel(R) Xeon(R) CPU E5-2699 v4 @ 2.20GHz
CPU cores  : 2 @ 2197.454 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ❌ Disabled
RAM        : 2.9 GiB
Swap       : 2.0 GiB
Disk       : 993.0 GiB ( 10 GiB SSD + 1TB SATA HDD )
Disk Yapısı:

NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda      8:0    0  368K  1 disk 
sr0     11:0    1 1024M  0 rom  
vda    254:0    0   10G  0 disk 
├─vda1 254:1    0    1M  0 part 
├─vda2 254:2    0  122M  0 part /boot/efi
└─vda3 254:3    0  9.9G  0 part /
vdb    254:16   0 1000G  0 disk /mnt/data

Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.38+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ❌ Offline
IP         : 96.62.250.101

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
Read       | 147.82 MB/s  (36.0k) | 364.38 MB/s   (5.5k)
Write      | 148.21 MB/s  (36.1k) | 366.30 MB/s   (5.5k)
Total      | 296.03 MB/s  (72.2k) | 730.68 MB/s  (11.1k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 949.57 MB/s   (1.8k) | 503.94 MB/s    (480)
Write      | 1.00 GB/s     (1.9k) | 537.50 MB/s    (512)
Total      | 1.94 GB/s     (3.7k) | 1.04 GB/s      (992)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 1.09 Gbits/sec  | 924 Mbits/sec   | 9.15 ms        
Eranium         | Amsterdam, NL (100G)      | 1.08 Gbits/sec  | 920 Mbits/sec   | 3.73 ms        
Uztelecom       | Tashkent, UZ (10G)        | 1.02 Gbits/sec  | busy            | 92.5 ms        
Leaseweb        | Singapore, SG (10G)       | 918 Mbits/sec   | busy            | 170 ms         
Clouvider       | Los Angeles, CA, US (10G) | 960 Mbits/sec   | busy            | 141 ms         
Leaseweb        | NYC, NY, US (10G)         | 911 Mbits/sec   | 850 Mbits/sec   | 84.8 ms        
Edgoo           | Sao Paulo, BR (1G)        | 796 Mbits/sec   | 145 Mbits/sec   | 224 ms