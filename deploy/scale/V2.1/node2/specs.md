# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-09-20                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Sep 30 20:00:41 UTC 2026

Basic System Information:
---------------------------------
Uptime     : 0 days, 1 hours, 15 minutes
Processor  : Intel(R) Xeon(R) D-2123IT CPU @ 2.20GHz
CPU cores  : 8 @ 2000.004 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 31.0 GiB
Swap       : 1024.0 MiB
Disk       : 3.6 TiB
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.111+deb13-amd64
VM Type    : NONE
IPv4/IPv6  : ✔ Online / ✔ Online

IPv6 Network Information:
---------------------------------
ISP        : OVH SAS
ASN        : AS16276 OVH SAS
Host       : OVH GmbH
Location   : Saarbrücken, Saarland (SL)
Country    : Germany

fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/md3):
---------------------------------
Block Size | 4k            (IOPS) | 64k           (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 1.81 MB/s      (442) | 17.05 MB/s     (260)
Write      | 1.83 MB/s      (448) | 17.58 MB/s     (268)
Total      | 3.64 MB/s      (890) | 34.64 MB/s     (528)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 53.87 MB/s     (102) | 69.99 MB/s      (66)
Write      | 56.85 MB/s     (108) | 74.65 MB/s      (71)
Total      | 110.73 MB/s    (210) | 144.65 MB/s    (137)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 481 Mbits/sec   | 6.57 Gbits/sec  | 18.8 ms        
Eranium         | Amsterdam, NL (100G)      | 485 Mbits/sec   | 8.77 Gbits/sec  | 9.01 ms        
Uztelecom       | Tashkent, UZ (10G)        | 454 Mbits/sec   | 2.59 Gbits/sec  | 90.5 ms        
Leaseweb        | Singapore, SG (10G)       | 420 Mbits/sec   | 1.43 Gbits/sec  | 163 ms         
Clouvider       | Los Angeles, CA, US (10G) | 102 Mbits/sec   | busy            | 149 ms         
Leaseweb        | NYC, NY, US (10G)         | 455 Mbits/sec   | 2.67 Gbits/sec  | 87.2 ms        
Edgoo           | Sao Paulo, BR (1G)        | 397 Mbits/sec   | 937 Mbits/sec   | 216 ms         

iperf3 Network Speed Tests (IPv6):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 473 Mbits/sec   | 7.02 Gbits/sec  | 18.8 ms        
Eranium         | Amsterdam, NL (100G)      | 478 Mbits/sec   | 8.66 Gbits/sec  | 9.04 ms        
Uztelecom       | Tashkent, UZ (10G)        | 451 Mbits/sec   | 2.53 Gbits/sec  | 92.5 ms        
Leaseweb        | Singapore, SG (10G)       | 429 Mbits/sec   | 1.44 Gbits/sec  | 162 ms         
Clouvider       | Los Angeles, CA, US (10G) | 76.0 Mbits/sec  | 1.38 Gbits/sec  | 150 ms         
Leaseweb        | NYC, NY, US (10G)         | 450 Mbits/sec   | 2.78 Gbits/sec  | 85.7 ms        
Edgoo           | Sao Paulo, BR (1G)        | 345 Mbits/sec   | 227 Mbits/sec   | 216 ms         

Geekbench 6 Benchmark Test:
---------------------------------
Test            | Value                         
                |                               
Single Core     |                               
Multi Core      |                               
Full Test       | https://browser.geekbench.com/v6/cpu/19279974

=== START OF READ SMART DATA SECTION ===
SMART Attributes Data Structure revision number: 16
Vendor Specific SMART Attributes with Thresholds:
ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
  1 Raw_Read_Error_Rate     0x000b   100   100   016    Pre-fail  Always       -       0
  2 Throughput_Performance  0x0005   130   130   054    Pre-fail  Offline      -       100
  3 Spin_Up_Time            0x0007   161   161   024    Pre-fail  Always       -       265 (Average 262)
  4 Start_Stop_Count        0x0012   100   100   000    Old_age   Always       -       108
  5 Reallocated_Sector_Ct   0x0033   100   100   005    Pre-fail  Always       -       0
  7 Seek_Error_Rate         0x000b   100   100   067    Pre-fail  Always       -       0
  8 Seek_Time_Performance   0x0005   128   128   020    Pre-fail  Offline      -       18
  9 Power_On_Hours          0x0012   093   093   000    Old_age   Always       -       55209
 10 Spin_Retry_Count        0x0013   100   100   060    Pre-fail  Always       -       0
 12 Power_Cycle_Count       0x0032   100   100   000    Old_age   Always       -       108
192 Power-Off_Retract_Count 0x0032   083   083   000    Old_age   Always       -       21419
193 Load_Cycle_Count        0x0012   083   083   000    Old_age   Always       -       21419
194 Temperature_Celsius     0x0002   162   162   000    Old_age   Always       -       37 (Min/Max 21/46)
196 Reallocated_Event_Count 0x0032   100   100   000    Old_age   Always       -       0
197 Current_Pending_Sector  0x0022   100   100   000    Old_age   Always       -       0
198 Offline_Uncorrectable   0x0008   100   100   000    Old_age   Offline      -       0
199 UDMA_CRC_Error_Count    0x000a   200   200   000    Old_age   Always       -       0
