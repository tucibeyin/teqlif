#!/usr/bin/env python3
"""
Call API Test Suite — teqlif VPS
Run on VPS: python3 test_call_api.py

Comprehensive call lifecycle tests at API/DB/WS level.
Deps: pip install httpx websockets asyncpg

NOTE: CALLEE_BUSY (USER_BUSY) cannot be tested with 2 users — the auto-end path
for stale "calling" calls prevents isolation of the callee-busy check. A 3rd user
account would be needed to test this code path cleanly.
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

    async def start(self):
        self._task = asyncio.create_task(self._run())
        await asyncio.sleep(0.5)

    async def _run(self):
        try:
            async with websockets.connect(WS_URL, ping_interval=None) as ws:
                auth = {"type": "auth", "token": self.token, "since_ts": time.time() - 5}
                await ws.send(json.dumps(auth))
                async for msg in ws:
                    if msg == "pong":
                        continue
                    try:
                        data = json.loads(msg)
                        if data.get("type", "").startswith("call_"):
                            self.events.append({**data, "_ts": time.time()})
                            log(f"  [WS:{self.username}] {data.get('type')} call_id={data.get('call_id')}")
                    except Exception:
                        pass
        except Exception:
            pass

    def get(self, event_type: str, call_id: int = None) -> list[dict]:
        return [
            e for e in self.events
            if e.get("type") == event_type and (call_id is None or e.get("call_id") == call_id)
        ]

    async def stop(self):
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

# ─── CLEANUP HELPER ────────────────────────────────────────────────────────────
async def ensure_clean(caller: ApiClient, callee: ApiClient):
    """Force-end any lingering active calls before each test."""
    seen: set[int] = set()
    for user_id in [caller.user_id, callee.user_id]:
        rows = await db_active_calls_for_user(user_id)
        for c in rows:
            cid = c["id"]
            if cid in seen:
                continue
            seen.add(cid)
            s, _ = await caller.post(f"/calls/{cid}/end")
            if s != 200:
                s, _ = await callee.post(f"/calls/{cid}/end")
            if s != 200:
                await db_execute(
                    "UPDATE calls SET status='ended', ended_at=NOW() WHERE id=$1", cid
                )
            log(f"  [CLEANUP] call_id={cid} was={c['status']} force-ended (api={s})")

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

    s3, _ = await callee.post(f"/calls/{call_id}/end")  # callee hangs up
    record("TC04: endCall (callee) 200", s3 == 200, f"status={s3}")
    await asyncio.sleep(0.5)
    record("TC04: DB=ended after callee end", await db_call_status(call_id) == "ended")
    record("TC04: caller WS call_ended", len(ws_caller.get("call_ended", call_id)) > 0)


async def tc05_stale_caller_busy(caller: ApiClient, callee: ApiClient):
    log("\n=== TC05: Stale CALLER_BUSY — crash simulation (calling auto-ended) ===")
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
    record("TC05: stale call1=ended in DB", await db_call_status(call_id1) == "ended")
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
    # Idempotent reject must NOT emit call_rejected WS
    record("TC09: no call_rejected WS (reject was no-op)",
           len(ws_caller.get("call_rejected", call_id)) == 0)
    # end_call must still send call_ended to callee
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
    # Idempotent end must NOT emit call_ended WS
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

    # Callee fetches token while call is "calling"
    s2, d2 = await callee.get(f"/calls/{call_id}/callee-token")
    record("TC18: callee-token 200 while calling", s2 == 200, f"status={s2}")
    record("TC18: token field present", bool(d2.get("token")), f"keys={list(d2.keys())}")
    record("TC18: room_name field present", bool(d2.get("room_name")), f"room={d2.get('room_name','')[:30]}")

    # Caller must NOT get callee-token (callee_id check)
    s3, _ = await caller.get(f"/calls/{call_id}/callee-token")
    record("TC18: caller cannot fetch callee-token → 404", s3 == 404, f"status={s3}")

    # After accept, callee-token still valid
    await callee.post(f"/calls/{call_id}/accept")
    await asyncio.sleep(0.3)
    s4, _ = await callee.get(f"/calls/{call_id}/callee-token")
    record("TC18: callee-token 200 while active", s4 == 200, f"status={s4}")

    # After end, callee-token rejected
    await caller.post(f"/calls/{call_id}/end")
    await asyncio.sleep(0.3)
    s5, _ = await callee.get(f"/calls/{call_id}/callee-token")
    record("TC18: callee-token 409 after end", s5 == 409, f"status={s5}")


async def final_cleanup(caller: ApiClient, callee: ApiClient):
    log("\n=== FINAL CLEANUP: Check for lingering active calls ===")
    active_caller = await db_active_calls_for_user(caller.user_id)
    active_callee = await db_active_calls_for_user(callee.user_id)
    record("CLEANUP: no stale calls for caller", len(active_caller) == 0, f"stale={active_caller}")
    record("CLEANUP: no stale calls for callee", len(active_callee) == 0, f"stale={active_callee}")
    seen: set[int] = set()
    for c in active_caller + active_callee:
        cid = c["id"]
        if cid in seen:
            continue
        seen.add(cid)
        s, _ = await caller.post(f"/calls/{cid}/end")
        log(f"  Force-ended stale call_id={cid} was={c['status']} api={s}")

# ─── MAIN ──────────────────────────────────────────────────────────────────────
async def main():
    log("=" * 60)
    log("teqlif Call API Test Suite")
    log(f"Base URL: {BASE_URL}")
    log("=" * 60)

    print(f"\nŞifreler (terminale yazılanlar görünmez)\n")
    caller_pass = getpass.getpass(f"  {CALLER_USER} şifresi: ")
    callee_pass = getpass.getpass(f"  {CALLEE_USER} şifresi: ")
    print()

    caller = ApiClient(CALLER_USER)
    callee = ApiClient(CALLEE_USER)

    log("\n=== SETUP: Login ===")
    ok_c = await caller.login(caller_pass)
    ok_e = await callee.login(callee_pass)
    record("Login teqlif (caller)", ok_c)
    record("Login tesbih (callee)", ok_e)
    if not (ok_c and ok_e):
        log("\n[FATAL] Login failed. Exiting.")
        sys.exit(1)

    ws_caller = WsCapture(caller.token, CALLER_USER)
    ws_callee = WsCapture(callee.token, CALLEE_USER)
    await ws_caller.start()
    await ws_callee.start()

    try:
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

        await final_cleanup(caller, callee)

    finally:
        await ws_caller.stop()
        await ws_callee.stop()
        await caller.close()
        await callee.close()

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
