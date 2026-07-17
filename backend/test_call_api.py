#!/usr/bin/env python3
"""
Call API Test Script — teqlif VPS
Run on VPS: python3 test_call_api.py

Tests call lifecycle, state machine, and edge cases at API/DB level.
No mobile UI required. Needs: pip install httpx websockets asyncpg
"""

import asyncio
import json
import time
import sys
from datetime import datetime, timezone

import httpx
import websockets
import asyncpg

# ─── CONFIG ────────────────────────────────────────────────────────────────────
BASE_URL   = "https://www.teqlif.com/api"
WS_URL     = "wss://www.teqlif.com/api/messages/ws"
DB_DSN     = "postgresql://teqlif:teqlif@localhost:5432/teqlif"  # adjust if different

CALLER_USER = "teqlif"    # iOS caller
CALLEE_USER = "tesbih"    # Android callee
PASSWORD    = "teqlif123" # same password for both (adjust if different)

PASS_MARK = "✓"
FAIL_MARK = "✗"
SKIP_MARK = "—"

# ─── RESULTS ───────────────────────────────────────────────────────────────────
results = []

def log(msg: str):
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
    print(f"[{ts}] {msg}")

def record(name: str, passed: bool, detail: str = ""):
    mark = PASS_MARK if passed else FAIL_MARK
    results.append((name, passed, detail))
    log(f"  {mark} {name}" + (f" — {detail}" if detail else ""))

# ─── DB HELPER ─────────────────────────────────────────────────────────────────
async def db_query(sql: str, *args):
    try:
        conn = await asyncpg.connect(DB_DSN)
        row = await conn.fetchrow(sql, *args)
        await conn.close()
        return row
    except Exception as e:
        log(f"  [DB] Query failed: {e}")
        return None

async def db_call_status(call_id: int) -> str | None:
    row = await db_query("SELECT status FROM calls WHERE id = $1", call_id)
    return row["status"] if row else None

async def db_active_calls_for_user(user_id: int) -> list:
    try:
        conn = await asyncpg.connect(DB_DSN)
        rows = await conn.fetch(
            "SELECT id, status FROM calls WHERE (caller_id=$1 OR callee_id=$1) AND status IN ('calling','active') ORDER BY id DESC",
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
                self.user_id = data.get("user_id") or data.get("id")
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
        self._ws = None
        self._task: asyncio.Task | None = None

    async def start(self):
        self._task = asyncio.create_task(self._run())
        await asyncio.sleep(0.5)  # let WS connect

    async def _run(self):
        try:
            async with websockets.connect(WS_URL, ping_interval=None) as ws:
                self._ws = ws
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
        except Exception as e:
            pass  # WS disconnect is normal

    def get_events(self, event_type: str, call_id: int = None) -> list[dict]:
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

# ─── TEST CASES ────────────────────────────────────────────────────────────────

async def test_login(caller: ApiClient, callee: ApiClient):
    log("\n=== SETUP: Login ===")
    ok_c = await caller.login(PASSWORD)
    ok_e = await callee.login(PASSWORD)
    record("Login teqlif (caller)", ok_c)
    record("Login tesbih (callee)", ok_e)
    return ok_c and ok_e

async def test_normal_call_caller_ends(caller: ApiClient, callee: ApiClient,
                                        ws_caller: WsCapture, ws_callee: WsCapture):
    log("\n=== TC1: Normal call — caller ends ===")
    status, data = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC1: startCall 200", status == 200, f"status={status}")
    if status != 200:
        return

    call_id = data.get("call_id")
    log(f"  call_id={call_id}")

    await asyncio.sleep(0.5)
    db_s = await db_call_status(call_id)
    record("TC1: DB status=calling after start", db_s == "calling", f"db={db_s}")

    await asyncio.sleep(0.5)
    ws_events = ws_callee.get_events("call_incoming", call_id)
    record("TC1: callee WS received call_incoming", len(ws_events) > 0, f"count={len(ws_events)}")

    # caller cancels
    status2, _ = await caller.post(f"/calls/{call_id}/end")
    record("TC1: endCall 200", status2 == 200, f"status={status2}")

    await asyncio.sleep(0.5)
    db_s2 = await db_call_status(call_id)
    record("TC1: DB status=ended after end", db_s2 == "ended", f"db={db_s2}")

    ws_ended = ws_callee.get_events("call_ended", call_id)
    record("TC1: callee WS received call_ended", len(ws_ended) > 0, f"count={len(ws_ended)}")


async def test_callee_reject(caller: ApiClient, callee: ApiClient,
                              ws_caller: WsCapture, ws_callee: WsCapture):
    log("\n=== TC2: Callee rejects ===")
    status, data = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC2: startCall 200", status == 200, f"status={status}")
    if status != 200:
        return

    call_id = data.get("call_id")
    await asyncio.sleep(0.5)

    status2, _ = await callee.post(f"/calls/{call_id}/reject")
    record("TC2: rejectCall 200", status2 == 200, f"status={status2}")

    await asyncio.sleep(0.5)
    db_s = await db_call_status(call_id)
    record("TC2: DB status=rejected", db_s == "rejected", f"db={db_s}")

    ws_rejected = ws_caller.get_events("call_rejected", call_id)
    record("TC2: caller WS received call_rejected", len(ws_rejected) > 0, f"count={len(ws_rejected)}")


async def test_caller_busy_stale(caller: ApiClient, callee: ApiClient):
    log("\n=== TC3: CALLER_BUSY — stale calling auto-end ===")
    # First call — don't end it (simulate client crash)
    status1, data1 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC3: first startCall 200", status1 == 200, f"status={status1}")
    if status1 != 200:
        return

    call_id1 = data1.get("call_id")
    log(f"  call_id1={call_id1} (will NOT be ended — simulates crash)")

    await asyncio.sleep(0.3)

    # Immediately retry — should succeed (stale "calling" auto-ended by backend fix)
    status2, data2 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC3: second startCall succeeds (stale auto-end)", status2 == 200,
           f"status={status2} body={str(data2)[:150]}")

    if status2 == 200:
        call_id2 = data2.get("call_id")
        log(f"  call_id2={call_id2}")
        await asyncio.sleep(0.3)
        db_s1 = await db_call_status(call_id1)
        db_s2 = await db_call_status(call_id2)
        record("TC3: stale call1 auto-ended", db_s1 == "ended", f"db call1={db_s1}")
        record("TC3: new call2 is calling", db_s2 == "calling", f"db call2={db_s2}")
        # Clean up
        await caller.post(f"/calls/{call_id2}/end")
    else:
        # Still CALLER_BUSY — backend fix not in effect
        active = await db_active_calls_for_user(caller.user_id)
        record("TC3: no leftover active calls (cleanup)", len(active) == 0, f"active={active}")
        # Try to clean up stale
        await caller.post(f"/calls/{call_id1}/end")


