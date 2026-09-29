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