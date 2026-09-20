#!/var/www/teqlif.com/venv/bin/python3
# deploy/scale/V1.4/scripts/teqlif-healthcheck.py
#
# Teqlif günlük sistem sağlık raporu.
# Her gün 06:00 UTC (09:00 TRT) çalışır, Telegram'a gönderir.
# node5'te root olarak çalışır (systemd User=root).

import asyncio
import glob
import os
import re
import subprocess
import time
import urllib.parse
from datetime import datetime, timezone, timedelta

import httpx

# ─────────────────────────────────────────────────────────────────────────────
# Credential / ortam okuyucu
# ─────────────────────────────────────────────────────────────────────────────
_ENV_FILE = "/var/www/teqlif.com/backend/.env.production"

def _env(key: str, default: str = "") -> str:
    try:
        with open(_ENV_FILE) as f:
            for line in f:
                line = line.strip()
                if line.startswith(f"{key}="):
                    v = line[len(key) + 1:].strip().strip('"').strip("'")
                    return v if v else default
    except Exception:
        pass
    return default

TG_TOKEN     = _env("TELEGRAM_BOT_TOKEN")
TG_CHAT      = _env("TELEGRAM_CHAT_ID")
REDIS_URL    = _env("REDIS_URL")
DB_URL       = _env("DATABASE_URL")
LK_KEY       = _env("LIVEKIT_API_KEY")
LK_SECRET    = _env("LIVEKIT_API_SECRET")
EDGE_LK      = [u.strip() for u in _env("EDGE_LIVEKIT_URLS", "http://10.10.0.1:7880,http://10.10.0.6:7880").split(",")]
EDGE_MINIO   = [u.strip() for u in _env("EDGE_MINIO_URLS",   "http://10.10.0.1:9010,http://10.10.0.6:9010").split(",")]

PROMETHEUS   = "http://10.10.0.4:9090"
LOKI         = "http://10.10.0.4:3100"
BACKUP_DIR   = "/var/backups/teqlif"
ZAP_DEADLINE = datetime(2026, 12, 10, tzinfo=timezone.utc)

IP_TO_NODE = {
    "10.10.0.2": "gateway", "10.10.0.1": "node1",
    "10.10.0.3": "node2",   "10.10.0.4": "node3",
    "10.10.0.5": "node5",   "10.10.0.6": "node4",
}
NODE5_SVCS = [
    "postgresql", "redis-server", "clickhouse-server",
    "teqlif", "teqlif-worker", "teqlif-worker-critical",
    "node_exporter", "promtail",
]

# ─────────────────────────────────────────────────────────────────────────────
# Yardımcılar
# ─────────────────────────────────────────────────────────────────────────────
def _age(seconds: int) -> str:
    if seconds < 60:   return f"{seconds}s"
    if seconds < 3600: return f"{seconds // 60}dk {seconds % 60}s"
    return f"{seconds // 3600}s {(seconds % 3600) // 60}dk"

def _gb(b: float) -> str:
    return f"{b / 1024 ** 3:.1f}"

def _mb(b: float) -> str:
    return f"{int(b / 1024 ** 2)}MB"

async def _prom(client: httpx.AsyncClient, query: str) -> list:
    try:
        r = await client.get(f"{PROMETHEUS}/api/v1/query",
                             params={"query": query}, timeout=6)
        return r.json().get("data", {}).get("result", [])
    except Exception:
        return []

def _parse_db_url(raw: str):
    """DATABASE_URL'i asyncpg.connect() parametrelerine ayırır."""
    url = raw.replace("postgresql+asyncpg://", "postgresql://")
    if "?" in url:
        url = url.split("?")[0]
    p = urllib.parse.urlparse(url)
    return {
        "user":     urllib.parse.unquote(p.username or "postgres"),
        "password": urllib.parse.unquote(p.password or ""),
        "host":     p.hostname or "127.0.0.1",
        "port":     p.port or 5432,
        "database": p.path.lstrip("/") or "teqlif",
    }