async def test_double_end_idempotent(caller: ApiClient, callee: ApiClient):
    log("\n=== TC4: Double end — idempotent ===")
    status, data = await caller.post("/calls/start", {"callee_id": callee.user_id})
    if status != 200:
        record("TC4: startCall 200", False, f"status={status}")
        return

    call_id = data.get("call_id")
    await asyncio.sleep(0.3)

    s1, _ = await caller.post(f"/calls/{call_id}/end")
    s2, _ = await caller.post(f"/calls/{call_id}/end")
    record("TC4: first end 200", s1 == 200, f"status={s1}")
    record("TC4: second end 200 (idempotent)", s2 == 200, f"status={s2}")

    db_s = await db_call_status(call_id)
    record("TC4: DB still ended", db_s == "ended", f"db={db_s}")


async def test_reject_then_caller_retry(caller: ApiClient, callee: ApiClient):
    log("\n=== TC5: CallKit auto-reject then immediate caller retry ===")
    # Simulates: callee VoIP push → AppDelegate → CXEndCallAction → rejectCallById fires
    status1, data1 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC5: first startCall 200", status1 == 200, f"status={status1}")
    if status1 != 200:
        return

    call_id1 = data1.get("call_id")
    await asyncio.sleep(0.3)

    # Simulate callee's CallEventActionCallDecline → _rejectCallById
    rej_s, _ = await callee.post(f"/calls/{call_id1}/reject")
    record("TC5: callee reject 200", rej_s == 200, f"status={rej_s}")

    # Also simulate caller endCall (both fire in parallel in real app)
    end_s, _ = await caller.post(f"/calls/{call_id1}/end")
    record("TC5: caller end after reject 200 (idempotent)", end_s == 200, f"status={end_s}")

    await asyncio.sleep(0.3)
    db_s1 = await db_call_status(call_id1)
    record("TC5: call1 terminal state", db_s1 in ("rejected", "ended"), f"db={db_s1}")

    # Caller retries immediately
    status2, data2 = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC5: immediate retry succeeds", status2 == 200, f"status={status2} body={str(data2)[:100]}")

    if status2 == 200:
        call_id2 = data2.get("call_id")
        await caller.post(f"/calls/{call_id2}/end")


