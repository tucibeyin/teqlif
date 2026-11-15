"""teqlif-agent — İnteraktif Telegram komut işleyici.

Sadece lider node'da çalışır (nodeMonitor). getUpdates polling ile
gelen komutları ve inline klavye callback'lerini işler.

PROD kanalı:  Cluster geneli — tüm node'lar, tüm servisler, yedekler
STAGING kanalı: node5'e özel — sadece staging servis + job'ları

Desteklenen komutlar (iki kanalda da):
  /durum        Cluster özeti (PROD) / staging özeti (STAGING)
  /node <id>    Node detay + servis restart butonları
  /joblar       Stale + hatalı job listesi
  /job <ad>     Tek job detay
  /yedekler     Yedek zamanları (sadece PROD)
  /portlar      Servis sağlığı özeti
  /yardim       Komut listesi

Callback formatları:
  ref           /durum yenile
  dn:<node>     /node <node>
  dj:<job>      /job <job>  (__list → /joblar)
  rs:<nd>:<svc> <node>'da <svc> restart
  yv            /yedekler
"""
from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from datetime import datetime, timezone

from alerter import TelegramAlerter, TelegramBot
from constants import BACKUP_LABELS, BACKUP_MAX_MIN, RESTARTABLE_SVCS, STAGING_SERVICES
from db import AgentDB

logger = logging.getLogger("teqlif-agent.commander")

_STAGING_NODE = "node5"

_PROD_COMMANDS = [
    {"command": "durum",    "description": "📊 Cluster özeti — node'lar + job'lar"},
    {"command": "node",     "description": "📡 Node seç ve yönet"},
    {"command": "portlar",  "description": "🔌 Tüm servis sağlığı"},
    {"command": "joblar",   "description": "⚙️ Stale + hatalı job'lar"},
    {"command": "yedekler", "description": "💾 Yedek zamanları"},
    {"command": "yardim",   "description": "🤖 Komut listesi"},
    {"command": "menu",     "description": "🔄 Telegram menüsünü yenile"},
]

_STAGING_COMMANDS = [
    {"command": "durum",   "description": "🧪 Staging özeti (node5)"},
    {"command": "node",    "description": "📡 node5 detay ve yönet"},
    {"command": "portlar", "description": "🔌 Staging servis sağlığı"},
    {"command": "joblar",  "description": "⚙️ Staging job durumu"},
    {"command": "yardim",  "description": "🤖 Komut listesi"},
    {"command": "menu",    "description": "🔄 Telegram menüsünü yenile"},
]


@dataclass
class CommandContext:
    """Bir komut isteğinin tüm bağlamı — alerter + hangi bot + staging mı."""
    chat_id:    str
    alerter:    TelegramAlerter
    is_staging: bool
    bot:        TelegramBot  # callback yanıtları bu bot üzerinden gider