# ─────────────────────────────────────────────────────────────────────────────
# 1. WireGuard
# ─────────────────────────────────────────────────────────────────────────────
def section_wireguard() -> str:
    lines = ["📡 <b>WireGuard</b>"]
    try:
        r = subprocess.run(["wg", "show", "wg0", "dump"],
                           capture_output=True, text=True, timeout=5)
        if r.returncode != 0:
            return "📡 <b>WireGuard</b>\n⚠️ wg show başarısız"
        now = int(time.time())
        rows = []
        for line in r.stdout.strip().splitlines()[1:]:
            parts = line.split("\t")
            if len(parts) < 5:
                continue
            allowed = parts[3]
            hs_raw  = parts[4]
            m = re.search(r"10\.10\.0\.\d+", allowed)
            if not m:
                continue
            node = IP_TO_NODE.get(m.group(), m.group())
            hs = int(hs_raw) if hs_raw.isdigit() else 0
            if hs == 0:
                rows.append((node, f"🔴 {node:<9} handshake yok"))
            else:
                age = now - hs
                icon = "✅" if age < 180 else ("⚠️" if age < 600 else "🔴")
                rows.append((node, f"{icon} {node:<9} {_age(age)}"))
        for _, line in sorted(rows):
            lines.append(line)
    except Exception as exc:
        lines.append(f"⚠️ {exc}")
    return "\n".join(lines)

# ─────────────────────────────────────────────────────────────────────────────
# 2. node5 Servisler
# ─────────────────────────────────────────────────────────────────────────────
def section_node5() -> str:
    lines = ["🖥️ <b>Servisler — node5</b>"]
    try:
        for svc in NODE5_SVCS:
            target = svc
            if svc == "postgresql":
                r = subprocess.run(
                    ["systemctl", "list-units", "postgresql@*",
                     "--no-legend", "--state=active"],
                    capture_output=True, text=True)
                if r.stdout.strip():
                    target = r.stdout.strip().split()[0]

            raw = subprocess.run(
                ["systemctl", "show", "-p",
                 "ActiveState,MemoryCurrent,ActiveEnterTimestamp", target],
                capture_output=True, text=True).stdout
            props = {k: v for k, v in
                     (l.split("=", 1) for l in raw.strip().splitlines() if "=" in l)}
            state = props.get("ActiveState", "?")
            mem   = props.get("MemoryCurrent", "")
            ts    = props.get("ActiveEnterTimestamp", "")

            if state == "active":
                mem_s = f" {_mb(int(mem))}" if mem and mem.isdigit() else ""
                up_s  = ""
                try:
                    start = datetime.strptime(ts.strip(), "%a %Y-%m-%d %H:%M:%S %Z")
                    diff  = int((datetime.now() - start).total_seconds())
                    d, h, mn = diff // 86400, (diff % 86400) // 3600, (diff % 3600) // 60
                    if d > 0:
                        up_s = f" {d}g" + (f" {h}sa" if h > 0 else "")
                    elif h > 0:
                        up_s = f" {h}sa" + (f" {mn}dk" if mn > 0 else "")
                    else:
                        up_s = f" {mn}dk"
                except Exception:
                    pass
                lines.append(f"✅ {svc}{mem_s}{up_s}")
            elif state == "failed":
                lines.append(f"🔴 {svc} FAILED")
            else:
                lines.append(f"⚠️ {svc} {state.upper()}")
    except Exception as exc:
        lines.append(f"⚠️ {exc}")
    return "\n".join(lines)

