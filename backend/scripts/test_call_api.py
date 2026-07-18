#!/usr/bin/env python3
"""
Call API Test Suite — teqlif VPS
Run on VPS: python3 test_call_api.py

Comprehensive call lifecycle tests at API/DB/WS level.
Deps: pip install httpx websockets asyncpg

Users:
  caller (A) = teqlif
  callee (B) = tesbih
  third  (C) = third account (prompted at runtime)

TC01–TC18: 2-user core lifecycle, idempotency, race, auth, endpoint checks
TC19–TC20: 2-user concurrent race & explicit active-guard validation
TC21–TC28: 3-user multi-party scenarios (WhatsApp-style busy, isolation, cross-role)
TC29–TC32: GET /calls/active recovery endpoint (crash recovery, reconnect)
"""

import asyncio
import json
import time
import sys
from datetime import datetime, timezone
import getpass

import httpx
import websockets
import asyncpg

# ─── CONFIG ────────────────────────────────────────────────────────────────────
BASE_URL    = "https://www.teqlif.com/api"
WS_URL      = "wss://www.teqlif.com/api/messages/ws"
DB_DSN      = "postgresql://teqlif:Teqlif5664@127.0.0.1:5432/teqlif"

CALLER_USER = "teqlif"
CALLEE_USER = "tesbih"
THIRD_USER  = "tucibeyin"

PASS_MARK = "✓"
FAIL_MARK = "✗"

results: list[tuple[str, bool, str]] = []

def log(msg: str):
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
    print(f"[{ts}] {msg}")

def record(name: str, passed: bool, detail: str = ""):
    mark = PASS_MARK if passed else FAIL_MARK
    results.append((name, passed, detail))
    log(f"  {mark} {name}" + (f" — {detail}" if detail else ""))

# ─── DB HELPERS ────────────────────────────────────────────────────────────────
async def db_query(sql: str, *args):
    try:
        conn = await asyncpg.connect(DB_DSN)
        row = await conn.fetchrow(sql, *args)
        await conn.close()
        return row
    except Exception as e:
        log(f"  [DB] Query failed: {e}")
        return None

async def db_execute(sql: str, *args):
    try:
        conn = await asyncpg.connect(DB_DSN)
        await conn.execute(sql, *args)
        await conn.close()
    except Exception as e:
        log(f"  [DB] Execute failed: {e}")

async def db_call_status(call_id: int) -> str | None:
    row = await db_query("SELECT status FROM calls WHERE id = $1", call_id)
    return row["status"] if row else None

async def db_active_calls_for_user(user_id: int) -> list:
    try:
        conn = await asyncpg.connect(DB_DSN)
        rows = await conn.fetch(
            "SELECT id, status FROM calls "
            "WHERE (caller_id=$1 OR callee_id=$1) "
            "AND status IN ('calling','active','connecting','connected') "
            "ORDER BY id DESC",
            user_id
        )
        await conn.close()
        return [dict(r) for r in rows]
    except Exception as e:
        log(f"  [DB] Query failed: {e}")
        return []

# ─── API CLIENT ────────────────────────────────────────────────────────────────
class ApiClient:
    def __init__(self, username: str):
        self.username = username
        self.token: str | None = None
        self.user_id: int | None = None
        self._client = httpx.AsyncClient(timeout=15.0, verify=True)

    async def login(self, password: str) -> bool:
        try:
            r = await self._client.post(f"{BASE_URL}/auth/login", json={
                "login_identifier": self.username,
                "password": password,
            })
            if r.status_code == 200:
                data = r.json()
                self.token = data.get("access_token")
                user_obj = data.get("user") or {}
                self.user_id = user_obj.get("id") or data.get("user_id") or data.get("id")
                log(f"  Login OK | user={self.username} user_id={self.user_id}")
                return True
            log(f"  Login FAIL | user={self.username} status={r.status_code} body={r.text[:200]}")
            return False
        except Exception as e:
            log(f"  Login ERROR | user={self.username} {e}")
            return False

    def _headers(self):
        return {"Authorization": f"Bearer {self.token}"}

    async def post(self, path: str, body: dict = None) -> tuple[int, dict]:
        try:
            r = await self._client.post(f"{BASE_URL}{path}", json=body or {}, headers=self._headers())
            try:
                data = r.json()
            except Exception:
                data = {"_raw": r.text}
            return r.status_code, data
        except Exception as e:
            return 0, {"_error": str(e)}

    async def get(self, path: str) -> tuple[int, dict]:
        try:
            r = await self._client.get(f"{BASE_URL}{path}", headers=self._headers())
            try:
                data = r.json()
            except Exception:
                data = {"_raw": r.text}
            return r.status_code, data
        except Exception as e:
            return 0, {"_error": str(e)}

    async def close(self):
        await self._client.aclose()

# ─── WS EVENT CAPTURE ──────────────────────────────────────────────────────────
class WsCapture:
    def __init__(self, token: str, username: str):
        self.token = token
        self.username = username
        self.events: list[dict] = []
        self._task: asyncio.Task | None = None
        self._stopped = False

    async def start(self):
        self._stopped = False
        self._task = asyncio.create_task(self._run())
        await asyncio.sleep(0.5)

    async def _run(self):
        # Reconnect loop: if the server kicks this WS (e.g. code 4008 — another session
        # on the same account, like a real device coming to foreground), reconnect after
        # a brief delay so test assertions aren't silently missed.
        if not self.token:
            return
        while not self._stopped:
            try:
                async with websockets.connect(WS_URL, ping_interval=None) as ws:
                    auth = {"type": "auth", "token": self.token, "since_ts": time.time() - 5}
                    await ws.send(json.dumps(auth))
                    async for msg in ws:
                        if self._stopped:
                            return
                        if msg == "pong":
                            continue
                        try:
                            data = json.loads(msg)
                            if data.get("type", "").startswith("call_"):
                                self.events.append({**data, "_ts": time.time()})
                                log(f"  [WS:{self.username}] {data.get('type')} call_id={data.get('call_id')}")
                        except Exception:
                            pass
            except asyncio.CancelledError:
                raise
            except Exception:
                if not self._stopped:
                    await asyncio.sleep(1)

    def get(self, event_type: str, call_id: int = None) -> list[dict]:
        return [
            e for e in self.events
            if e.get("type") == event_type and (call_id is None or e.get("call_id") == call_id)
        ]

    async def stop(self):
        self._stopped = True
        if self._task:
            self._task.cancel()
            try:
                await asyncio.wait_for(asyncio.shield(self._task), timeout=2.0)
            except (asyncio.CancelledError, asyncio.TimeoutError):
                pass

