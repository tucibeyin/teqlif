"""teqlif-agent — İnteraktif Telegram komut işleyici.

Sadece lider node'da çalışır (nodeMonitor). getUpdates polling ile
gelen komutları ve inline klavye callback'lerini işler.

Desteklenen komutlar:
  /durum        Cluster özeti (node'lar + job'lar + yedekler)
  /node <id>    Belirli node detayı + servis restart butonları
  /joblar       Stale + hatalı job listesi
  /job <ad>     Tek job detay
  /yedekler     Yedek zamanları
  /portlar      Node servis sağlığı özeti
  /yardim       Komut listesi

Callback formatları:
  ref           /durum yenile
  dn:<node>     /node <node>
  dj:<job>      /job <job>  (__list → /joblar)
  rs:<nd>:<svc> <node>'da <svc> restart (gossip /cmd endpoint)
  yv            /yedekler
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

import aiohttp

from config import AgentConfig
from db import AgentDB
import telegram as tg

logger = logging.getLogger("teqlif-agent.commander")

_RESTARTABLE = frozenset({
    "teqlif",
    "teqlif-worker",
    "teqlif-worker-critical",
    "teqlif-worker-video",
    "teqlif-ai-proxy",
    "teqlif-livekit",
    "teqlif-agent",
    "teqlif-staging",
    "teqlif-worker-staging",
    "teqlif-worker-critical-staging",
})

_BACKUP_LABELS: dict[str, str] = {
    "pg_backup":                "PG dump",
    "minio_backup":             "MinIO",
    "redis_backup":             "Redis",
    "clickhouse_backup":        "ClickHouse",
    "loki_backup":              "Loki",
    "uptime_kuma_backup":       "Uptime Kuma",
    "nodemonitor_config_backup":"nodeMonitor config",
    "mail_backup":              "Stalwart Mail",
    "cluster_secrets_backup":   "Cluster sırlar",
    "pg_basebackup":            "PG base backup",
    "offsite_sync":             "Offsite sync",
    "offsite_wal_sync":         "WAL sync",
    "pg_wal_cleanup":           "WAL temizliği",
}


class TelegramCommander:
    def __init__(self, cfg: AgentConfig, db: AgentDB) -> None:
        self._cfg  = cfg
        self._db   = db
        self._offset: int = 0
        self._task: asyncio.Task | None = None
        self._polling = False

    async def run(self, is_leader: bool) -> None:
        if is_leader and not self._polling:
            self._polling = True
            self._task = asyncio.create_task(self._poll_loop(), name="tg-commander")
            logger.info("Telegram commander başlatıldı (lider)")
        elif not is_leader and self._polling:
            self._polling = False
            if self._task:
                self._task.cancel()
                self._task = None
            logger.info("Telegram commander durduruldu (lider değil)")

    # ── Polling ───────────────────────────────────────────────────────────────

    async def _poll_loop(self) -> None:
        while self._polling:
            try:
                updates = await tg.get_updates(
                    self._cfg.telegram_bot_token, self._offset, timeout=1
                )
                if updates:
                    self._offset = updates[-1]["update_id"] + 1
                for upd in updates:
                    try:
                        await self._handle_update(upd)
                    except Exception as exc:
                        logger.warning("Update işlenemedi: %s", exc)
            except asyncio.CancelledError:
                break
            except Exception as exc:
                logger.debug("Commander polling hatası: %s", exc)
            await asyncio.sleep(2)

    # ── Update Yönlendirme ────────────────────────────────────────────────────

    def _auth_chats(self) -> set[str]:
        chats: set[str] = set()
        if self._cfg.telegram_chat_id:
            chats.add(str(self._cfg.telegram_chat_id))
        if getattr(self._cfg, "staging_telegram_chat_id", None):
            chats.add(str(self._cfg.staging_telegram_chat_id))
        return chats

    async def _handle_update(self, upd: dict) -> None:
        if "message" in upd:
            msg     = upd["message"]
            chat_id = str(msg.get("chat", {}).get("id", ""))
            if chat_id not in self._auth_chats():
                return
            text = msg.get("text", "").strip()
            if text.startswith("/"):
                await self._dispatch(chat_id, text)

        elif "callback_query" in upd:
            cq      = upd["callback_query"]
            chat_id = str(cq.get("message", {}).get("chat", {}).get("id", ""))
            if chat_id not in self._auth_chats():
                await tg.answer_callback(self._cfg.telegram_bot_token, cq["id"], "⛔ Yetkisiz")
                return
            await self._handle_callback(cq)

    async def _dispatch(self, chat_id: str, text: str) -> None:
        parts = text.lstrip("/").split()
        cmd   = parts[0].split("@")[0].lower() if parts else ""
        args  = parts[1:]

        handlers = {
            "durum":   self._cmd_durum,
            "d":       self._cmd_durum,
            "node":    self._cmd_node,
            "n":       self._cmd_node,
            "joblar":  self._cmd_joblar,
            "j":       self._cmd_joblar,
            "job":     self._cmd_job,
            "yedekler":self._cmd_yedekler,
            "y":       self._cmd_yedekler,
            "portlar": self._cmd_portlar,
            "p":       self._cmd_portlar,
            "yardim":  self._cmd_yardim,
            "start":   self._cmd_yardim,
            "help":    self._cmd_yardim,
        }
        fn = handlers.get(cmd)
        if fn:
            await fn(chat_id, args)
        else:
            await tg.send(
                self._cfg.telegram_bot_token, chat_id,
                f"❓ Bilinmeyen komut: <code>/{cmd}</code>\n/yardim ile komutları gör."
            )

    # ── Callback İşleyici ─────────────────────────────────────────────────────

    async def _handle_callback(self, cq: dict) -> None:
        cb_id   = cq["id"]
        data    = cq.get("data", "")
        chat_id = str(cq.get("message", {}).get("chat", {}).get("id", ""))
        parts   = data.split(":", 2)
        action  = parts[0]

        if action == "ref":
            await tg.answer_callback(self._cfg.telegram_bot_token, cb_id, "")
            await self._cmd_durum(chat_id, [])
        elif action == "yv":
            await tg.answer_callback(self._cfg.telegram_bot_token, cb_id, "")
            await self._cmd_yedekler(chat_id, [])
        elif action == "dn":
            node_id = parts[1] if len(parts) > 1 else ""
            await tg.answer_callback(self._cfg.telegram_bot_token, cb_id, "")
            await self._cmd_node(chat_id, [node_id])
        elif action == "dj":
            job = parts[1] if len(parts) > 1 else ""
            await tg.answer_callback(self._cfg.telegram_bot_token, cb_id, "")
            if job == "__list":
                await self._cmd_joblar(chat_id, [])
            else:
                await self._cmd_job(chat_id, [job])
        elif action == "rs":
            node_id = parts[1] if len(parts) > 1 else ""
            svc     = parts[2] if len(parts) > 2 else ""
            await self._do_restart(cb_id, chat_id, node_id, svc)
        else:
            await tg.answer_callback(self._cfg.telegram_bot_token, cb_id, "Bilinmeyen aksiyon")

    # ── Restart ───────────────────────────────────────────────────────────────

    async def _do_restart(self, cb_id: str, chat_id: str, node_id: str, svc: str) -> None:
        if not node_id or not svc:
            await tg.answer_callback(self._cfg.telegram_bot_token, cb_id, "⛔ Eksik parametre")
            return
        await tg.answer_callback(
            self._cfg.telegram_bot_token, cb_id,
            f"🔄 {node_id} → {svc} restart başlatılıyor...", show_alert=True,
        )
        result = await self._send_cmd(node_id, {"cmd": "restart_service", "service": svc})
        if result.get("ok"):
            await tg.send(
                self._cfg.telegram_bot_token, chat_id,
                f"✅ <b>{node_id}</b> — <code>{svc}</code> restart başlatıldı"
            )
        else:
            err = result.get("error", "bilinmeyen hata")
            await tg.send(
                self._cfg.telegram_bot_token, chat_id,
                f"⛔ <b>{node_id}</b> — <code>{svc}</code> restart başarısız\n"
                f"<code>{err[:150]}</code>"
            )

    async def _send_cmd(self, node_id: str, payload: dict) -> dict:
        """Hedef node'un gossip /cmd endpoint'ine komut gönderir."""
        wg_ip: str | None = None
        for peer in self._cfg.peers:
            if peer.node_id == node_id:
                wg_ip = peer.wg_ip
                break
        if wg_ip is None and node_id == self._cfg.node_id:
            wg_ip = self._cfg.wg_ip
        if not wg_ip:
            return {"ok": False, "error": f"node bulunamadı: {node_id}"}

        url     = f"http://{wg_ip}:{self._cfg.gossip_port}/cmd"
        headers = {"Authorization": f"Bearer {self._cfg.gossip_token}"}
        try:
            async with aiohttp.ClientSession() as s:
                async with s.post(
                    url, json=payload, headers=headers,
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as r:
                    return await r.json()
        except Exception as exc:
            return {"ok": False, "error": str(exc)[:100]}

    # ── Komutlar ──────────────────────────────────────────────────────────────

    async def _cmd_durum(self, chat_id: str, args: list[str]) -> None:
        states = await self._db.get_all_node_states()
        stale  = await self._db.get_stale_jobs()
        failed = await self._db.get_failed_jobs()

        now_str = datetime.now(timezone.utc).strftime("%d %b %H:%M")
        lines   = [f"<b>📊 Anlık Durum</b> — {now_str} UTC\n"]

        active = sum(1 for s in states if _seen_ok(s.get("seen_at", "")))
        lines.append(f"<b>📡 Node'lar ({active}/{len(states)} aktif)</b>")
        for s in sorted(states, key=lambda x: x["node_id"]):
            nid  = s["node_id"]
            icon = "✅" if _seen_ok(s.get("seen_at", "")) else "🔴"
            m    = s.get("metrics") or {}
            cpu  = m.get("cpu_percent", "?")
            ram  = m.get("ram_percent", "?")
            dsk  = m.get("disk_percent", "?")
            lines.append(f"  {icon} <b>{nid}</b>  CPU {cpu}%  RAM {ram}%  Disk {dsk}%")

        lines.append("")
        issue_cnt = len(stale) + len(failed)
        if issue_cnt:
            lines.append(f"<b>⚠️ Job Sorunları ({issue_cnt})</b>")
            for row in stale[:4]:
                lines.append(f"  • <code>{row['job_name']}</code> stale")
            for row in failed[:4]:
                lines.append(f"  • <code>{row['job_name']}</code> hata")
            if issue_cnt > 8:
                lines.append(f"  … ve {issue_cnt - 8} tane daha")
        else:
            lines.append("✅ <b>Tüm job'lar normal</b>")

        lines.append("\n<i>/node &lt;id&gt; · /joblar · /yedekler · /portlar</i>")

        markup = {"inline_keyboard": [[
            {"text": "🔄 Yenile",    "callback_data": "ref"},
            {"text": "⚙️ Joblar",   "callback_data": "dj:__list"},
            {"text": "💾 Yedekler", "callback_data": "yv"},
        ]]}
        await tg.send(self._cfg.telegram_bot_token, chat_id, "\n".join(lines), reply_markup=markup)

    async def _cmd_node(self, chat_id: str, args: list[str]) -> None:
        if not args:
            states = await self._db.get_all_node_states()
            lines  = ["<b>📡 Node Listesi</b>"]
            for s in sorted(states, key=lambda x: x["node_id"]):
                nid  = s["node_id"]
                icon = "✅" if _seen_ok(s.get("seen_at", "")) else "🔴"
                lines.append(f"  {icon} <code>/node {nid}</code>")
            await tg.send(self._cfg.telegram_bot_token, chat_id, "\n".join(lines))
            return

        target = args[0]
        states = await self._db.get_all_node_states()
        state  = next((s for s in states if s["node_id"] == target), None)
        if not state:
            await tg.send(
                self._cfg.telegram_bot_token, chat_id,
                f"❓ Node bulunamadı: <code>{target}</code>"
            )
            return

        m    = state.get("metrics") or {}
        svcs = state.get("services") or {}
        seen = state.get("seen_at", "")
        icon = "✅" if _seen_ok(seen) else "🔴"

        lines = [f"<b>{icon} {target}</b>  (son görülme: {_ago(seen)})"]
        lines.append(
            f"CPU {m.get('cpu_percent','?')}%  "
            f"RAM {m.get('ram_percent','?')}%  "
            f"Disk {m.get('disk_percent','?')}%"
        )
        if m.get("offsite_disk_percent") is not None:
            lines.append(f"Offsite Disk {m['offsite_disk_percent']}%")

        # Services
        svc_lines: list[str] = []
        restart_btns: list[dict] = []
        for svc_name, svc_data in sorted(svcs.items()):
            if not isinstance(svc_data, dict) or "healthy" not in svc_data:
                continue
            ok       = svc_data.get("healthy", True)
            svc_icon = "✅" if ok else "🔴"
            svc_lines.append(f"  {svc_icon} {svc_name}")
            if not ok and svc_name in _RESTARTABLE:
                label = svc_name.replace("teqlif-", "").replace("-", " ").title()
                cb    = f"rs:{target}:{svc_name}"
                if len(cb.encode()) <= 64:
                    restart_btns.append({"text": f"🔄 {label}", "callback_data": cb})

        if svc_lines:
            lines.append("\n<b>🔧 Servisler:</b>")
            lines.extend(svc_lines[:18])

        markup = None
        if restart_btns:
            rows   = [restart_btns[i:i+2] for i in range(0, len(restart_btns), 2)]
            markup = {"inline_keyboard": rows}

        await tg.send(self._cfg.telegram_bot_token, chat_id, "\n".join(lines), reply_markup=markup)

    async def _cmd_joblar(self, chat_id: str, args: list[str]) -> None:
        stale  = await self._db.get_stale_jobs()
        failed = await self._db.get_failed_jobs()

        lines = ["<b>⚙️ Job Durumu</b>"]

        if stale:
            lines.append(f"\n<b>⏰ Stale ({len(stale)})</b>")
            for row in stale:
                job  = row["job_name"]
                mins = row.get("expected_every_m", "?")
                last = _short_dt(str(row.get("last_ok_at") or "hiç"))
                lines.append(f"  <code>{job}</code>")
                lines.append(f"    Beklenen: {mins}dk · Son: {last}")

        if failed:
            lines.append(f"\n<b>🚨 Hata ({len(failed)})</b>")
            for row in failed:
                job    = row["job_name"]
                cnt    = row.get("fail_count", 1)
                reason = str(row.get("fail_reason") or "")
                lines.append(f"  <code>{job}</code> ({cnt}× hata)")
                if reason:
                    lines.append(f"    <code>{reason[:80]}</code>")

        if not stale and not failed:
            lines.append("\n✅ Tüm job'lar normal çalışıyor")

        await tg.send(self._cfg.telegram_bot_token, chat_id, "\n".join(lines))

    async def _cmd_job(self, chat_id: str, args: list[str]) -> None:
        if not args:
            await self._cmd_joblar(chat_id, [])
            return

        job_name   = args[0]
        all_health = await self._db.get_all_job_health()
        stale      = {r["job_name"] for r in await self._db.get_stale_jobs()}
        failed_set = {r["job_name"] for r in await self._db.get_failed_jobs()}

        job_data = next((r for r in all_health if r["job_name"] == job_name), None)
        if not job_data:
            await tg.send(
                self._cfg.telegram_bot_token, chat_id,
                f"❓ Job bulunamadı: <code>{job_name}</code>"
            )
            return

        if job_name in stale:
            icon = "⏰"
        elif job_name in failed_set:
            icon = "🚨"
        else:
            icon = "✅"

        lines = [f"<b>{icon} {job_name}</b>"]
        lines.append(f"Son OK:   {_short_dt(str(job_data.get('last_ok_at') or 'hiç'))}")
        lines.append(f"Beklenen: her {job_data.get('expected_every_m', '?')} dk")
        if job_data.get("fail_count", 0):
            lines.append(f"Hata:     {job_data['fail_count']}×")
        if job_data.get("last_fail_at"):
            lines.append(f"Son hata: {_short_dt(str(job_data['last_fail_at']))}")
        if job_data.get("fail_reason"):
            lines.append(f"Neden: <code>{str(job_data['fail_reason'])[:100]}</code>")

        await tg.send(self._cfg.telegram_bot_token, chat_id, "\n".join(lines))

    async def _cmd_yedekler(self, chat_id: str, args: list[str]) -> None:
        from modules.health import _BACKUP_MAX_MIN as _BMM

        states      = await self._db.get_all_node_states()
        backup_data: dict[str, int] = {}
        for s in states:
            svcs = s.get("services") or {}
            for key in _BACKUP_LABELS:
                if key in svcs and isinstance(svcs[key], dict) and "age_min" in svcs[key]:
                    backup_data[key] = svcs[key]["age_min"]

        if not backup_data:
            await tg.send(
                self._cfg.telegram_bot_token, chat_id,
                "💾 Yedek verisi henüz toplanmadı.\nnode2 gossip bağlantısını kontrol edin."
            )
            return

        lines   = ["<b>💾 Yedek Durumu</b>\n"]
        ok_cnt  = 0
        err_cnt = 0
        for key, label in _BACKUP_LABELS.items():
            age = backup_data.get(key)
            if age is None:
                continue
            max_min = _BMM.get(key, 25 * 60)
            if age <= max_min:
                ok_cnt += 1
                lines.append(f"  ✅ <b>{label}</b> — {_fmt_mins(age)}")
            else:
                err_cnt += 1
                lines.append(f"  ⚠️ <b>{label}</b> — {_fmt_mins(age)} <i>(limit {_fmt_mins(max_min)})</i>")

        summary = f"\n{ok_cnt} OK"
        if err_cnt:
            summary += f", {err_cnt} eski"
        lines.append(summary)
        await tg.send(self._cfg.telegram_bot_token, chat_id, "\n".join(lines))

    async def _cmd_portlar(self, chat_id: str, args: list[str]) -> None:
        states = await self._db.get_all_node_states()
        lines  = ["<b>🔌 Servis Sağlığı</b>"]

        for s in sorted(states, key=lambda x: x["node_id"]):
            nid   = s["node_id"]
            svcs  = s.get("services") or {}
            items = [
                (name, data) for name, data in svcs.items()
                if isinstance(data, dict) and "healthy" in data
            ]
            if not items:
                continue
            down = [name for name, data in items if not data.get("healthy")]
            if down:
                lines.append(f"\n🔴 <b>{nid}</b> — {len(down)} sorun")
                for svc in down:
                    lines.append(f"  • {svc}")
            else:
                lines.append(f"  ✅ <b>{nid}</b> — {len(items)} servis")

        markup = {"inline_keyboard": [[
            {"text": "🔄 Yenile", "callback_data": "ref"},
        ]]}
        await tg.send(self._cfg.telegram_bot_token, chat_id, "\n".join(lines), reply_markup=markup)

    async def _cmd_yardim(self, chat_id: str, args: list[str]) -> None:
        text = (
            "<b>🤖 teqlif-agent Komutları</b>\n\n"
            "<b>Durum:</b>\n"
            "  /durum — Cluster özeti\n"
            "  /node &lt;id&gt; — Node detay  <i>(/node node6)</i>\n"
            "  /portlar — Tüm servis sağlığı\n\n"
            "<b>Job'lar:</b>\n"
            "  /joblar — Stale + hatalı job'lar\n"
            "  /job &lt;ad&gt; — Tek job detay\n\n"
            "<b>Yedekler:</b>\n"
            "  /yedekler — Yedek zamanları\n\n"
            "/yardim — Bu mesaj\n\n"
            "<i>Node'lar: node1 node2 node3 node4 "
            "node5 node6 node101 nodeMonitor</i>"
        )
        await tg.send(self._cfg.telegram_bot_token, chat_id, text)


# ── Yardımcı Fonksiyonlar ─────────────────────────────────────────────────────

def _seen_ok(ts: str) -> bool:
    if not ts:
        return False
    try:
        dt  = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        sec = (datetime.now(timezone.utc) - dt).total_seconds()
        return sec < 300
    except Exception:
        return False


def _ago(ts: str) -> str:
    if not ts:
        return "bilinmiyor"
    try:
        dt  = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        sec = int((datetime.now(timezone.utc) - dt).total_seconds())
        if sec < 60:
            return f"{sec}s"
        if sec < 3600:
            return f"{sec // 60}dk"
        return f"{sec // 3600}sa {(sec % 3600) // 60}dk"
    except Exception:
        return "?"


def _short_dt(ts: str) -> str:
    if not ts or ts in ("hiç", "None", "null"):
        return "hiç"
    try:
        dt  = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        sec = (datetime.now(timezone.utc) - dt).total_seconds()
        if sec < 86400:
            return f"{dt.strftime('%H:%M')} ({_ago(ts)} önce)"
        return dt.strftime("%d %b %H:%M")
    except Exception:
        return ts[:16]


def _fmt_mins(mins: int) -> str:
    if mins < 60:
        return f"{mins} dk"
    h = mins // 60
    m = mins % 60
    if h < 24:
        return f"{h}sa {m}dk" if m else f"{h}sa"
    d = h // 24
    rh = h % 24
    return f"{d}g {rh}sa" if rh else f"{d}g"