# ─────────────────────────────────────────────────────────────────────────────
# 3. Diğer node'lar (Prometheus + HTTP)
# ─────────────────────────────────────────────────────────────────────────────
async def section_nodes(client: httpx.AsyncClient) -> str:
    lines = ["🌐 <b>Diğer Node'lar</b>"]
    try:
        # node_exporter up durumu — job adları node-node3, node-gateway, vb.
        results = await _prom(client, 'up{job=~"node-.*"}')
        up_map = {}
        for row in results:
            inst = row["metric"].get("instance", "")
            ip   = inst.split(":")[0]
            node = IP_TO_NODE.get(ip, ip)
            up_map[node] = row["value"][1] == "1"

        for node in ["gateway", "node1", "node2", "node3", "node4"]:
            if node not in up_map:
                lines.append(f"⚠️ {node:<9} bilinmiyor")
            elif up_map[node]:
                lines.append(f"✅ {node}")
            else:
                lines.append(f"🔴 {node:<9} node_exporter DOWN")

        # node3 monitoring stack (doğrudan HTTP)
        checks = [
            ("loki",      f"{LOKI}/ready",                   200),
            ("grafana",   "http://10.10.0.4:3000/api/health", 200),
            ("alertmgr",  "http://10.10.0.4:9093/-/healthy",  200),
        ]
        for name, url, expected in checks:
            try:
                resp = await client.get(url, timeout=4)
                icon = "✅" if resp.status_code == expected else "⚠️"
                lines.append(f"  {icon} {name}")
            except Exception:
                lines.append(f"  🔴 {name} erişilemiyor")

        # node2 AI proxy
        try:
            t0 = time.monotonic()
            resp = await client.get("http://10.10.0.3:8080/health", timeout=4)
            ms = int((time.monotonic() - t0) * 1000)
            lines.append(f"  {'✅' if resp.status_code==200 else '⚠️'} node2/ai-proxy {ms}ms")
        except Exception:
            lines.append("  🔴 node2/ai-proxy erişilemiyor")

        # node3 AI proxy
        try:
            t0 = time.monotonic()
            resp = await client.get("http://10.10.0.4:8080/health", timeout=4)
            ms = int((time.monotonic() - t0) * 1000)
            lines.append(f"  {'✅' if resp.status_code==200 else '⚠️'} node3/ai-proxy {ms}ms")
        except Exception:
            lines.append("  🔴 node3/ai-proxy erişilemiyor")

        # MinIO health (node1/node4)
        for edge_url in EDGE_MINIO:
            ip = urllib.parse.urlparse(edge_url).hostname or ""
            node = IP_TO_NODE.get(ip, ip)
            try:
                resp = await client.get(f"{edge_url}/minio/health/live", timeout=4)
                lines.append(f"  {'✅' if resp.status_code==200 else '⚠️'} {node}/minio")
            except Exception:
                lines.append(f"  🔴 {node}/minio erişilemiyor")

    except Exception as exc:
        lines.append(f"⚠️ {exc}")
    return "\n".join(lines)

# ─────────────────────────────────────────────────────────────────────────────
# 4. Disk + Bellek (Prometheus)
# ─────────────────────────────────────────────────────────────────────────────
async def section_disk_mem(client: httpx.AsyncClient) -> str:
    lines = []

    # Disk
    lines.append("💿 <b>Disk</b>")
    try:
        avail_r = await _prom(client,
            'node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay|squashfs"}')
        size_r  = await _prom(client,
            'node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|overlay|squashfs"}')
        avail_m = {r["metric"]["instance"]: float(r["value"][1]) for r in avail_r}
        size_m  = {r["metric"]["instance"]: float(r["value"][1]) for r in size_r}
        rows = []
        for inst, total in size_m.items():
            if total == 0:
                continue
            ip   = inst.split(":")[0]
            node = IP_TO_NODE.get(ip, ip)
            used = total - avail_m.get(inst, 0)
            pct  = int(used / total * 100)
            icon = "🔴" if pct >= 90 else ("⚠️" if pct >= 75 else "✅")
            rows.append((node, f"{icon} {node:<9} %{pct}  {_gb(used)}/{_gb(total)} GB"))
        if rows:
            for _, line in sorted(rows):
                lines.append(line)
        else:
            lines.append("  ⚠️ Prometheus veri döndürmedi")
    except Exception as exc:
        lines.append(f"⚠️ {exc}")

    # Bellek
    lines.append("\n🧠 <b>Bellek</b>")
    try:
        mt = {r["metric"]["instance"]: float(r["value"][1])
              for r in await _prom(client, "node_memory_MemTotal_bytes")}
        ma = {r["metric"]["instance"]: float(r["value"][1])
              for r in await _prom(client, "node_memory_MemAvailable_bytes")}
        st = {r["metric"]["instance"]: float(r["value"][1])
              for r in await _prom(client, "node_memory_SwapTotal_bytes")}
        sf = {r["metric"]["instance"]: float(r["value"][1])
              for r in await _prom(client, "node_memory_SwapFree_bytes")}
        rows = []
        for inst, total in mt.items():
            if total == 0:
                continue
            ip   = inst.split(":")[0]
            node = IP_TO_NODE.get(ip, ip)
            used = total - ma.get(inst, 0)
            pct  = int(used / total * 100)
            swap_t = st.get(inst, 0)
            swap_u = swap_t - sf.get(inst, 0) if swap_t > 0 else 0
            swap_pct = int(swap_u / swap_t * 100) if swap_t > 0 else 0
            icon  = "🔴" if pct >= 90 else ("⚠️" if pct >= 80 else "✅")
            swap_s = (f"  Swap {_gb(swap_u)}/{_gb(swap_t)} GB"
                      f"{'⚠️' if swap_pct >= 50 else ''}"
                      if swap_t > 0 else "")
            rows.append((node, f"{icon} {node:<9} RAM {_gb(used)}/{_gb(total)} GB %{pct}{swap_s}"))
        if rows:
            for _, line in sorted(rows):
                lines.append(line)
        else:
            lines.append("  ⚠️ Prometheus veri döndürmedi")
    except Exception as exc:
        lines.append(f"⚠️ {exc}")

    return "\n".join(lines)