# ─── CLEANUP HELPER ────────────────────────────────────────────────────────────
async def ensure_clean(*users: ApiClient):
    """Force-end any lingering active calls before each test."""
    seen: set[int] = set()
    for user in users:
        if user.user_id is None:
            continue
        rows = await db_active_calls_for_user(user.user_id)
        for c in rows:
            cid = c["id"]
            if cid in seen:
                continue
            seen.add(cid)
            ended = False
            for u in users:
                s, _ = await u.post(f"/calls/{cid}/end")
                if s == 200:
                    ended = True
                    break
            if not ended:
                await db_execute(
                    "UPDATE calls SET status='ended', ended_at=NOW() WHERE id=$1", cid
                )
            log(f"  [CLEANUP] call_id={cid} was={c['status']} force-ended")

# ─── HELPERS ───────────────────────────────────────────────────────────────────
def err_code(body: dict) -> str:
    return (body.get("error") or {}).get("code", "")

# ─── TEST CASES ────────────────────────────────────────────────────────────────

async def tc01_caller_cancels(caller: ApiClient, callee: ApiClient,
                               ws_caller: WsCapture, ws_callee: WsCapture):
    log("\n=== TC01: Caller cancels (calling → ended) ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC01: startCall 200", s == 200, f"status={s}")
    if s != 200:
        return
    call_id = d["call_id"]

    await asyncio.sleep(0.5)
    record("TC01: DB=calling after start", await db_call_status(call_id) == "calling")
    record("TC01: callee WS call_incoming", len(ws_callee.get("call_incoming", call_id)) > 0)

    s2, _ = await caller.post(f"/calls/{call_id}/end")
    record("TC01: endCall 200", s2 == 200, f"status={s2}")

    await asyncio.sleep(0.5)
    record("TC01: DB=ended after cancel", await db_call_status(call_id) == "ended")
    record("TC01: callee WS call_ended", len(ws_callee.get("call_ended", call_id)) > 0)


async def tc02_callee_rejects(caller: ApiClient, callee: ApiClient,
                               ws_caller: WsCapture, ws_callee: WsCapture):
    log("\n=== TC02: Callee rejects (calling → rejected) ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC02: startCall 200", s == 200, f"status={s}")
    if s != 200:
        return
    call_id = d["call_id"]

    await asyncio.sleep(0.5)
    record("TC02: callee WS call_incoming", len(ws_callee.get("call_incoming", call_id)) > 0)

    s2, _ = await callee.post(f"/calls/{call_id}/reject")
    record("TC02: rejectCall 200", s2 == 200, f"status={s2}")

    await asyncio.sleep(0.5)
    record("TC02: DB=rejected", await db_call_status(call_id) == "rejected")
    record("TC02: caller WS call_rejected", len(ws_caller.get("call_rejected", call_id)) > 0)


async def tc03_accept_caller_ends(caller: ApiClient, callee: ApiClient,
                                   ws_caller: WsCapture, ws_callee: WsCapture):
    log("\n=== TC03: Accept + caller ends (calling → active → ended) ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC03: startCall 200", s == 200, f"status={s}")
    if s != 200:
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.5)

    s2, _ = await callee.post(f"/calls/{call_id}/accept")
    record("TC03: acceptCall 200", s2 == 200, f"status={s2}")
    await asyncio.sleep(0.5)
    record("TC03: DB=active after accept", await db_call_status(call_id) == "active")
    record("TC03: caller WS call_accepted", len(ws_caller.get("call_accepted", call_id)) > 0)

    # Accepting an already-active call must fail
    s_dup, _ = await callee.post(f"/calls/{call_id}/accept")
    record("TC03: accept twice → 409", s_dup == 409, f"status={s_dup}")

    s3, _ = await caller.post(f"/calls/{call_id}/end")
    record("TC03: endCall (caller) 200", s3 == 200, f"status={s3}")
    await asyncio.sleep(0.5)
    record("TC03: DB=ended after caller end", await db_call_status(call_id) == "ended")
    record("TC03: callee WS call_ended", len(ws_callee.get("call_ended", call_id)) > 0)


async def tc04_accept_callee_ends(caller: ApiClient, callee: ApiClient,
                                   ws_caller: WsCapture, ws_callee: WsCapture):
    log("\n=== TC04: Accept + callee ends (calling → active → ended by callee) ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC04: startCall 200", s == 200, f"status={s}")
    if s != 200:
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.5)

    s2, _ = await callee.post(f"/calls/{call_id}/accept")
    record("TC04: acceptCall 200", s2 == 200, f"status={s2}")
    await asyncio.sleep(0.5)
    record("TC04: DB=active after accept", await db_call_status(call_id) == "active")
    record("TC04: caller WS call_accepted", len(ws_caller.get("call_accepted", call_id)) > 0)

    s3, _ = await callee.post(f"/calls/{call_id}/end")
    record("TC04: endCall (callee) 200", s3 == 200, f"status={s3}")
    await asyncio.sleep(0.5)
    record("TC04: DB=ended after callee end", await db_call_status(call_id) == "ended")
    record("TC04: caller WS call_ended", len(ws_caller.get("call_ended", call_id)) > 0)


