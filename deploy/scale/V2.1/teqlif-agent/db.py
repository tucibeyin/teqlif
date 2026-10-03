"""teqlif-agent — SQLite CRDT hafızası.

Her tablo merge kuralını belirtir:
  job_health   → LWW (Last Write Wins) — büyük timestamp kazanır
  node_state   → LWW per node_id
  cleanup_log  → G-Set (append-only, union ile birleşir)
  ttl_policies → LWW per name
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import aiosqlite

_SCHEMA = """
CREATE TABLE IF NOT EXISTS job_health (
    job_name          TEXT PRIMARY KEY,
    last_ok_at        TEXT,
    last_fail_at      TEXT,
    fail_count        INTEGER DEFAULT 0,
    expected_every_m  INTEGER DEFAULT 60,
    last_alert_at     TEXT,
    updated_at        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS node_state (
    node_id      TEXT PRIMARY KEY,
    metrics      TEXT,      -- JSON: cpu, ram, disk, net_rx, net_tx
    services     TEXT,      -- JSON: {svc: {healthy, error}}
    is_leader    INTEGER DEFAULT 0,
    agent_ver    TEXT,
    seen_at      TEXT NOT NULL,
    updated_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS cleanup_log (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    policy_name  TEXT NOT NULL,
    target_id    TEXT,
    action       TEXT,
    result       TEXT,
    leader_node  TEXT,
    created_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS ttl_policies (
    name         TEXT PRIMARY KEY,
    description  TEXT,
    config       TEXT,      -- JSON
    enabled      INTEGER DEFAULT 1,
    updated_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS leader_history (
    node_id     TEXT NOT NULL,
    started_at  TEXT NOT NULL,
    ended_at    TEXT,
    PRIMARY KEY (node_id, started_at)
);

CREATE INDEX IF NOT EXISTS idx_cleanup_log_created ON cleanup_log(created_at);
CREATE INDEX IF NOT EXISTS idx_cleanup_log_policy  ON cleanup_log(policy_name);
"""


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class AgentDB:
    def __init__(self, path: Path) -> None:
        self._path = path
        self._db: aiosqlite.Connection | None = None

    async def init(self) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._db = await aiosqlite.connect(self._path)
        self._db.row_factory = aiosqlite.Row
        await self._db.executescript(_SCHEMA)
        await self._db.commit()

    async def close(self) -> None:
        if self._db:
            await self._db.close()

    # ── Job Health ────────────────────────────────────────────────────────────

    async def mark_ok(self, job_name: str, expected_every_m: int = 60) -> None:
        now = _now()
        await self._db.execute("""
            INSERT INTO job_health (job_name, last_ok_at, fail_count, expected_every_m, updated_at)
            VALUES (?, ?, 0, ?, ?)
            ON CONFLICT(job_name) DO UPDATE SET
                last_ok_at       = excluded.last_ok_at,
                fail_count       = 0,
                expected_every_m = excluded.expected_every_m,
                updated_at       = excluded.updated_at
        """, (job_name, now, expected_every_m, now))
        await self._db.commit()

    async def mark_fail(self, job_name: str, expected_every_m: int = 60) -> None:
        now = _now()
        await self._db.execute("""
            INSERT INTO job_health (job_name, last_fail_at, fail_count, expected_every_m, updated_at)
            VALUES (?, ?, 1, ?, ?)
            ON CONFLICT(job_name) DO UPDATE SET
                last_fail_at     = excluded.last_fail_at,
                fail_count       = fail_count + 1,
                expected_every_m = excluded.expected_every_m,
                updated_at       = excluded.updated_at
        """, (job_name, now, expected_every_m, now))
        await self._db.commit()

    async def get_stale_jobs(self) -> list[dict]:
        """Beklenen interval'den fazla geçmesine rağmen çalışmayan job'lar."""
        cur = await self._db.execute("""
            SELECT job_name, last_ok_at, expected_every_m, last_alert_at
            FROM job_health
            WHERE last_ok_at IS NOT NULL
              AND (
                CAST((julianday('now') - julianday(last_ok_at)) * 1440 AS INTEGER)
                > expected_every_m * 1.5
              )
        """)
        rows = await cur.fetchall()
        return [dict(r) for r in rows]

    async def set_job_alert_sent(self, job_name: str) -> None:
        await self._db.execute(
            "UPDATE job_health SET last_alert_at=? WHERE job_name=?", (_now(), job_name)
        )
        await self._db.commit()

    # ── Node State ────────────────────────────────────────────────────────────

    async def upsert_node_state(
        self,
        node_id:   str,
        metrics:   dict,
        services:  dict,
        is_leader: bool = False,
        agent_ver: str  = "1.0",
    ) -> None:
        now = _now()
        await self._db.execute("""
            INSERT INTO node_state (node_id, metrics, services, is_leader, agent_ver, seen_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(node_id) DO UPDATE SET
                metrics    = excluded.metrics,
                services   = excluded.services,
                is_leader  = excluded.is_leader,
                agent_ver  = excluded.agent_ver,
                seen_at    = excluded.seen_at,
                updated_at = excluded.updated_at
        """, (node_id, json.dumps(metrics), json.dumps(services), int(is_leader), agent_ver, now, now))
        await self._db.commit()

    async def get_all_node_states(self) -> list[dict]:
        cur = await self._db.execute("SELECT * FROM node_state ORDER BY node_id")
        rows = await cur.fetchall()
        result = []
        for r in rows:
            d = dict(r)
            d["metrics"]  = json.loads(d["metrics"]  or "{}")
            d["services"] = json.loads(d["services"] or "{}")
            result.append(d)
        return result

    # ── Cleanup Log ───────────────────────────────────────────────────────────

    async def log_cleanup(
        self, policy_name: str, target_id: str, action: str, result: str, leader_node: str
    ) -> None:
        await self._db.execute("""
            INSERT INTO cleanup_log (policy_name, target_id, action, result, leader_node, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (policy_name, target_id, action, result, leader_node, _now()))
        await self._db.commit()

    # ── TTL Policies ──────────────────────────────────────────────────────────

    async def upsert_policy(self, name: str, description: str, config: dict) -> None:
        now = _now()
        await self._db.execute("""
            INSERT INTO ttl_policies (name, description, config, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET
                description = excluded.description,
                config      = excluded.config,
                updated_at  = excluded.updated_at
        """, (name, description, json.dumps(config), now))
        await self._db.commit()

    async def get_policies(self) -> list[dict]:
        cur = await self._db.execute("SELECT * FROM ttl_policies WHERE enabled=1")
        rows = await cur.fetchall()
        result = []
        for r in rows:
            d = dict(r)
            d["config"] = json.loads(d["config"] or "{}")
            result.append(d)
        return result

    # ── CRDT Gossip Delta ─────────────────────────────────────────────────────

    async def get_delta(self, since: str) -> dict[str, Any]:
        """since tarihinden bu yana değişen tüm kayıtları döner."""
        cur_jh = await self._db.execute(
            "SELECT * FROM job_health WHERE updated_at > ?", (since,)
        )
        cur_ns = await self._db.execute(
            "SELECT * FROM node_state WHERE updated_at > ?", (since,)
        )
        cur_cl = await self._db.execute(
            "SELECT * FROM cleanup_log WHERE created_at > ?", (since,)
        )
        cur_tp = await self._db.execute(
            "SELECT * FROM ttl_policies WHERE updated_at > ?", (since,)
        )
        return {
            "job_health":   [dict(r) for r in await cur_jh.fetchall()],
            "node_state":   [dict(r) for r in await cur_ns.fetchall()],
            "cleanup_log":  [dict(r) for r in await cur_cl.fetchall()],
            "ttl_policies": [dict(r) for r in await cur_tp.fetchall()],
        }

    async def apply_delta(self, delta: dict[str, Any]) -> None:
        """Başka bir node'dan gelen delta'yı LWW/union ile uygular."""
        for row in delta.get("job_health", []):
            await self._db.execute("""
                INSERT INTO job_health
                    (job_name, last_ok_at, last_fail_at, fail_count, expected_every_m, last_alert_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(job_name) DO UPDATE SET
                    last_ok_at       = CASE WHEN excluded.updated_at > updated_at THEN excluded.last_ok_at   ELSE last_ok_at   END,
                    last_fail_at     = CASE WHEN excluded.updated_at > updated_at THEN excluded.last_fail_at  ELSE last_fail_at  END,
                    fail_count       = CASE WHEN excluded.updated_at > updated_at THEN excluded.fail_count    ELSE fail_count    END,
                    expected_every_m = CASE WHEN excluded.updated_at > updated_at THEN excluded.expected_every_m ELSE expected_every_m END,
                    updated_at       = MAX(updated_at, excluded.updated_at)
            """, (
                row["job_name"], row.get("last_ok_at"), row.get("last_fail_at"),
                row.get("fail_count", 0), row.get("expected_every_m", 60),
                row.get("last_alert_at"), row["updated_at"],
            ))

        for row in delta.get("node_state", []):
            await self._db.execute("""
                INSERT INTO node_state (node_id, metrics, services, is_leader, agent_ver, seen_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(node_id) DO UPDATE SET
                    metrics    = CASE WHEN excluded.updated_at > updated_at THEN excluded.metrics   ELSE metrics   END,
                    services   = CASE WHEN excluded.updated_at > updated_at THEN excluded.services  ELSE services  END,
                    is_leader  = CASE WHEN excluded.updated_at > updated_at THEN excluded.is_leader ELSE is_leader END,
                    seen_at    = MAX(seen_at, excluded.seen_at),
                    updated_at = MAX(updated_at, excluded.updated_at)
            """, (
                row["node_id"], row["metrics"], row["services"],
                row.get("is_leader", 0), row.get("agent_ver", ""), row["seen_at"], row["updated_at"],
            ))

        # cleanup_log: G-Set — INSERT OR IGNORE (append-only)
        for row in delta.get("cleanup_log", []):
            await self._db.execute("""
                INSERT OR IGNORE INTO cleanup_log
                    (policy_name, target_id, action, result, leader_node, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                row["policy_name"], row.get("target_id"), row.get("action"),
                row.get("result"), row.get("leader_node"), row["created_at"],
            ))

        for row in delta.get("ttl_policies", []):
            await self._db.execute("""
                INSERT INTO ttl_policies (name, description, config, enabled, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(name) DO UPDATE SET
                    description = CASE WHEN excluded.updated_at > updated_at THEN excluded.description ELSE description END,
                    config      = CASE WHEN excluded.updated_at > updated_at THEN excluded.config      ELSE config      END,
                    enabled     = CASE WHEN excluded.updated_at > updated_at THEN excluded.enabled     ELSE enabled     END,
                    updated_at  = MAX(updated_at, excluded.updated_at)
            """, (
                row["name"], row.get("description"), row["config"],
                row.get("enabled", 1), row["updated_at"],
            ))

        await self._db.commit()