# ─────────────────────────────────────────────────────────────────────────────
# 5. PostgreSQL
# ─────────────────────────────────────────────────────────────────────────────
async def section_postgresql() -> str:
    lines = ["🗄️ <b>PostgreSQL</b>"]
    try:
        import asyncpg
        kw = _parse_db_url(DB_URL)
        conn = await asyncpg.connect(**kw, timeout=5)

        db_size   = await conn.fetchval(
            "SELECT pg_size_pretty(pg_database_size(current_database()))")
        act_conn  = await conn.fetchval(
            "SELECT count(*) FROM pg_stat_activity "
            "WHERE datname=current_database() AND state != 'idle'")
        locks     = await conn.fetchval(
            "SELECT count(*) FROM pg_locks WHERE NOT granted")
        long_q    = await conn.fetchval(
            "SELECT count(*) FROM pg_stat_activity "
            "WHERE state='active' AND query_start < NOW()-INTERVAL '30s' "
            "AND query NOT LIKE '%pg_stat%'")
        migration = await conn.fetchval(
            "SELECT version_num FROM alembic_version LIMIT 1")
        # Dead tuple uyarısı (> 500k dead tuple olan tablolar)
        bloat = await conn.fetch(
            "SELECT relname, n_dead_tup FROM pg_stat_user_tables "
            "WHERE n_dead_tup > 500000 ORDER BY n_dead_tup DESC LIMIT 3")

        await conn.close()

        lock_icon = "🔴" if locks > 0 else "✅"
        lines.append(f"Boyut: {db_size} · {act_conn} aktif bağ · {locks} kilit {lock_icon}")
        if long_q > 0:
            lines.append(f"⚠️ {long_q} uzun sorgu (>30s)")
        lines.append(f"Migration: {migration} ✅")
        for row in bloat:
            lines.append(f"⚠️ Bloat: {row['relname']} {row['n_dead_tup']:,} dead tuple")

    except Exception as exc:
        lines.append(f"⚠️ alınamadı: {exc}")
    return "\n".join(lines)

