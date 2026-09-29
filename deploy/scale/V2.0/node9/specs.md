# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-09-20                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Mon Sep 28 20:37:33 UTC 2026

Basic System Information:
---------------------------------
Uptime     : 0 days, 0 hours, 9 minutes
Processor  : Intel(R) Xeon(R) D-2123IT CPU @ 2.20GHz
CPU cores  : 8 @ 1000.000 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 31.0 GiB
Swap       : 1024.0 MiB
Disk       : 3.6 TiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.107+deb13-amd64
VM Type    : NONE
IPv4/IPv6  : ✔ Online / ✔ Online

NAME          MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINTS
sda             8:0    0   3.6T  0 disk  
├─sda1          8:1    0   511M  0 part  
│ └─md1         9:1    0 510.9M  0 raid1 /boot/efi
├─sda2          8:2    0     1G  0 part  
│ └─md2         9:2    0  1022M  0 raid1 /boot
├─sda3          8:3    0   150G  0 part  
│ └─md3         9:3    0 149.9G  0 raid1 
│   └─vg-root 253:0    0 149.9G  0 lvm   /
├─sda4          8:4    0   512M  0 part  [SWAP]
├─sda5          8:5    0   3.5T  0 part  
│ └─md5         9:5    0   3.5T  0 raid1 /data
└─sda6          8:6    0     2M  0 part  
sdb             8:16   0   3.6T  0 disk  
├─sdb1          8:17   0   511M  0 part  
│ └─md1         9:1    0 510.9M  0 raid1 /boot/efi
├─sdb2          8:18   0     1G  0 part  
│ └─md2         9:2    0  1022M  0 raid1 /boot
├─sdb3          8:19   0   150G  0 part  
│ └─md3         9:3    0 149.9G  0 raid1 
│   └─vg-root 253:0    0 149.9G  0 lvm   /
├─sdb4          8:20   0   512M  0 part  [SWAP]
└─sdb5          8:21   0   3.5T  0 part  
  └─md5         9:5    0   3.5T  0 raid1 /data

IPv6 Network Information:
---------------------------------
ISP        : OVH SAS
ASN        : AS16276 OVH SAS
Host       : OVH GmbH
Location   : Saarbrücken, Saarland (SL)
Country    : Germany

fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/mapper/vg-root):
---------------------------------
Block Size | 4k            (IOPS) | 64k           (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 1.61 MB/s      (393) | 18.12 MB/s     (276)
Write      | 1.64 MB/s      (401) | 18.73 MB/s     (285)
Total      | 3.25 MB/s      (794) | 36.86 MB/s     (561)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 50.33 MB/s      (96) | 65.46 MB/s      (62)
Write      | 52.91 MB/s     (100) | 69.75 MB/s      (66)
Total      | 103.25 MB/s    (196) | 135.22 MB/s    (128)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 479 Mbits/sec   | 6.60 Gbits/sec  | 18.9 ms        
Eranium         | Amsterdam, NL (100G)      | 485 Mbits/sec   | 8.75 Gbits/sec  | 8.98 ms        
Uztelecom       | Tashkent, UZ (10G)        | 454 Mbits/sec   | 2.67 Gbits/sec  | 92.6 ms        
Leaseweb        | Singapore, SG (10G)       | 368 Mbits/sec   | 23.1 Mbits/sec  | 199 ms         
Clouvider       | Los Angeles, CA, US (10G) | 94.3 Mbits/sec  | 1.47 Gbits/sec  | 149 ms         
Leaseweb        | NYC, NY, US (10G)         | 436 Mbits/sec   | 2.65 Gbits/sec  | 87.2 ms        
Edgoo           | Sao Paulo, BR (1G)        | 399 Mbits/sec   | 956 Mbits/sec   | 223 ms         

iperf3 Network Speed Tests (IPv6):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 472 Mbits/sec   | 6.74 Gbits/sec  | 18.9 ms        
Eranium         | Amsterdam, NL (100G)      | 478 Mbits/sec   | 8.66 Gbits/sec  | 8.98 ms        
Uztelecom       | Tashkent, UZ (10G)        | 441 Mbits/sec   | 2.55 Gbits/sec  | 89.4 ms        
Leaseweb        | Singapore, SG (10G)       | 214 Mbits/sec   | 27.5 Mbits/sec  | 205 ms         
Clouvider       | Los Angeles, CA, US (10G) | 68.2 Mbits/sec  | 1.41 Gbits/sec  | 149 ms         
Leaseweb        | NYC, NY, US (10G)         | 444 Mbits/sec   | 2.77 Gbits/sec  | 87.3 ms        
Edgoo           | Sao Paulo, BR (1G)        | 393 Mbits/sec   | 796 Mbits/sec   | 248 ms         