async def test_normal_call_accepted(caller: ApiClient, callee: ApiClient,
                                     ws_caller: WsCapture):
    log("\n=== TC6: Normal call — accept + end ===")
    status, data = await caller.post("/calls/start", {"callee_id": callee.user_id})
    record("TC6: startCall 200", status == 200, f"status={status}")
    if status != 200:
        return

    call_id = data.get("call_id")
    await asyncio.sleep(0.5)

    status2, _ = await callee.post(f"/calls/{call_id}/accept")
    record("TC6: acceptCall 200", status2 == 200, f"status={status2}")

    await asyncio.sleep(0.5)
    db_s = await db_call_status(call_id)
    record("TC6: DB status=active after accept", db_s == "active", f"db={db_s}")

    ws_accepted = ws_caller.get_events("call_accepted", call_id)
    record("TC6: caller WS received call_accepted", len(ws_accepted) > 0, f"count={len(ws_accepted)}")

    status3, _ = await caller.post(f"/calls/{call_id}/end")
    record("TC6: endCall after accept 200", status3 == 200, f"status={status3}")

    await asyncio.sleep(0.5)
    db_s2 = await db_call_status(call_id)
    record("TC6: DB status=ended after end", db_s2 == "ended", f"db={db_s2}")


async def test_status_endpoint(caller: ApiClient, callee: ApiClient):
    log("\n=== TC7: Status endpoint ===")
    status, data = await caller.post("/calls/start", {"callee_id": callee.user_id})
    if status != 200:
        record("TC7: startCall", False, f"status={status}")
        return

    call_id = data.get("call_id")
    s, d = await callee.get(f"/calls/{call_id}/status")
    record("TC7: GET /calls/{id}/status 200", s == 200, f"status={s}")
    record("TC7: status field=calling", d.get("status") == "calling", f"data={d}")

    await caller.post(f"/calls/{call_id}/end")
    s2, d2 = await callee.get(f"/calls/{call_id}/status")
    record("TC7: status after end=ended", d2.get("status") == "ended", f"data={d2}")


async def test_cleanup_stale_db(caller: ApiClient, callee: ApiClient):
    log("\n=== CLEANUP: Check for lingering active calls ===")
    active_caller = await db_active_calls_for_user(caller.user_id)
    active_callee = await db_active_calls_for_user(callee.user_id)
    record("CLEANUP: no stale calls for caller", len(active_caller) == 0,
           f"stale={active_caller}")
    record("CLEANUP: no stale calls for callee", len(active_callee) == 0,
           f"stale={active_callee}")

    # Force-end any strays
    for c in active_caller + active_callee:
        cid = c["id"]
        s, _ = await caller.post(f"/calls/{cid}/end")
        log(f"  Force-ended stale call_id={cid} status_before={c['status']} end_status={s}")

# ─── MAIN ──────────────────────────────────────────────────────────────────────

async def main():
    log("=" * 60)
    log("teqlif Call API Test Suite")
    log(f"Base URL: {BASE_URL}")
    log("=" * 60)

    caller = ApiClient(CALLER_USER)
    callee = ApiClient(CALLEE_USER)

    if not await test_login(caller, callee):
        log("\n[FATAL] Login failed — check credentials. Exiting.")
        sys.exit(1)

    # Start WS captures
    ws_caller = WsCapture(caller.token, CALLER_USER)
    ws_callee = WsCapture(callee.token, CALLEE_USER)
    await ws_caller.start()
    await ws_callee.start()

    try:
        await test_normal_call_caller_ends(caller, callee, ws_caller, ws_callee)
        await asyncio.sleep(1)

        await test_callee_reject(caller, callee, ws_caller, ws_callee)
        await asyncio.sleep(1)

        await test_caller_busy_stale(caller, callee)
        await asyncio.sleep(1)

        await test_double_end_idempotent(caller, callee)
        await asyncio.sleep(1)

        await test_reject_then_caller_retry(caller, callee)
        await asyncio.sleep(1)

        await test_normal_call_accepted(caller, callee, ws_caller)
        await asyncio.sleep(1)

        await test_status_endpoint(caller, callee)
        await asyncio.sleep(1)

        await test_cleanup_stale_db(caller, callee)

    finally:
        await ws_caller.stop()
        await ws_callee.stop()
        await caller.close()
        await callee.close()

    # ── Summary ────────────────────────────────────────────────────────────────
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