# ─────────────────────────────────────────────────────────────────────────────
# 6. Redis + ARQ
# ─────────────────────────────────────────────────────────────────────────────
def section_redis() -> str:
    lines = ["📦 <b>Redis + ARQ</b>"]
    try:
        import redis as redis_lib
        r = redis_lib.Redis.from_url(REDIS_URL, socket_timeout=5, decode_responses=True)
        r.ping()
        info = r.info()

        used    = info.get("used_memory", 0)
        max_mem = info.get("maxmemory", 0)
        evicted = info.get("evicted_keys", 0)
        aof_enabled = info.get("aof_enabled", 0)
        aof_status  = info.get("aof_last_rewrite_status", "ok")
        aof_ok  = (not aof_enabled) or (str(aof_status) == "ok")
        rdb_ok  = info.get("rdb_last_bgsave_status",  "?") == "ok"
        hits    = info.get("keyspace_hits",   0)
        misses  = info.get("keyspace_misses", 0)
        hit_r   = int(hits / (hits + misses) * 100) if (hits + misses) > 0 else 0

        # DB0 key sayısı
        db0 = info.get("db0", {})
        keys = db0.get("keys", 0) if isinstance(db0, dict) else 0

        # Aktif oturum (session:* key sayısı — SCAN ile)
        session_count = sum(1 for _ in r.scan_iter("session:*", count=500))

        pct      = int(used / max_mem * 100) if max_mem > 0 else 0
        mem_icon = "🔴" if pct >= 90 else ("⚠️" if pct >= 75 else "✅")
        max_s    = f"/{max_mem // 1024 // 1024}MB" if max_mem > 0 else ""
        lines.append(f"{mem_icon} {_mb(used)}{max_s} %{pct} · {keys:,} key · hit %{hit_r}")
        lines.append(f"  Oturum: {session_count:,}  "
                     f"{'✅' if aof_ok else '🔴'} AOF  "
                     f"{'✅' if rdb_ok else '🔴'} RDB")
        if evicted > 0:
            lines.append(f"  🔴 Eviction: {evicted:,} key silindi!")

        # ARQ kuyrukları — queue_name='default' ve 'critical'
        lines.append("⚡ ARQ:")
        for q in ["default", "critical"]:
            pending = r.zcard(q) or 0
            dead    = r.zcard(f"{q}:dead") or 0
            p_icon  = "⚠️" if pending > 0 else "✅"
            d_icon  = f"  🔴 {dead} ölü" if dead > 0 else ""
            lines.append(f"  {p_icon} {q}: {pending} bekleyen{d_icon}")

        # In-progress job sayısı (0 = worker boşta, normal)
        in_progress = len(r.keys("arq:in-progress:*") or [])
        if in_progress > 0:
            lines.append(f"  ▶️ {in_progress} job işleniyor")

        r.close()
    except Exception as exc:
        lines.append(f"⚠️ alınamadı: {exc}")
    return "\n".join(lines)

# ─────────────────────────────────────────────────────────────────────────────
# 7. ClickHouse
# ─────────────────────────────────────────────────────────────────────────────
def section_clickhouse() -> str:
    lines = ["📊 <b>ClickHouse</b>"]
    try:
        import clickhouse_connect
        client = clickhouse_connect.get_client(
            host="localhost", port=8123,
            database="teqlif_prod_analytics",
            connect_timeout=5)

        size_row = client.query(
            "SELECT formatReadableSize(sum(bytes_on_disk)) "
            "FROM system.parts WHERE database='teqlif_prod_analytics' AND active"
        )
        db_size = size_row.result_rows[0][0] if size_row.result_rows else "?"

        # Son 24s toplam satır sayısı (event_time sütunu olan tablolar)
        total_24h = 0
        for table in ["user_events", "search_events", "feed_analytics",
                      "swipe_live_events", "direct_sale_events"]:
            try:
                row = client.query(
                    f"SELECT count() FROM {table} "
                    f"WHERE event_time > now() - INTERVAL 24 HOUR")
                total_24h += row.result_rows[0][0] if row.result_rows else 0
            except Exception:
                pass

        client.close()
        lines.append(f"Boyut: {db_size} · Son 24s: {total_24h:,} satır")
    except Exception as exc:
        lines.append(f"⚠️ alınamadı: {exc}")
    return "\n".join(lines)