class TelegramCommander:
    def __init__(
        self,
        db:              AgentDB,
        prod_bot:        TelegramBot,
        prod_alerter:    TelegramAlerter,
        staging_bot:     TelegramBot,       # token aynıysa prod_bot ile aynı instance olabilir
        staging_alerter: TelegramAlerter | None,
        restart_gw,                         # GossipClient — circular import önlemi
    ) -> None:
        self._db              = db
        self._prod_bot        = prod_bot
        self._staging_bot     = staging_bot
        self._alerter         = prod_alerter
        self._staging_alerter = staging_alerter
        self._restart_gw      = restart_gw
        self._tasks:  list[asyncio.Task] = []
        self._polling = False

    # ── Lider Kontrolü ───────────────────────────────────────────────────────

    async def run(self, is_leader: bool) -> None:
        if is_leader and not self._polling:
            self._polling = True
            self._tasks = [
                asyncio.create_task(
                    self._poll_loop(self._prod_bot, is_staging=False),
                    name="tg-prod",
                ),
            ]
            # Staging bot yalnızca token farklıysa ayrı poll loop çalıştırır
            if self._staging_alerter and self._staging_bot is not self._prod_bot:
                self._tasks.append(
                    asyncio.create_task(
                        self._poll_loop(self._staging_bot, is_staging=True),
                        name="tg-staging",
                    )
                )
            logger.info("Telegram commander başlatıldı (lider)")
            await self._register_menus()
        elif not is_leader and self._polling:
            self._polling = False
            for t in self._tasks:
                t.cancel()
            self._tasks = []
            logger.info("Telegram commander durduruldu (lider değil)")

    # ── Menü Kaydı ───────────────────────────────────────────────────────────

    async def _register_menus(self) -> tuple[bool, bool]:
        """PROD ve STAGING botları için Telegram '/' menüsünü ayarlar.
        Her lider seçiminde çalışır. (ok_prod, ok_staging) döner."""
        prod_ok    = False
        staging_ok = False

        # PROD: default scope (PM'de görünür) + per-chat scope
        try:
            await self._prod_bot.set_commands("", _PROD_COMMANDS)
        except Exception:
            pass
        try:
            prod_ok = await self._prod_bot.set_commands(
                self._alerter.chat_id, _PROD_COMMANDS,
            )
            logger.info("PROD Telegram menüsü %s", "ayarlandı" if prod_ok else "AYARLANAMADI")
        except Exception as exc:
            logger.warning("PROD menü kaydı başarısız: %s", exc)

        # STAGING: ayrı bot varsa onun default scope'unu da ayarla
        if self._staging_alerter and self._staging_alerter.chat_id:
            try:
                if self._staging_bot is not self._prod_bot:
                    await self._staging_bot.set_commands("", _STAGING_COMMANDS)
                staging_ok = await self._staging_bot.set_commands(
                    self._staging_alerter.chat_id, _STAGING_COMMANDS,
                )
                logger.info("STAGING Telegram menüsü %s", "ayarlandı" if staging_ok else "AYARLANAMADI")
            except Exception as exc:
                logger.warning("STAGING menü kaydı başarısız: %s", exc)
        else:
            staging_ok = True

        return prod_ok, staging_ok

    # ── Polling ───────────────────────────────────────────────────────────────

    async def _poll_loop(self, bot: TelegramBot, *, is_staging: bool) -> None:
        """Belirli bir bot'un update stream'ini dinler; is_staging routing'i belirler."""
        offset = 0
        while self._polling:
            try:
                updates = await bot.get_updates(offset)
                if updates:
                    offset = updates[-1]["update_id"] + 1
                for upd in updates:
                    try:
                        await self._handle_update(upd, bot=bot, is_staging=is_staging)
                    except Exception as exc:
                        logger.warning("Update işlenemedi: %s", exc)
            except asyncio.CancelledError:
                break
            except Exception as exc:
                logger.debug("Commander polling hatası: %s", exc)
            await asyncio.sleep(2)

    # ── Context Fabrikası ─────────────────────────────────────────────────────

    def _make_context(
        self, chat_id: str, bot: TelegramBot, is_staging: bool
    ) -> CommandContext | None:
        """Gelen update'in bağlamını oluşturur; yetkisiz chat ise None döner."""
        alerter = self._staging_alerter if is_staging else self._alerter
        if not alerter or not alerter.chat_id:
            return None
        return CommandContext(
            chat_id=chat_id, alerter=alerter, is_staging=is_staging, bot=bot,
        )

    # ── Update Yönlendirme ────────────────────────────────────────────────────

    async def _handle_update(
        self, upd: dict, *, bot: TelegramBot, is_staging: bool
    ) -> None:
        if "message" in upd:
            msg     = upd["message"]
            chat_id = str(msg.get("chat", {}).get("id", ""))
            ctx     = self._make_context(chat_id, bot, is_staging)
            if not ctx:
                return
            text = msg.get("text", "").strip()
            if text.startswith("/"):
                await self._dispatch(ctx, text)

        elif "callback_query" in upd:
            cq      = upd["callback_query"]
            chat_id = str(cq.get("message", {}).get("chat", {}).get("id", ""))
            ctx     = self._make_context(chat_id, bot, is_staging)
            if not ctx:
                await bot.answer_callback(cq["id"], "⛔ Yetkisiz")
                return
            await self._handle_callback(ctx, cq)

    async def _dispatch(self, ctx: CommandContext, text: str) -> None:
        parts = text.lstrip("/").split()
        cmd   = parts[0].split("@")[0].lower() if parts else ""
        args  = parts[1:]

        handlers = {
            "durum":    self._cmd_durum,
            "d":        self._cmd_durum,
            "node":     self._cmd_node,
            "n":        self._cmd_node,
            "joblar":   self._cmd_joblar,
            "j":        self._cmd_joblar,
            "job":      self._cmd_job,
            "yedekler": self._cmd_yedekler,
            "y":        self._cmd_yedekler,
            "portlar":  self._cmd_portlar,
            "p":        self._cmd_portlar,
            "yardim":   self._cmd_yardim,
            "start":    self._cmd_yardim,
            "help":     self._cmd_yardim,
            "menu":     self._cmd_menu,
        }
        fn = handlers.get(cmd)
        if fn:
            await fn(ctx, args)
        else:
            await ctx.alerter.send(
                f"❓ Bilinmeyen komut: <code>/{cmd}</code>\n/yardim ile komutları gör."
            )

    # ── Callback İşleyici ─────────────────────────────────────────────────────

    async def _handle_callback(self, ctx: CommandContext, cq: dict) -> None:
        cb_id  = cq["id"]
        data   = cq.get("data", "")
        parts  = data.split(":", 2)
        action = parts[0]

        if action == "ref":
            await ctx.bot.answer_callback(cb_id)
            await self._cmd_durum(ctx, [])
        elif action == "yv":
            await ctx.bot.answer_callback(cb_id)
            await self._cmd_yedekler(ctx, [])
        elif action == "dn":
            node_id = parts[1] if len(parts) > 1 else ""
            await ctx.bot.answer_callback(cb_id)
            await self._cmd_node(ctx, [node_id])
        elif action == "dj":
            job = parts[1] if len(parts) > 1 else ""
            await ctx.bot.answer_callback(cb_id)
            if job == "__list":
                await self._cmd_joblar(ctx, [])
            else:
                await self._cmd_job(ctx, [job])
        elif action == "nl":
            await ctx.bot.answer_callback(cb_id)
            await self._cmd_node(ctx, [])
        elif action == "er":
            node_id = parts[1] if len(parts) > 1 else ""
            await ctx.bot.answer_callback(cb_id)
            await self._cmd_node_errors(ctx, node_id)
        elif action == "rs":
            node_id = parts[1] if len(parts) > 1 else ""
            svc     = parts[2] if len(parts) > 2 else ""
            await self._do_restart(ctx, cb_id, node_id, svc)
        else:
            await ctx.bot.answer_callback(cb_id, "Bilinmeyen aksiyon")

    # ── Restart ───────────────────────────────────────────────────────────────

    async def _do_restart(
        self, ctx: CommandContext, cb_id: str, node_id: str, svc: str,
    ) -> None:
        if not node_id or not svc:
            await self._bot.answer_callback(cb_id, "⛔ Eksik parametre")
            return
        # Staging kanalından sadece staging servisler restart edilebilir
        if ctx.is_staging and svc not in STAGING_SERVICES:
            await self._bot.answer_callback(cb_id, "⛔ Bu servis staging kanalından yönetilemez")
            return
        await ctx.bot.answer_callback(
            cb_id,
            f"🔄 {node_id} → {svc} restart başlatılıyor...",
            show_alert=True,
        )
        result = await self._restart_gw.restart_service(node_id, svc)
        if result.get("ok"):
            await ctx.alerter.send(
                f"✅ <b>{node_id}</b> — <code>{svc}</code> restart başlatıldı"
            )
        else:
            err = result.get("error", "bilinmeyen hata")
            await ctx.alerter.send(
                f"⛔ <b>{node_id}</b> — <code>{svc}</code> restart başarısız\n"
                f"<code>{err[:150]}</code>"
            )

    # ── Komutlar ──────────────────────────────────────────────────────────────

    async def _cmd_durum(self, ctx: CommandContext, args: list[str]) -> None:
        states = await self._db.get_all_node_states()
        stale  = await self._db.get_stale_jobs()
        failed = await self._db.get_failed_jobs()

        now_str = datetime.now(timezone.utc).strftime("%d %b %H:%M")

        if ctx.is_staging:
            # Staging: sadece node5
            staging_states = [s for s in states if s["node_id"] == _STAGING_NODE]
            lines = [f"<b>🧪 Staging Durumu</b> — {now_str} UTC\n"]
            if not staging_states:
                lines.append(f"🔴 {_STAGING_NODE} bulunamadı")
            else:
                s    = staging_states[0]
                icon = "✅" if _seen_ok(s.get("seen_at", "")) else "🔴"
                m    = s.get("metrics") or {}
                svcs = s.get("services") or {}
                lines.append(
                    f"{icon} <b>{_STAGING_NODE}</b>  "
                    f"CPU {m.get('cpu_percent','?')}%  "
                    f"RAM {m.get('ram_percent','?')}%"
                )
                staging_svcs = {
                    k: v for k, v in svcs.items()
                    if isinstance(v, dict) and "healthy" in v
                    and any(k.startswith(p) for p in ("teqlif-staging", "teqlif-worker-staging",
                                                       "teqlif-worker-critical-staging",
                                                       "teqlif-worker-video-staging",
                                                       "teqlif-ai-proxy-staging",
                                                       "teqlif-redis-staging",
                                                       "teqlif-livekit-staging"))
                }
                if staging_svcs:
                    lines.append("")
                    for sn, sd in sorted(staging_svcs.items()):
                        ok = sd.get("healthy", True)
                        lines.append(f"  {'✅' if ok else '🔴'} {sn}")

            # Job'lar — staging prefix filtreleme
            staging_stale  = [r for r in stale  if _is_staging_job(r["job_name"])]
            staging_failed = [r for r in failed if _is_staging_job(r["job_name"])]
            issue_cnt = len(staging_stale) + len(staging_failed)
            lines.append("")
            if issue_cnt:
                lines.append(f"<b>⚠️ Staging Job Sorunları ({issue_cnt})</b>")
                for row in staging_stale[:3]:
                    lines.append(f"  • <code>{row['job_name']}</code> stale")
                for row in staging_failed[:3]:
                    lines.append(f"  • <code>{row['job_name']}</code> hata")
            else:
                lines.append("✅ <b>Staging job'lar normal</b>")

            markup = {"inline_keyboard": [
                [{"text": "🔄 Yenile",                  "callback_data": "ref"}],
                [{"text": f"📡 {_STAGING_NODE}",        "callback_data": f"dn:{_STAGING_NODE}"}],
                [{"text": f"🔍 Son Hatalar",            "callback_data": f"er:{_STAGING_NODE}"}],
                [{"text": "⚙️ Joblar",                 "callback_data": "dj:__list"}],
            ]}
        else:
            # PROD: tüm cluster
            lines = [f"<b>📊 Anlık Durum</b> — {now_str} UTC\n"]
            active = sum(1 for s in states if _seen_ok(s.get("seen_at", "")))
            lines.append(f"<b>📡 Node'lar ({active}/{len(states)} aktif)</b>")
            for s in sorted(states, key=lambda x: _node_sort_key(x["node_id"])):
                nid  = s["node_id"]
                icon = "✅" if _seen_ok(s.get("seen_at", "")) else "🔴"
                m    = s.get("metrics") or {}
                cpu  = m.get("cpu_percent", "?")
                ram  = m.get("ram_percent", "?")
                dsk  = m.get("disk_percent", "?")
                lines.append(f"  {icon} <b>{nid}</b>  CPU {cpu}%  RAM {ram}%  Disk {dsk}%")

            lines.append("")
            # Prod job'lar — staging job'larını hariç tut
            prod_stale  = [r for r in stale  if not _is_staging_job(r["job_name"])]
            prod_failed = [r for r in failed if not _is_staging_job(r["job_name"])]
            issue_cnt   = len(prod_stale) + len(prod_failed)
            if issue_cnt:
                lines.append(f"<b>⚠️ Job Sorunları ({issue_cnt})</b>")
                for row in prod_stale[:4]:
                    lines.append(f"  • <code>{row['job_name']}</code> stale")
                for row in prod_failed[:4]:
                    lines.append(f"  • <code>{row['job_name']}</code> hata")
                if issue_cnt > 8:
                    lines.append(f"  … ve {issue_cnt - 8} tane daha")
            else:
                lines.append("✅ <b>Tüm job'lar normal</b>")

            markup = {"inline_keyboard": [
                [{"text": "🔄 Yenile",    "callback_data": "ref"}],
                [{"text": "📡 Node Seç",  "callback_data": "nl"}],
                [{"text": "⚙️ Joblar",   "callback_data": "dj:__list"}],
                [{"text": "💾 Yedekler", "callback_data": "yv"}],
            ]}

        await ctx.alerter.send("\n".join(lines), markup=markup)

    async def _cmd_node(self, ctx: CommandContext, args: list[str]) -> None:
        states = await self._db.get_all_node_states()

        if not args:
            # Node listesi — inline keyboard butonlar
            if ctx.is_staging:
                s    = next((x for x in states if x["node_id"] == _STAGING_NODE), None)
                icon = "✅" if s and _seen_ok(s.get("seen_at", "")) else "🔴"
                markup = {"inline_keyboard": [
                    [{"text": f"{icon} {_STAGING_NODE}", "callback_data": f"dn:{_STAGING_NODE}"}],
                ]}
                await ctx.alerter.send("<b>📡 Staging Node</b>", markup=markup)
            else:
                rows = []
                for s in sorted(states, key=lambda x: _node_sort_key(x["node_id"])):
                    nid  = s["node_id"]
                    icon = "✅" if _seen_ok(s.get("seen_at", "")) else "🔴"
                    rows.append([{"text": f"{icon} {nid}", "callback_data": f"dn:{nid}"}])
                markup = {"inline_keyboard": rows}
                await ctx.alerter.send("<b>📡 Node Seç</b>", markup=markup)
            return

        target = args[0]
        if ctx.is_staging and target != _STAGING_NODE:
            await ctx.alerter.send(
                f"⛔ Staging kanalından sadece <code>{_STAGING_NODE}</code> görülebilir."
            )
            return

        state = next((s for s in states if s["node_id"] == target), None)
        if not state:
            await ctx.alerter.send(f"❓ Node bulunamadı: <code>{target}</code>")
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

        def _svc_visible(svc_name: str) -> bool:
            return svc_name in STAGING_SERVICES if ctx.is_staging else True

        svc_lines: list[str] = []
        restart_btns: list[dict] = []
        for svc_name, svc_data in sorted(svcs.items()):
            if not isinstance(svc_data, dict) or "healthy" not in svc_data:
                continue
            if not _svc_visible(svc_name):
                continue
            ok       = svc_data.get("healthy", True)
            svc_icon = "✅" if ok else "🔴"
            svc_lines.append(f"  {svc_icon} {svc_name}")
            if not ok and svc_name in RESTARTABLE_SVCS:
                label = svc_name.replace("teqlif-", "").replace("-", " ").title()
                cb    = f"rs:{target}:{svc_name}"
                if len(cb.encode()) <= 64:
                    restart_btns.append({"text": f"🔄 {label}", "callback_data": cb})

        if svc_lines:
            lines.append("\n<b>🔧 Servisler:</b>")
            lines.extend(svc_lines[:18])

        # Aksiyon butonları: restart (sadece down servisler) + Son Hatalar + geri
        action_rows: list[list[dict]] = [[btn] for btn in restart_btns]
        er_cb = f"er:{target}"
        if len(er_cb.encode()) <= 64:
            action_rows.append([{"text": "🔍 Son Hatalar", "callback_data": er_cb}])
        action_rows.append([{"text": "◀ Node Listesi", "callback_data": "nl"}])

        await ctx.alerter.send("\n".join(lines), markup={"inline_keyboard": action_rows})

    async def _cmd_node_errors(self, ctx: CommandContext, node_id: str) -> None:
        """Belirli node için son hataları gösterir: down servisler + stale/fail job'lar."""
        if not node_id:
            return
        if ctx.is_staging and node_id != _STAGING_NODE:
            await ctx.alerter.send(
                f"⛔ Staging kanalından sadece <code>{_STAGING_NODE}</code> görülebilir."
            )
            return

        states = await self._db.get_all_node_states()
        state  = next((s for s in states if s["node_id"] == node_id), None)
        stale  = await self._db.get_stale_jobs()
        failed = await self._db.get_failed_jobs()

        lines = [f"<b>🔍 {node_id} — Son Hatalar</b>"]

        # Down servisler
        down_svcs: list[str] = []
        if state:
            svcs = state.get("services") or {}
            for svc_name, svc_data in sorted(svcs.items()):
                if not isinstance(svc_data, dict) or "healthy" not in svc_data:
                    continue
                if ctx.is_staging and svc_name not in STAGING_SERVICES:
                    continue
                if not svc_data.get("healthy", True):
                    down_svcs.append(svc_name)
        else:
            lines.append("\n⚠️ Node gossip'ten yanıt vermiyor")

        if down_svcs:
            lines.append(f"\n<b>🔴 Down Servisler ({len(down_svcs)})</b>")
            for s in down_svcs:
                cb    = f"rs:{node_id}:{s}"
                label = s.replace("teqlif-", "").replace("-", " ").title()
                lines.append(f"  • {s}")
        else:
            lines.append("\n✅ Tüm servisler aktif")

        # Stale job'lar (staging filtresi)
        if ctx.is_staging:
            stale  = [r for r in stale  if _is_staging_job(r["job_name"])]
            failed = [r for r in failed if _is_staging_job(r["job_name"])]
        else:
            stale  = [r for r in stale  if not _is_staging_job(r["job_name"])]
            failed = [r for r in failed if not _is_staging_job(r["job_name"])]

        if stale:
            lines.append(f"\n<b>⏰ Stale Job'lar ({len(stale)})</b>")
            for row in stale[:5]:
                job  = row["job_name"]
                last = _short_dt(str(row.get("last_ok_at") or "hiç"))
                lines.append(f"  • <code>{job}</code>\n    Son: {last}")

        if failed:
            lines.append(f"\n<b>🚨 Hatalı Job'lar ({len(failed)})</b>")
            for row in failed[:5]:
                job    = row["job_name"]
                cnt    = row.get("fail_count", 1)
                reason = str(row.get("fail_reason") or "")
                lines.append(f"  • <code>{job}</code> ({cnt}× hata)")
                if reason:
                    lines.append(f"    <code>{reason[:80]}</code>")

        if not stale and not failed and not down_svcs:
            lines.append("\n✅ Son 24 saatte hata yok")

        # Restart butonları (down servisler için)
        restart_rows: list[list[dict]] = []
        for s in down_svcs:
            if s in RESTARTABLE_SVCS:
                cb = f"rs:{node_id}:{s}"
                if len(cb.encode()) <= 64:
                    label = s.replace("teqlif-", "").replace("-", " ").title()
                    restart_rows.append([{"text": f"🔄 {label}", "callback_data": cb}])

        restart_rows.append([{"text": f"◀ {node_id} Detay", "callback_data": f"dn:{node_id}"}])
        await ctx.alerter.send("\n".join(lines), markup={"inline_keyboard": restart_rows})

    async def _cmd_joblar(self, ctx: CommandContext, args: list[str]) -> None:
        stale  = await self._db.get_stale_jobs()
        failed = await self._db.get_failed_jobs()

        if ctx.is_staging:
            stale  = [r for r in stale  if _is_staging_job(r["job_name"])]
            failed = [r for r in failed if _is_staging_job(r["job_name"])]
            lines  = ["<b>⚙️ Staging Job Durumu</b>"]
        else:
            stale  = [r for r in stale  if not _is_staging_job(r["job_name"])]
            failed = [r for r in failed if not _is_staging_job(r["job_name"])]
            lines  = ["<b>⚙️ Job Durumu</b>"]

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

        await ctx.alerter.send("\n".join(lines))

    async def _cmd_job(self, ctx: CommandContext, args: list[str]) -> None:
        if not args:
            await self._cmd_joblar(ctx, [])
            return

        job_name   = args[0]
        all_health = await self._db.get_all_job_health()
        stale      = {r["job_name"] for r in await self._db.get_stale_jobs()}
        failed_set = {r["job_name"] for r in await self._db.get_failed_jobs()}

        job_data = next((r for r in all_health if r["job_name"] == job_name), None)
        if not job_data:
            await ctx.alerter.send(f"❓ Job bulunamadı: <code>{job_name}</code>")
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

        await ctx.alerter.send("\n".join(lines))

    async def _cmd_yedekler(self, ctx: CommandContext, args: list[str]) -> None:
        if ctx.is_staging:
            await ctx.alerter.send(
                "💾 Yedek bilgisi PROD kanalından görüntülenebilir."
            )
            return

        states      = await self._db.get_all_node_states()
        backup_data: dict[str, int] = {}
        for s in states:
            svcs = s.get("services") or {}
            for key in BACKUP_LABELS:
                if key in svcs and isinstance(svcs[key], dict) and "age_min" in svcs[key]:
                    backup_data[key] = svcs[key]["age_min"]

        if not backup_data:
            await ctx.alerter.send(
                "💾 Yedek verisi henüz toplanmadı.\nnode2 gossip bağlantısını kontrol edin."
            )
            return

        lines   = ["<b>💾 Yedek Durumu</b>\n"]
        ok_cnt  = 0
        err_cnt = 0
        for key, label in BACKUP_LABELS.items():
            age = backup_data.get(key)
            if age is None:
                continue
            max_min = BACKUP_MAX_MIN.get(key, 25 * 60)
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
        await ctx.alerter.send("\n".join(lines))

    async def _cmd_portlar(self, ctx: CommandContext, args: list[str]) -> None:
        states = await self._db.get_all_node_states()

        if ctx.is_staging:
            # Staging: sadece node5 staging servisleri
            lines = ["<b>🔌 Staging Servis Sağlığı</b>"]
            s = next((x for x in states if x["node_id"] == _STAGING_NODE), None)
            if s:
                svcs = s.get("services") or {}
                items = [
                    (name, data) for name, data in svcs.items()
                    if isinstance(data, dict) and "healthy" in data
                    and name in STAGING_SERVICES
                ]
                down = [name for name, data in items if not data.get("healthy")]
                if down:
                    lines.append(f"\n🔴 <b>{_STAGING_NODE}</b> — {len(down)} sorun")
                    for svc in down:
                        lines.append(f"  • {svc}")
                else:
                    lines.append(f"  ✅ <b>{_STAGING_NODE}</b> — {len(items)} staging servis")
        else:
            lines = ["<b>🔌 Servis Sağlığı</b>"]
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
        await ctx.alerter.send("\n".join(lines), markup=markup)

    async def _cmd_menu(self, ctx: CommandContext, args: list[str]) -> None:
        """Telegram '/' menüsünü yeniden kaydet ve sonucu bildir."""
        await ctx.alerter.send("⏳ Menü kayıt ediliyor...")
        prod_ok, staging_ok = await self._register_menus()
        lines = ["<b>📋 Menü Kayıt Sonucu</b>"]
        lines.append(f"PROD:    {'✅ başarılı' if prod_ok else '❌ başarısız'}")
        if self._staging_alerter and self._staging_alerter.chat_id:
            lines.append(f"STAGING: {'✅ başarılı' if staging_ok else '❌ başarısız'}")
        lines.append("\n<i>Telegram uygulamasını yeniden başlatmanız gerekebilir.</i>")
        await ctx.alerter.send("\n".join(lines))

    async def _cmd_yardim(self, ctx: CommandContext, args: list[str]) -> None:
        if ctx.is_staging:
            text = (
                "<b>🧪 teqlif-agent Staging Komutları</b>\n\n"
                "<b>Durum:</b>\n"
                f"  /durum — Staging özeti ({_STAGING_NODE})\n"
                f"  /node {_STAGING_NODE} — Staging node detay\n"
                "  /portlar — Staging servis sağlığı\n\n"
                "<b>Job'lar:</b>\n"
                "  /joblar — Stale + hatalı staging job'lar\n"
                "  /job &lt;ad&gt; — Tek job detay\n\n"
                "/yardim — Bu mesaj\n\n"
                f"<i>Staging node: {_STAGING_NODE}</i>"
            )
        else:
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
        await ctx.alerter.send(text)


# ── Yardımcı Fonksiyonlar ─────────────────────────────────────────────────────

def _node_sort_key(node_id: str) -> tuple:
    """node1..node6, node101, nodeMonitor sırasıyla sıralar."""
    if node_id.startswith("node"):
        suffix = node_id[4:]
        if suffix.isdigit():
            return (0, int(suffix))
    return (1, node_id)


def _is_staging_job(job_name: str) -> bool:
    return "staging" in job_name.lower()


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