async def tc05_stale_caller_busy(caller: ApiClient, callee: ApiClient):
    log("\n=== TC05: Stale CALLER_BUSY — crash simulation (calling → missed, stale callee notified) ===")
    await ensure_clean(caller, callee)

    s1, d1 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC05: first startCall 200", s1 == 200, f"status={s1}")
    if s1 != 200:
        return
    call_id1 = d1["call_id"]
    log(f"  call_id1={call_id1} (not ended — simulates client crash)")

    await asyncio.sleep(0.3)

    s2, d2 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC05: second startCall succeeds (stale auto-end)", s2 == 200, f"status={s2}")
    if s2 != 200:
        await caller.post(f"/calls/{call_id1}/end")
        return
    call_id2 = d2["call_id"]
    await asyncio.sleep(0.3)
    record("TC05: stale call1=missed in DB", await db_call_status(call_id1) == "missed")
    record("TC05: new call2=calling in DB", await db_call_status(call_id2) == "calling")
    await caller.post(f"/calls/{call_id2}/end")


async def tc06_active_caller_busy(caller: ApiClient, callee: ApiClient):
    log("\n=== TC06: Active CALLER_BUSY (in active call → new start → 409) ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC06: startCall 200", s == 200, f"status={s}")
    if s != 200:
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    s2, _ = await callee.post(f"/calls/{call_id}/accept")
    record("TC06: acceptCall 200", s2 == 200, f"status={s2}")
    await asyncio.sleep(0.3)

    # Caller tries to start a new call while already in active call
    s3, d3 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC06: second start → 409 CALLER_BUSY", s3 == 409 and err_code(d3) == "CALLER_BUSY",
           f"status={s3} code={err_code(d3)}")

    await caller.post(f"/calls/{call_id}/end")