# ─────────────────────────────────────────────────────────────────────────────
# 8. LiveKit
# ─────────────────────────────────────────────────────────────────────────────
async def section_livekit(client: httpx.AsyncClient) -> str:
    lines = ["🎬 <b>LiveKit</b>"]
    if not LK_KEY or not LK_SECRET:
        lines.append("⚠️ LIVEKIT_API_KEY veya SECRET tanımlı değil")
        return "\n".join(lines)
    try:
        from livekit import api as lk_api
        for edge_url in EDGE_LK:
            ip   = urllib.parse.urlparse(edge_url).hostname or ""
            node = IP_TO_NODE.get(ip, ip)
            try:
                lk = lk_api.LiveKitAPI(
                    url=edge_url, api_key=LK_KEY, api_secret=LK_SECRET)
                rooms = await asyncio.wait_for(
                    lk.room.list_rooms(lk_api.ListRoomsRequest()), timeout=5)
                await lk.aclose()
                room_list = rooms.rooms if hasattr(rooms, "rooms") else []
                participants = sum(getattr(r, "num_participants", 0) for r in room_list)
                lines.append(f"✅ {node:<9} {len(room_list)} oda · {participants} katılımcı")
            except Exception as exc:
                lines.append(f"⚠️ {node:<9} {exc}")
    except ImportError:
        lines.append("⚠️ livekit-api kütüphanesi bulunamadı")
    except Exception as exc:
        lines.append(f"⚠️ {exc}")
    return "\n".join(lines)

