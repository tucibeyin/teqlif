# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#              Yet-Another-Bench-Script              #
#                     v2026-10-31                    #
# https://github.com/masonr/yet-another-bench-script #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Wed Nov 11 04:32:37 AM GMT 2026

Basic System Information:
---------------------------------
Uptime     : 23 days, 15 hours, 59 minutes
Processor  : Intel(R) Xeon(R) CPU E5-2699 v4 @ 2.20GHz
CPU cores  : 2 @ 2197.454 MHz
AES-NI     : ✔ Enabled
VM-x/AMD-V : ✔ Enabled
RAM        : 2.9 GiB
Swap       : 1024.0 MiB
Disk       : 10 GB SSD (vda) + 1000 GB HDD (vdb -> /mnt/data) 
Distro     : Debian GNU/Linux 13 (trixie)
Kernel     : 6.12.111+deb13-amd64
VM Type    : KVM
IPv4/IPv6  : ✔ Online / ❌ Offline

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
Read       | 164.08 MB/s  (40.0k) | 1.61 GB/s    (24.7k)
Write      | 164.52 MB/s  (40.1k) | 1.62 GB/s    (24.8k)
Total      | 328.61 MB/s  (80.2k) | 3.24 GB/s    (49.5k)
           |                      |                     
Block Size | 512k          (IOPS) | 1m            (IOPS)
  ------   | ---            ----  | ----           ---- 
Read       | 1.75 GB/s     (3.3k) | 1.77 GB/s     (1.6k)
Write      | 1.84 GB/s     (3.5k) | 1.89 GB/s     (1.8k)
Total      | 3.60 GB/s     (6.8k) | 3.67 GB/s     (3.5k)

iperf3 Network Speed Tests (IPv4):
---------------------------------
Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping           
-----           | -----                     | ----            | ----            | ----           
Clouvider       | London, UK (10G)          | 1.06 Gbits/sec  | 921 Mbits/sec   | 9.23 ms        
Eranium         | Amsterdam, NL (100G)      | 1.10 Gbits/sec  | 914 Mbits/sec   | 3.50 ms        
Uztelecom       | Tashkent, UZ (10G)        | 978 Mbits/sec   | 705 Mbits/sec   | 90.9 ms        
Leaseweb        | Singapore, SG (10G)       | 969 Mbits/sec   | 661 Mbits/sec   | 160 ms         
Clouvider       | Los Angeles, CA, US (10G) | 950 Mbits/sec   | 173 Mbits/sec   | 153 ms         
Leaseweb        | NYC, NY, US (10G)         | 1.01 Gbits/sec  | 792 Mbits/sec   | 84.4 ms        
Edgoo           | Sao Paulo, BR (1G)        | busy            | busy            | 204 ms         

Geekbench 6 Benchmark Test:
---------------------------------
Test            | Value                         
                |                               
Single Core     | 676                           
Multi Core      | 1165                          
Full Test       | https://browser.geekbench.com/v6/cpu/19459446

YABS completed in 17 min 28 sec

---

## `/mnt/data` (`/dev/vdb` `984G ext4`) Ek `fio-3.39` Benchmark (Wed Nov 11 05:23–05:25 UTC 2026)

> YABS yalnızca `/dev/vda3` sistem diskini ölçtüğü için asıl yedek diski `/mnt/data` (`/dev/vdb`) ayrı ölçülmüştür.

### 1. Sıralı 1M R/W (`--size=2G --bs=1M --iodepth=8 --direct=1 --rw=readwrite --rwmixwrite=50`)
- **READ:** `137 MiB/s` (`144 MB/s`), `IOPS=137`, `clat` `p50=922 usec` (`0.92 ms`), `p95=33.2 ms`, `p99=53.2 ms`, `max=446 ms`
- **WRITE:** `145 MiB/s` (`153 MB/s`), `IOPS=145`, `clat` `p50=52.2 ms`, `p95=54.3 ms`, `p99=56.4 ms`, `max=446 ms`
- **Disk stats (`vdb`):** `util=98.58%`

### 2. Rastgele 4K R/W (`--size=1G --bs=4k --iodepth=32 --direct=1 --rw=randrw --rwmixwrite=50`)
- **READ:** **`27.4k IOPS`**, `107 MiB/s` (`112 MB/s`), `clat` `avg=537.9 usec`, `p50=469 usec`, `p99=1.53 ms`, `max=18.6 ms`
- **WRITE:** **`27.4k IOPS`**, `107 MiB/s` (`112 MB/s`), `clat` `avg=614.1 usec`, `p50=537 usec`, `p99=1.76 ms`, `max=19.9 ms`
- **Disk stats (`vdb`):** `util=93.44%`

### 3. Senkron 64K `fdatasync` (`--size=256M --bs=64k --iodepth=1 --ioengine=sync --fdatasync=1 --rw=write`)
- **WRITE (`fdatasync=1`):** `83 IOPS`, **`5321 KiB/s` (`5.45 MB/s`)**, total `49.3 sn`
- **`write` `clat`:** `avg=179.3 usec`, `p99=506 usec`
- **`fdatasync` latency (`sync`):** `min=1.63 ms`, `p50=2.51 ms`, `p90=3.72 ms`, **`p95=60.56 ms`**, **`p99=229.6 ms`**, **`p99.9=480.2 ms`**, **`max=871.9 ms`**

### Disk Alanı (Test Temizliği Sonrası)
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda3       9.7G  3.3G  6.1G  36% /
/dev/vdb        984G  2.1M  934G   1% /mnt/data
```

### Mühendislik Yorumu
- `/dev/vdb` virtio üzerinden `ROTA=1` (HDD) bildirse de **54.8k toplam 4K rastgele IOPS (`~0.5 ms` p50) ve `~144–153 MB/s` sıralı aktarım** değerleriyle host katmanında güçlü SSD/NVMe cache destekli bir depolama davranışı göstermektedir (`~150 MB/s` sıralı tavan 1 Gbps ağ hattını boğmaz).
- Buna karşın **her 64K blokta senkron `fdatasync` (`83 IOPS / 5.45 MB/s`, `p99=230ms`, `max=872ms`)** çok sert düşmektedir; bu sonuç **`rclone`/SFTP dosya-dosya senkronu yerine büyük pack dosyaları (`--pack-size 32` MiB) yazan `restic` + `rest-server` mimarisinin doğruluğunu** kesinleştirmektedir.