async def tc07_double_end_idempotent(caller: ApiClient, callee: ApiClient):
    log("\n=== TC07: Double end — idempotent ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    if s != 200:
        record("TC07: startCall 200", False, f"status={s}")
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    s1, _ = await caller.post(f"/calls/{call_id}/end")
    s2, _ = await caller.post(f"/calls/{call_id}/end")
    record("TC07: first end 200", s1 == 200, f"status={s1}")
    record("TC07: second end 200 (idempotent)", s2 == 200, f"status={s2}")
    record("TC07: DB=ended (not overwritten)", await db_call_status(call_id) == "ended")


async def tc08_double_reject_idempotent(caller: ApiClient, callee: ApiClient):
    log("\n=== TC08: Double reject — idempotent ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    if s != 200:
        record("TC08: startCall 200", False, f"status={s}")
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    s1, _ = await callee.post(f"/calls/{call_id}/reject")
    s2, _ = await callee.post(f"/calls/{call_id}/reject")
    record("TC08: first reject 200", s1 == 200, f"status={s1}")
    record("TC08: second reject 200 (idempotent)", s2 == 200, f"status={s2}")
    record("TC08: DB=rejected (not overwritten)", await db_call_status(call_id) == "rejected")


async def tc09_end_then_reject_race(caller: ApiClient, callee: ApiClient,
                                     ws_caller: WsCapture, ws_callee: WsCapture):
    """end fires first → status=ended; subsequent reject is idempotent (no WS sent)."""
    log("\n=== TC09: Race — end then reject (end wins) ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    if s != 200:
        record("TC09: startCall 200", False, f"status={s}")
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    s_end, _ = await caller.post(f"/calls/{call_id}/end")
    s_rej, _ = await callee.post(f"/calls/{call_id}/reject")
    record("TC09: end 200", s_end == 200, f"status={s_end}")
    record("TC09: reject 200 after end (idempotent)", s_rej == 200, f"status={s_rej}")

    await asyncio.sleep(0.5)
    record("TC09: DB=ended (end wins)", await db_call_status(call_id) == "ended")
    record("TC09: no call_rejected WS (reject was no-op)",
           len(ws_caller.get("call_rejected", call_id)) == 0)
    record("TC09: callee WS call_ended received",
           len(ws_callee.get("call_ended", call_id)) > 0)


async def tc10_reject_then_end_race(caller: ApiClient, callee: ApiClient,
                                     ws_caller: WsCapture, ws_callee: WsCapture):
    """reject fires first → status=rejected; subsequent end is idempotent (no WS sent)."""
    log("\n=== TC10: Race — reject then end (reject wins) ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    if s != 200:
        record("TC10: startCall 200", False, f"status={s}")
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    s_rej, _ = await callee.post(f"/calls/{call_id}/reject")
    s_end, _ = await caller.post(f"/calls/{call_id}/end")
    record("TC10: reject 200", s_rej == 200, f"status={s_rej}")
    record("TC10: end 200 after reject (idempotent)", s_end == 200, f"status={s_end}")

    await asyncio.sleep(0.5)
    record("TC10: DB=rejected (reject wins)", await db_call_status(call_id) == "rejected")
    record("TC10: caller WS call_rejected received",
           len(ws_caller.get("call_rejected", call_id)) > 0)
    record("TC10: no call_ended WS (end was no-op)",
           len(ws_callee.get("call_ended", call_id)) == 0)


async def tc11_caller_retry_after_reject(caller: ApiClient, callee: ApiClient):
    log("\n=== TC11: Caller retry after callee reject (no CALLER_BUSY) ===")
    await ensure_clean(caller, callee)

    s1, d1 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC11: first startCall 200", s1 == 200, f"status={s1}")
    if s1 != 200:
        return
    call_id1 = d1["call_id"]
    await asyncio.sleep(0.3)

    await callee.post(f"/calls/{call_id1}/reject")
    await asyncio.sleep(0.3)

    s2, d2 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC11: retry startCall 200 (no CALLER_BUSY)", s2 == 200, f"status={s2}")
    if s2 == 200:
        call_id2 = d2["call_id"]
        record("TC11: new call has different id", call_id2 != call_id1, f"id1={call_id1} id2={call_id2}")
        await caller.post(f"/calls/{call_id2}/end")


async def tc12_caller_retry_after_stale_end(caller: ApiClient, callee: ApiClient):
    """After caller ends a calling call, retry must succeed immediately."""
    log("\n=== TC12: Caller retry after own cancel (no CALLER_BUSY) ===")
    await ensure_clean(caller, callee)

    s1, d1 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC12: first startCall 200", s1 == 200, f"status={s1}")
    if s1 != 200:
        return
    call_id1 = d1["call_id"]
    await asyncio.sleep(0.3)

    await caller.post(f"/calls/{call_id1}/end")
    await asyncio.sleep(0.3)

    s2, d2 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC12: retry startCall 200 (no CALLER_BUSY)", s2 == 200, f"status={s2}")
    if s2 == 200:
        await caller.post(f"/calls/{d2['call_id']}/end")


async def tc13_self_call(caller: ApiClient):
    log("\n=== TC13: Self-call → 400 ===")
    s, _ = await caller.post("/calls/start", {"callee_id": caller.user_id})
    record("TC13: self-call → 400", s == 400, f"status={s}")


async def tc14_invalid_callee(caller: ApiClient):
    log("\n=== TC14: Non-existent callee → 404 ===")
    s, _ = await caller.post("/calls/start", {"callee_id": 999999})
    record("TC14: invalid callee_id → 404", s == 404, f"status={s}")


async def tc15_reject_by_caller(caller: ApiClient, callee: ApiClient):
    """Caller calls /reject on their own outgoing call → 404 (callee_id mismatch)."""
    log("\n=== TC15: Reject by wrong party (caller tries /reject) → 404 ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    if s != 200:
        record("TC15: startCall 200", False, f"status={s}")
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    s2, _ = await caller.post(f"/calls/{call_id}/reject")
    record("TC15: caller /reject → 404 (callee_id check)", s2 == 404, f"status={s2}")

    await caller.post(f"/calls/{call_id}/end")


async def tc16_accept_already_ended(caller: ApiClient, callee: ApiClient):
    log("\n=== TC16: Accept already-ended call → 409 ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    if s != 200:
        record("TC16: startCall 200", False, f"status={s}")
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    await caller.post(f"/calls/{call_id}/end")
    await asyncio.sleep(0.3)

    s2, _ = await callee.post(f"/calls/{call_id}/accept")
    record("TC16: accept ended call → 409", s2 == 409, f"status={s2}")


async def tc17_status_endpoint(caller: ApiClient, callee: ApiClient):
    log("\n=== TC17: Status endpoint — calling → active → ended ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    if s != 200:
        record("TC17: startCall 200", False, f"status={s}")
        return
    call_id = d["call_id"]

    _, d2 = await callee.get(f"/calls/{call_id}/status")
    record("TC17: status=calling", d2.get("status") == "calling", f"data={d2}")
    record("TC17: accepted_at=null while calling", d2.get("accepted_at") is None)

    await callee.post(f"/calls/{call_id}/accept")
    await asyncio.sleep(0.3)
    _, d3 = await callee.get(f"/calls/{call_id}/status")
    record("TC17: status=active after accept", d3.get("status") == "active", f"data={d3}")
    record("TC17: accepted_at set after accept", d3.get("accepted_at") is not None)

    await caller.post(f"/calls/{call_id}/end")
    await asyncio.sleep(0.3)
    _, d4 = await callee.get(f"/calls/{call_id}/status")
    record("TC17: status=ended after end", d4.get("status") == "ended", f"data={d4}")


async def tc18_callee_token_endpoint(caller: ApiClient, callee: ApiClient):
    log("\n=== TC18: Callee-token endpoint ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    if s != 200:
        record("TC18: startCall 200", False, f"status={s}")
        return
    call_id = d["call_id"]

    s2, d2 = await callee.get(f"/calls/{call_id}/callee-token")
    record("TC18: callee-token 200 while calling", s2 == 200, f"status={s2}")
    record("TC18: token field present", bool(d2.get("token")), f"keys={list(d2.keys())}")
    record("TC18: room_name field present", bool(d2.get("room_name")), f"room={d2.get('room_name','')[:30]}")

    s3, _ = await caller.get(f"/calls/{call_id}/callee-token")
    record("TC18: caller cannot fetch callee-token → 404", s3 == 404, f"status={s3}")

    await callee.post(f"/calls/{call_id}/accept")
    await asyncio.sleep(0.3)
    s4, _ = await callee.get(f"/calls/{call_id}/callee-token")
    record("TC18: callee-token 200 while active", s4 == 200, f"status={s4}")

    await caller.post(f"/calls/{call_id}/end")
    await asyncio.sleep(0.3)
    s5, _ = await callee.get(f"/calls/{call_id}/callee-token")
    record("TC18: callee-token 409 after end", s5 == 409, f"status={s5}")


# ─── TC19-TC20: Concurrent race & explicit active-guard ────────────────────────

async def tc19_concurrent_accept_reject(caller: ApiClient, callee: ApiClient,
                                         ws_caller: WsCapture, ws_callee: WsCapture):
    """Concurrent /accept and /reject — SELECT FOR UPDATE ensures exactly one wins.
    Before the FOR UPDATE fix: reject could read stale 'calling' while accept committed
    'active', then overwrite 'active' with 'rejected'. This TC validates the fix."""
    log("\n=== TC19: Concurrent accept+reject race (FOR UPDATE validation) ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC19: startCall 200", s == 200, f"status={s}")
    if s != 200:
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    # Fire both concurrently — one must win, one must lose
    accept_task = asyncio.create_task(callee.post(f"/calls/{call_id}/accept"))
    reject_task = asyncio.create_task(callee.post(f"/calls/{call_id}/reject"))
    (accept_s, _), (reject_s, _) = await asyncio.gather(accept_task, reject_task)

    await asyncio.sleep(0.5)
    final_status = await db_call_status(call_id)

    if accept_s == 200:
        # Accept won: DB must stay "active"; reject must be a no-op (active guard)
        record("TC19: accept won → DB=active (no lost-update)",
               final_status == "active", f"db={final_status}")
        record("TC19: reject returned 200 (active guard idempotent)", reject_s == 200,
               f"reject_s={reject_s}")
        record("TC19: no call_rejected WS (active guard blocked emit)",
               len(ws_caller.get("call_rejected", call_id)) == 0)
        await caller.post(f"/calls/{call_id}/end")
    elif reject_s == 200:
        # Reject won: DB must be "rejected"; accept must return 409
        record("TC19: reject won → DB=rejected", final_status == "rejected",
               f"db={final_status}")
        record("TC19: accept returned 409 (CONFLICT)", accept_s == 409,
               f"accept_s={accept_s}")
        record("TC19: call_rejected WS sent to caller",
               len(ws_caller.get("call_rejected", call_id)) > 0)
    else:
        record("TC19: exactly one side must win", False,
               f"accept={accept_s} reject={reject_s} db={final_status}")


async def tc20_reject_after_accept(caller: ApiClient, callee: ApiClient,
                                    ws_caller: WsCapture):
    """Explicit reject after accept — tests the 'active' guard without relying
    on real-device timing. Validates that DB stays 'active' and no WS is emitted."""
    log("\n=== TC20: Reject after accept — active guard explicit ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC20: startCall 200", s == 200, f"status={s}")
    if s != 200:
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    s2, _ = await callee.post(f"/calls/{call_id}/accept")
    record("TC20: acceptCall 200", s2 == 200, f"status={s2}")
    await asyncio.sleep(0.3)
    record("TC20: DB=active after accept", await db_call_status(call_id) == "active")

    # Spurious /reject (ghost-call dismiss scenario)
    s3, _ = await callee.post(f"/calls/{call_id}/reject")
    record("TC20: spurious /reject returns 200 (active guard)", s3 == 200, f"status={s3}")
    await asyncio.sleep(0.3)
    record("TC20: DB still=active (active guard blocked overwrite)",
           await db_call_status(call_id) == "active")
    record("TC20: no call_rejected WS emitted",
           len(ws_caller.get("call_rejected", call_id)) == 0)

    await caller.post(f"/calls/{call_id}/end")


# ─── TC21-TC28: 3-user multi-party scenarios ───────────────────────────────────

async def tc21_user_busy_calling(caller: ApiClient, callee: ApiClient, third: ApiClient):
    """C calls B while A→B is in 'calling' state → USER_BUSY.
    B is the callee of an active incoming call — a third party cannot ring B."""
    log("\n=== TC21: USER_BUSY — C calls B while A→B is ringing (calling state) ===")
    await ensure_clean(caller, callee, third)

    s1, d1 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC21: A→B startCall 200", s1 == 200, f"status={s1}")
    if s1 != 200:
        return
    call_id1 = d1["call_id"]
    await asyncio.sleep(0.3)
    record("TC21: A→B DB=calling", await db_call_status(call_id1) == "calling")

    s2, d2 = await third.post("/calls/start", {"callee_id": callee.user_id})
    record("TC21: C→B → 409 USER_BUSY (B ringing)",
           s2 == 409 and err_code(d2) == "USER_BUSY",
           f"status={s2} code={err_code(d2)}")

    # Original A→B call untouched
    record("TC21: A→B still calling (untouched by C's attempt)",
           await db_call_status(call_id1) == "calling")

    await caller.post(f"/calls/{call_id1}/end")


async def tc22_user_busy_active(caller: ApiClient, callee: ApiClient, third: ApiClient):
    """C calls B while A→B is active → USER_BUSY.
    B is in a live call — no one can reach B until the call ends."""
    log("\n=== TC22: USER_BUSY — C calls B while A→B is active ===")
    await ensure_clean(caller, callee, third)

    s1, d1 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC22: A→B startCall 200", s1 == 200, f"status={s1}")
    if s1 != 200:
        return
    call_id1 = d1["call_id"]
    await asyncio.sleep(0.3)

    s2, _ = await callee.post(f"/calls/{call_id1}/accept")
    record("TC22: B accepts A→B 200", s2 == 200, f"status={s2}")
    await asyncio.sleep(0.3)
    record("TC22: A→B DB=active", await db_call_status(call_id1) == "active")

    s3, d3 = await third.post("/calls/start", {"callee_id": callee.user_id})
    record("TC22: C→B → 409 USER_BUSY (B in active call)",
           s3 == 409 and err_code(d3) == "USER_BUSY",
           f"status={s3} code={err_code(d3)}")

    await caller.post(f"/calls/{call_id1}/end")


async def tc23_concurrent_caller_race(caller: ApiClient, callee: ApiClient, third: ApiClient,
                                       ws_callee: WsCapture):
    """A and C simultaneously call B — exactly one 200, one 409 USER_BUSY.
    Tests DB-level callee_busy check under true concurrency."""
    log("\n=== TC23: Concurrent caller race — A and C both call B simultaneously ===")
    await ensure_clean(caller, callee, third)

    a_task = asyncio.create_task(caller.post("/calls/start", {"callee_id": callee.user_id}))
    c_task = asyncio.create_task(third.post("/calls/start", {"callee_id": callee.user_id}))
    (sa, da), (sc, dc) = await asyncio.gather(a_task, c_task)

    await asyncio.sleep(0.5)

    a_won = sa == 200
    c_won = sc == 200
    record("TC23: exactly one caller wins 200", a_won != c_won, f"A={sa} C={sc}")

    if a_won:
        winner_d, loser_s, loser_d, winner_name, winner = da, sc, dc, "A", caller
    elif c_won:
        winner_d, loser_s, loser_d, winner_name, winner = dc, sa, da, "C", third
    else:
        record("TC23: loser gets 409 USER_BUSY", False, f"A={sa} C={sc} — both failed")
        return

    win_call_id = winner_d.get("call_id")
    record("TC23: loser gets 409 USER_BUSY",
           loser_s == 409 and err_code(loser_d) == "USER_BUSY",
           f"loser_status={loser_s} code={err_code(loser_d)}")
    if win_call_id:
        record("TC23: winner call DB=calling",
               await db_call_status(win_call_id) == "calling",
               f"winner={winner_name} call_id={win_call_id}")
        await asyncio.sleep(0.3)
        # B should receive exactly 1 call_incoming for the winning call
        incoming = ws_callee.get("call_incoming", win_call_id)
        record("TC23: B gets exactly 1 call_incoming (no duplicate)", len(incoming) == 1,
               f"count={len(incoming)}")
        await winner.post(f"/calls/{win_call_id}/end")


async def tc24_third_party_end(caller: ApiClient, callee: ApiClient, third: ApiClient):
    """C (unrelated user) tries to /end A-B's call → 404.
    /end checks caller_id OR callee_id — third party must be rejected."""
    log("\n=== TC24: Third-party /end attempt → 404 ===")
    await ensure_clean(caller, callee, third)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC24: A→B startCall 200", s == 200, f"status={s}")
    if s != 200:
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    s2, _ = await third.post(f"/calls/{call_id}/end")
    record("TC24: C /end → 404 (not a participant)", s2 == 404, f"status={s2}")
    record("TC24: DB still=calling (end rejected)", await db_call_status(call_id) == "calling")

    await caller.post(f"/calls/{call_id}/end")


async def tc25_third_party_reject(caller: ApiClient, callee: ApiClient, third: ApiClient):
    """C (not the callee) tries to /reject A-B's call → 404.
    TC15 tests caller /reject; TC25 tests a completely unrelated third party."""
    log("\n=== TC25: Third-party /reject attempt → 404 ===")
    await ensure_clean(caller, callee, third)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC25: A→B startCall 200", s == 200, f"status={s}")
    if s != 200:
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    s2, _ = await third.post(f"/calls/{call_id}/reject")
    record("TC25: C /reject → 404 (not the callee)", s2 == 404, f"status={s2}")
    record("TC25: DB still=calling (reject rejected)", await db_call_status(call_id) == "calling")

    await caller.post(f"/calls/{call_id}/end")


async def tc26_ws_isolation(caller: ApiClient, callee: ApiClient, third: ApiClient,
                              ws_caller: WsCapture, ws_callee: WsCapture,
                              ws_third: WsCapture):
    """A-B call events (call_accepted, call_ended) must NOT be delivered to C's WS.
    WS broadcast is keyed on user_id — only participants receive their events."""
    log("\n=== TC26: WS event isolation — C does not receive A-B call events ===")
    await ensure_clean(caller, callee, third)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC26: A→B startCall 200", s == 200, f"status={s}")
    if s != 200:
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    await callee.post(f"/calls/{call_id}/accept")
    await asyncio.sleep(0.3)
    await caller.post(f"/calls/{call_id}/end")
    await asyncio.sleep(0.5)

    record("TC26: A receives call_accepted WS",
           len(ws_caller.get("call_accepted", call_id)) > 0)
    record("TC26: B receives call_ended WS",
           len(ws_callee.get("call_ended", call_id)) > 0)

    leaked = [e for e in ws_third.events if e.get("call_id") == call_id]
    record("TC26: C receives ZERO events for A-B call",
           len(leaked) == 0,
           f"leaked={[e.get('type') for e in leaked]}")


async def tc27_callee_busy_while_ringing(caller: ApiClient, callee: ApiClient, third: ApiClient):
    """B is ringed by A (B is callee in 'calling' call). B tries to call C.
    Expected: 409 CALLER_BUSY — B must first reject/ignore A's call before initiating.
    (Before the CALLER_BUSY callee-role fix, B's action would silently auto-end A's call.)"""
    log("\n=== TC27: CALLER_BUSY — B (callee, being ringed) tries to call C ===")
    await ensure_clean(caller, callee, third)

    s1, d1 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC27: A→B startCall 200", s1 == 200, f"status={s1}")
    if s1 != 200:
        return
    call_id1 = d1["call_id"]
    await asyncio.sleep(0.3)
    record("TC27: A→B DB=calling", await db_call_status(call_id1) == "calling")

    # B tries to initiate a call to C while being ringed by A
    s2, d2 = await callee.post("/calls/start", {"callee_id": third.user_id})
    record("TC27: B→C → 409 CALLER_BUSY (B is callee in ringing call)",
           s2 == 409 and err_code(d2) == "CALLER_BUSY",
           f"status={s2} code={err_code(d2)}")

    # A's call must NOT have been silently terminated
    record("TC27: A→B still calling (A's call preserved)",
           await db_call_status(call_id1) == "calling")

    await caller.post(f"/calls/{call_id1}/end")


async def tc28_callee_busy_in_active(caller: ApiClient, callee: ApiClient, third: ApiClient):
    """B is in active call with A. B tries to call C → CALLER_BUSY.
    Tests the 'callee_id == current_user.id AND status=active' branch of CALLER_BUSY."""
    log("\n=== TC28: CALLER_BUSY — B (callee in active call) tries to call C ===")
    await ensure_clean(caller, callee, third)

    s1, d1 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC28: A→B startCall 200", s1 == 200, f"status={s1}")
    if s1 != 200:
        return
    call_id1 = d1["call_id"]
    await asyncio.sleep(0.3)

    s2, _ = await callee.post(f"/calls/{call_id1}/accept")
    record("TC28: B accepts A→B 200", s2 == 200, f"status={s2}")
    await asyncio.sleep(0.3)
    record("TC28: A→B DB=active", await db_call_status(call_id1) == "active")

    s3, d3 = await callee.post("/calls/start", {"callee_id": third.user_id})
    record("TC28: B→C → 409 CALLER_BUSY (B is callee in active call)",
           s3 == 409 and err_code(d3) == "CALLER_BUSY",
           f"status={s3} code={err_code(d3)}")

    await caller.post(f"/calls/{call_id1}/end")



# ─── TC29-TC32: GET /calls/active recovery endpoint ────────────────────────────

async def tc29_active_caller_recovery(caller: ApiClient, callee: ApiClient):
    """GET /calls/active while caller is in 'calling' state.
    Simulates crash recovery: caller restarts app, queries active call, restores state."""
    log("\n=== TC29: Active call recovery — caller perspective (calling state) ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC29: A→B startCall 200", s == 200, f"status={s}")
    if s != 200:
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    s2, d2 = await caller.get("/calls/active")
    record("TC29: GET /calls/active 200", s2 == 200, f"status={s2}")
    active = d2.get("active_call")
    record("TC29: active_call not null", active is not None, f"data={d2}")
    if active:
        record("TC29: role=caller", active.get("role") == "caller",         f"role={active.get('role')}")
        record("TC29: status=calling",active.get("status") == "calling",    f"status={active.get('status')}")
        record("TC29: call_id matches", active.get("call_id") == call_id,   f"active_id={active.get('call_id')} expected={call_id}")
        record("TC29: fresh token present", bool(active.get("token")),       f"token_len={len(active.get('token',''))}")
        record("TC29: room_name present", bool(active.get("room_name")),     f"room={active.get('room_name','')[:30]}")
        record("TC29: other_user.username=tesbih",
               (active.get("other_user") or {}).get("username") == callee.username,
               f"other={active.get('other_user')}")
        record("TC29: livekit_url present", bool(active.get("livekit_url")), f"url={active.get('livekit_url','')[:30]}")
        record("TC29: accepted_at is null (not yet accepted)", active.get("accepted_at") is None)
    log(f"  [TC29] DEBUG active_call={active}")
    await caller.post(f"/calls/{call_id}/end")


async def tc30_active_callee_recovery(caller: ApiClient, callee: ApiClient):
    """GET /calls/active while callee is being ringed.
    Simulates callee app restart — should restore incoming call state."""
    log("\n=== TC30: Active call recovery — callee perspective (ringing) ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC30: A→B startCall 200", s == 200, f"status={s}")
    if s != 200:
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    s2, d2 = await callee.get("/calls/active")
    record("TC30: GET /calls/active 200", s2 == 200, f"status={s2}")
    active = d2.get("active_call")
    record("TC30: active_call not null (callee sees incoming)", active is not None, f"data={d2}")
    if active:
        record("TC30: role=callee",        active.get("role") == "callee",       f"role={active.get('role')}")
        record("TC30: status=calling",     active.get("status") == "calling",    f"status={active.get('status')}")
        record("TC30: call_id matches",    active.get("call_id") == call_id,     f"active_id={active.get('call_id')} expected={call_id}")
        record("TC30: fresh token present",bool(active.get("token")),            f"token_len={len(active.get('token',''))}")
        record("TC30: other_user.username=teqlif",
               (active.get("other_user") or {}).get("username") == caller.username,
               f"other={active.get('other_user')}")
    await caller.post(f"/calls/{call_id}/end")


async def tc31_active_no_call(caller: ApiClient):
    """GET /calls/active when no call is in progress → active_call=null (never 404)."""
    log("\n=== TC31: GET /calls/active — no active call ===")
    # No ensure_clean needed: the test just checks the idle state.

    s, d = await caller.get("/calls/active")
    record("TC31: GET /calls/active 200 (no call)", s == 200, f"status={s}")
    active = d.get("active_call")
    record("TC31: active_call is null", active is None, f"active_call={active}")


async def tc32_active_accepted_call_recovery(caller: ApiClient, callee: ApiClient):
    """GET /calls/active while call is in 'active' status (both parties accepted).
    Both caller and callee should get role-appropriate fresh LK tokens."""
    log("\n=== TC32: Active call recovery — live call (both sides) ===")
    await ensure_clean(caller, callee)

    s, d = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC32: A→B startCall 200", s == 200, f"status={s}")
    if s != 200:
        return
    call_id = d["call_id"]
    await asyncio.sleep(0.3)

    s2, _ = await callee.post(f"/calls/{call_id}/accept")
    record("TC32: B accepts 200", s2 == 200, f"status={s2}")
    await asyncio.sleep(0.3)
    record("TC32: DB=active", await db_call_status(call_id) == "active")

    # Caller recovery
    s3, d3 = await caller.get("/calls/active")
    record("TC32: caller GET /calls/active 200", s3 == 200, f"status={s3}")
    ca = d3.get("active_call")
    record("TC32: caller active_call not null",  ca is not None,                  f"data={d3}")
    if ca:
        record("TC32: caller role=caller",       ca.get("role")   == "caller",    f"role={ca.get('role')}")
        record("TC32: caller status=active",     ca.get("status") == "active",    f"status={ca.get('status')}")
        record("TC32: caller token present",     bool(ca.get("token")),           f"token_len={len(ca.get('token',''))}")
        record("TC32: caller accepted_at set",   ca.get("accepted_at") is not None, f"accepted_at={ca.get('accepted_at','')[:30]}")

    # Callee recovery
    s4, d4 = await callee.get("/calls/active")
    record("TC32: callee GET /calls/active 200", s4 == 200, f"status={s4}")
    cb = d4.get("active_call")
    record("TC32: callee active_call not null",  cb is not None,                  f"data={d4}")
    if cb:
        record("TC32: callee role=callee",       cb.get("role")   == "callee",    f"role={cb.get('role')}")
        record("TC32: callee status=active",     cb.get("status") == "active",    f"status={cb.get('status')}")
        record("TC32: callee token present",     bool(cb.get("token")),           f"token_len={len(cb.get('token',''))}")

    # Tokens should be different (different user roles → different LK grants)
    if ca and cb and ca.get("token") and cb.get("token"):
        record("TC32: caller and callee get distinct tokens",
               ca.get("token") != cb.get("token"),
               f"same={ca.get('token') == cb.get('token')}")

    await caller.post(f"/calls/{call_id}/end")


# ─── FINAL CLEANUP ─────────────────────────────────────────────────────────────

async def final_cleanup(*users: ApiClient):
    log("\n=== FINAL CLEANUP: Check for lingering active calls ===")
    all_stale: list[dict] = []
    seen: set[int] = set()
    for user in users:
        if user.user_id is None:
            continue
        rows = await db_active_calls_for_user(user.user_id)
        for c in rows:
            if c["id"] not in seen:
                seen.add(c["id"])
                all_stale.append(c)

    for u in users:
        if u.user_id is None:
            continue
        stale = [c for c in all_stale
                 if c["id"] in seen]
        record(f"CLEANUP: no stale calls for {u.username}", len(stale) == 0,
               f"stale={stale}")

    for c in all_stale:
        cid = c["id"]
        for u in users:
            s, _ = await u.post(f"/calls/{cid}/end")
            if s == 200:
                break
        else:
            await db_execute("UPDATE calls SET status='ended', ended_at=NOW() WHERE id=$1", cid)
        log(f"  Force-ended stale call_id={cid} was={c['status']}")


# ─── MAIN ──────────────────────────────────────────────────────────────────────
async def main():
    global THIRD_USER

    log("=" * 60)
    log("teqlif Call API Test Suite")
    log(f"Base URL: {BASE_URL}")
    log("=" * 60)

    print(f"\nŞifreler (terminale yazılanlar görünmez)\n")
    caller_pass = getpass.getpass(f"  {CALLER_USER} şifresi: ")
    callee_pass = getpass.getpass(f"  {CALLEE_USER} şifresi: ")
    third_pass  = getpass.getpass(f"  {THIRD_USER} şifresi: ")
    print()

    caller = ApiClient(CALLER_USER)
    callee = ApiClient(CALLEE_USER)
    third  = ApiClient(THIRD_USER)

    log("\n=== SETUP: Login ===")
    ok_a = await caller.login(caller_pass)
    ok_b = await callee.login(callee_pass)
    ok_c = await third.login(third_pass)
    record("Login A (caller/teqlif)", ok_a)
    record("Login B (callee/tesbih)", ok_b)
    record(f"Login C (third/{THIRD_USER})", ok_c)
    if not (ok_a and ok_b):
        log("\n[FATAL] A or B login failed. Exiting.")
        sys.exit(1)
    if not ok_c:
        log("\n[WARN] Third user login failed — TC21-TC28 will be skipped.")

    ws_caller = WsCapture(caller.token, CALLER_USER)
    ws_callee = WsCapture(callee.token, CALLEE_USER)
    ws_third  = WsCapture(third.token if ok_c else "", THIRD_USER)
    await ws_caller.start()
    await ws_callee.start()
    if ok_c:
        await ws_third.start()

    try:
        # ── 2-user core ────────────────────────────────────────────────────────
        await tc01_caller_cancels(caller, callee, ws_caller, ws_callee)
        await asyncio.sleep(1)
        await tc02_callee_rejects(caller, callee, ws_caller, ws_callee)
        await asyncio.sleep(1)
        await tc03_accept_caller_ends(caller, callee, ws_caller, ws_callee)
        await asyncio.sleep(1)
        await tc04_accept_callee_ends(caller, callee, ws_caller, ws_callee)
        await asyncio.sleep(1)
        await tc05_stale_caller_busy(caller, callee)
        await asyncio.sleep(1)
        await tc06_active_caller_busy(caller, callee)
        await asyncio.sleep(1)
        await tc07_double_end_idempotent(caller, callee)
        await asyncio.sleep(1)
        await tc08_double_reject_idempotent(caller, callee)
        await asyncio.sleep(1)
        await tc09_end_then_reject_race(caller, callee, ws_caller, ws_callee)
        await asyncio.sleep(1)
        await tc10_reject_then_end_race(caller, callee, ws_caller, ws_callee)
        await asyncio.sleep(1)
        await tc11_caller_retry_after_reject(caller, callee)
        await asyncio.sleep(1)
        await tc12_caller_retry_after_stale_end(caller, callee)
        await asyncio.sleep(0.5)
        await tc13_self_call(caller)
        await asyncio.sleep(0.5)
        await tc14_invalid_callee(caller)
        await asyncio.sleep(0.5)
        await tc15_reject_by_caller(caller, callee)
        await asyncio.sleep(1)
        await tc16_accept_already_ended(caller, callee)
        await asyncio.sleep(1)
        await tc17_status_endpoint(caller, callee)
        await asyncio.sleep(1)
        await tc18_callee_token_endpoint(caller, callee)
        await asyncio.sleep(1)

        # ── Concurrent race & active-guard ─────────────────────────────────────
        await tc19_concurrent_accept_reject(caller, callee, ws_caller, ws_callee)
        await asyncio.sleep(1)
        await tc20_reject_after_accept(caller, callee, ws_caller)
        await asyncio.sleep(1)

        # ── 3-user multi-party ──────────────────────────────────────────────────
        if ok_c:
            await tc21_user_busy_calling(caller, callee, third)
            await asyncio.sleep(1)
            await tc22_user_busy_active(caller, callee, third)
            await asyncio.sleep(1)
            await tc23_concurrent_caller_race(caller, callee, third, ws_callee)
            await asyncio.sleep(1)
            await tc24_third_party_end(caller, callee, third)
            await asyncio.sleep(1)
            await tc25_third_party_reject(caller, callee, third)
            await asyncio.sleep(1)
            await tc26_ws_isolation(caller, callee, third, ws_caller, ws_callee, ws_third)
            await asyncio.sleep(1)
            await tc27_callee_busy_while_ringing(caller, callee, third)
            await asyncio.sleep(1)
            await tc28_callee_busy_in_active(caller, callee, third)
            await asyncio.sleep(1)
        else:
            log("\n  [SKIP] TC21-TC28 skipped (third user login failed)")

        # ── Recovery endpoint ───────────────────────────────────────────────────
        await tc31_active_no_call(caller)           # no-call case first (cheap, no cleanup)
        await asyncio.sleep(0.5)
        await tc29_active_caller_recovery(caller, callee)
        await asyncio.sleep(1)
        await tc30_active_callee_recovery(caller, callee)
        await asyncio.sleep(1)
        await tc32_active_accepted_call_recovery(caller, callee)
        await asyncio.sleep(1)

        await final_cleanup(caller, callee, third)

    finally:
        await ws_caller.stop()
        await ws_callee.stop()
        await ws_third.stop()
        await caller.close()
        await callee.close()
        await third.close()

    log("\n" + "=" * 60)
    log("RESULTS SUMMARY")
    log("=" * 60)
    passed = sum(1 for _, ok, _ in results if ok)
    failed = sum(1 for _, ok, _ in results if not ok)
    for name, ok, detail in results:
        mark = PASS_MARK if ok else FAIL_MARK
        log(f"  {mark} {name}" + (f"  [{detail}]" if detail and not ok else ""))
    log("-" * 60)
    log(f"  Passed: {passed}  Failed: {failed}  Total: {len(results)}")
    log("=" * 60)
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    asyncio.run(main())