# ─────────────────────────────────────────────────────────────────────────────
# 9. Son Yedek
# ─────────────────────────────────────────────────────────────────────────────
def section_backup() -> str:
    lines = ["💾 <b>Son Yedek</b>"]
    try:
        now = datetime.now(timezone.utc)
        found_any = False

        for label, pattern in [
            ("PG",    f"{BACKUP_DIR}/pg/teqlif_pg_*.pgdump"),
            ("Redis", f"{BACKUP_DIR}/redis/teqlif_redis_*.rdb.gz"),
            ("CH",    f"{BACKUP_DIR}/ch/teqlif_ch_*.tar.zst"),
        ]:
            files = sorted(glob.glob(pattern))
            if not files:
                continue
            found_any = True
            latest = files[-1]
            size   = os.path.getsize(latest)
            m = re.search(r"(\d{8}T\d{6}Z)", latest)
            if not m:
                lines.append(f"✅ {label}: {size // 1024}KB")
                continue
            ts  = datetime.strptime(m.group(1), "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
            age = int((now - ts).total_seconds() / 3600)
            icon = "✅" if age < 26 else ("⚠️" if age < 50 else "🔴")
            lines.append(f"{icon} {label}: {m.group(1)} · {size // 1024}KB · {age}s önce")

        if not found_any:
            lines.append("🔴 Yedek dosyası bulunamadı!")
    except Exception as exc:
        lines.append(f"⚠️ {exc}")
    return "\n".join(lines)

# ─────────────────────────────────────────────────────────────────────────────
# 10. Loki — Son 24s hata sayısı
# ─────────────────────────────────────────────────────────────────────────────
async def section_errors(client: httpx.AsyncClient) -> str:
    lines = ["🔴 <b>Hatalar (son 24s)</b>"]
    for node in ["node5", "node3", "node2"]:
        try:
            r = await client.get(
                f"{LOKI}/loki/api/v1/query",
                params={"query": f'sum(count_over_time({{node="{node}"}} |= "ERROR" != "sshd" != "kex_exchange" != "count_over_time" != "livekit.pion.turn" [24h]))'},
                timeout=8)
            data    = r.json().get("data", {}).get("result", [])
            count   = int(float(data[0]["value"][1])) if data else 0
            icon    = "🔴" if count > 20 else ("⚠️" if count > 5 else "✅")
            lines.append(f"{icon} {node}: {count} ERROR")
        except Exception:
            lines.append(f"⚠️ {node}: Loki sorgusu başarısız")
    return "\n".join(lines)

# ─────────────────────────────────────────────────────────────────────────────
# 11. Uygulama istatistikleri (PG)
# ─────────────────────────────────────────────────────────────────────────────
async def section_app_stats() -> str:
    lines = ["📈 <b>Uygulama (son 24s)</b>"]
    try:
        import asyncpg
        kw   = _parse_db_url(DB_URL)
        conn = await asyncpg.connect(**kw, timeout=5)

        stats = {
            "Yeni kayıt":    "SELECT count(*) FROM users WHERE created_at > NOW()-INTERVAL '24h'",
            "Yeni ilan":     "SELECT count(*) FROM listings WHERE created_at > NOW()-INTERVAL '24h'",
            "Aktif ilan":    "SELECT count(*) FROM listings WHERE status='active'",
            "Yeni mesaj":    "SELECT count(*) FROM direct_messages WHERE created_at > NOW()-INTERVAL '24h'",
            "İşlem":         "SELECT count(*) FROM tuci_transactions WHERE created_at > NOW()-INTERVAL '24h'",
        }
        for label, query in stats.items():
            try:
                val = await conn.fetchval(query)
                lines.append(f"{label:<16} {val:,}")
            except Exception:
                lines.append(f"{label:<16} ⚠️")

        await conn.close()
    except Exception as exc:
        lines.append(f"⚠️ alınamadı: {exc}")
    return "\n".join(lines)

# ─────────────────────────────────────────────────────────────────────────────
# 12. Hatırlatmalar
# ─────────────────────────────────────────────────────────────────────────────
def section_reminders() -> str:
    now  = datetime.now(timezone.utc)
    days = (ZAP_DEADLINE - now).days
    icon = "🔴" if days <= 14 else ("⚠️" if days <= 30 else "📅")
    return f"⚠️ <b>Hatırlatma</b>\n{icon} node3 Zap panel girişi: {days} gün kaldı (son: 10 Ara 2026)"

# ─────────────────────────────────────────────────────────────────────────────
# Telegram gönder
# ─────────────────────────────────────────────────────────────────────────────
async def send_telegram(text: str) -> None:
    if not TG_TOKEN or not TG_CHAT:
        print("TELEGRAM_BOT_TOKEN veya TELEGRAM_CHAT_ID tanımlı değil")
        return
    # 4096 char limitini aş → 2 mesaja böl
    chunks = []
    if len(text) > 4000:
        split = text.rfind("\n\n", 0, 4000)
        if split == -1:
            split = 4000
        chunks = [text[:split], text[split:].strip()]
    else:
        chunks = [text]

    async with httpx.AsyncClient() as client:
        for chunk in chunks:
            try:
                await client.post(
                    f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage",
                    json={"chat_id": TG_CHAT, "text": chunk,
                          "parse_mode": "HTML"},
                    timeout=10)
            except Exception as exc:
                print(f"Telegram gönderme hatası: {exc}")

# ─────────────────────────────────────────────────────────────────────────────
# Ana akış
# ─────────────────────────────────────────────────────────────────────────────
async def main() -> None:
    tr_now  = datetime.now(timezone(timedelta(hours=3)))
    header  = (f"🏥 <b>Teqlif Sistem Raporu</b>\n"
               f"📅 {tr_now.strftime('%d %b %Y, %H:%M TRT')}\n")

    # Senkron bölümler (subprocess / dosya sistemi)
    wg_s    = section_wireguard()
    node5_s = section_node5()
    redis_s = section_redis()
    ch_s    = section_clickhouse()
    backup_s = section_backup()
    remind_s = section_reminders()

    # Asenkron bölümler paralel
    async with httpx.AsyncClient() as client:
        (nodes_s, disk_mem_s, lk_s, errors_s, pg_s, app_s) = await asyncio.gather(
            section_nodes(client),
            section_disk_mem(client),
            section_livekit(client),
            section_errors(client),
            section_postgresql(),
            section_app_stats(),
        )

    message = "\n\n".join([
        header,
        wg_s,
        node5_s,
        nodes_s,
        disk_mem_s,
        pg_s,
        redis_s,
        ch_s,
        lk_s,
        backup_s,
        errors_s,
        app_s,
        remind_s,
    ])

    print(message)          # journalctl için
    await send_telegram(message)

if __name__ == "__main__":
    asyncio.run(main())
