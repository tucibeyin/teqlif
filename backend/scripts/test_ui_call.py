#!/usr/bin/env python3
"""
UI call test script.
Caller: tucibeyin (script-controlled)
Callees: teqlif (iOS), tesbih (Android)
Log format parsed: [UI_CALL][COMPONENT][ISO8601] EVENT | detail=value

Usage:
  python test_ui_call.py                         # interactive mode, human actions
  python test_ui_call.py --auto                  # script accepts/rejects via API
  python test_ui_call.py --tc FG1,FG2            # run specific TCs only
  python test_ui_call.py --callee tesbih         # target only one callee
  python test_ui_call.py --android-log /tmp/and.txt --ios-log /tmp/ios.txt
"""

import argparse
import json
import os
import sys
import time
import datetime
import subprocess
import threading
from pathlib import Path

import requests

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
BASE_URL = "http://localhost:8000"
CALL_WAIT_SECONDS = 6     # seconds to wait for UI to react before prompting
ACCEPT_DELAY = 2.0        # seconds after call rings before AUTO accept
END_DELAY = 4.0           # seconds of connected state before AUTO end

USERS = {
    "caller":   "tucibeyin",
    "ios":      "teqlif",
    "android":  "tesbih",
}

# Hardware device identifiers — fixed per physical device
ADB_SERIAL_DEFAULT  = "98522010325540"           # tesbih — Samsung S19 Max
IOS_UDID_DEFAULT    = "00008130-0016759C00FA8D3A" # tucibeyin's iPhone (teqlif)

# Populated at runtime
TOKENS: dict[str, str] = {}
CALL_IDS: dict[str, int | None] = {}

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
LOG_PATH = Path(__file__).parent / "test_ui_call_results.jsonl"

def ts() -> str:
    return datetime.datetime.now().isoformat(timespec="seconds")

def log(level: str, msg: str) -> None:
    print(f"[{ts()}][{level}] {msg}", flush=True)

def log_event(tc: str, event: str, detail: str = "") -> None:
    entry = {"tc": tc, "ts": ts(), "event": event, "detail": detail}
    with LOG_PATH.open("a") as f:
        f.write(json.dumps(entry) + "\n")
    log("EVENT", f"[{tc}] {event} | {detail}")

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------
def api(method: str, path: str, token: str | None = None, **kwargs) -> requests.Response:
    headers = kwargs.pop("headers", {})
    if token:
        headers["Authorization"] = f"Bearer {token}"
    resp = requests.request(method, f"{BASE_URL}{path}", headers=headers, timeout=10, **kwargs)
    return resp

def login(username: str, password: str) -> str:
    r = api("POST", "/auth/login", json={"username": username, "password": password})
    if r.status_code != 200:
        raise RuntimeError(f"Login failed for {username}: {r.status_code} {r.text}")
    return r.json()["access_token"]

def start_call(caller_token: str, callee_username: str) -> int:
    r = api("POST", "/calls/start", caller_token,
            json={"callee_username": callee_username})
    if r.status_code != 200:
        raise RuntimeError(f"start_call failed: {r.status_code} {r.text}")
    data = r.json()
    return data["call_id"]

def accept_call(callee_token: str, call_id: int) -> None:
    r = api("POST", f"/calls/{call_id}/accept", callee_token)
    if r.status_code not in (200, 204):
        raise RuntimeError(f"accept_call failed: {r.status_code} {r.text}")

def reject_call(callee_token: str, call_id: int) -> None:
    r = api("POST", f"/calls/{call_id}/reject", callee_token)
    if r.status_code not in (200, 204):
        raise RuntimeError(f"reject_call failed: {r.status_code} {r.text}")

def end_call(caller_token: str, call_id: int) -> None:
    r = api("POST", f"/calls/{call_id}/end", caller_token)
    if r.status_code not in (200, 204):
        raise RuntimeError(f"end_call failed: {r.status_code} {r.text}")

def get_call_status(token: str, call_id: int) -> str:
    r = api("GET", f"/calls/{call_id}", token)
    if r.status_code != 200:
        return "unknown"
    return r.json().get("status", "unknown")

# ---------------------------------------------------------------------------
# Terminal interaction helpers
# ---------------------------------------------------------------------------
def human_prompt(msg: str) -> None:
    """Print a bold terminal prompt and wait for Enter."""
    print(f"\n\033[1;33m[ACTION REQUIRED] {msg}\033[0m")
    input("  Press Enter when done > ")

def countdown(seconds: int, msg: str) -> None:
    for i in range(seconds, 0, -1):
        print(f"\r  {msg} ({i}s) ", end="", flush=True)
        time.sleep(1)
    print()

# ---------------------------------------------------------------------------
# Android logcat capture (background thread)
# ---------------------------------------------------------------------------
_android_log_lines: list[str] = []
_android_log_lock = threading.Lock()

def start_android_logcat(adb_device: str | None = None) -> threading.Thread | None:
    """Start capturing Android logs with [UI_CALL] filter in a background thread."""
    cmd = ["adb"]
    if adb_device:
        cmd += ["-s", adb_device]
    cmd += ["logcat", "-v", "time", "-s", "flutter:*"]

    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                text=True, bufsize=1)
    except FileNotFoundError:
        log("WARN", "adb not found — Android log capture disabled")
        return None

    def _reader():
        for line in proc.stdout:
            if "[UI_CALL]" in line:
                with _android_log_lock:
                    _android_log_lines.append(line.rstrip())

    t = threading.Thread(target=_reader, daemon=True)
    t.start()
    log("INFO", "Android logcat capture started")
    return t

def dump_android_log(tc: str) -> None:
    with _android_log_lock:
        lines = list(_android_log_lines)
        _android_log_lines.clear()
    if lines:
        log("INFO", f"[{tc}] Android UI_CALL lines:")
        for l in lines:
            print(f"  {l}")

# ---------------------------------------------------------------------------
# iOS log file parsing
# ---------------------------------------------------------------------------
def parse_ios_log(path: str, since: datetime.datetime) -> list[str]:
    """Return [UI_CALL] lines from an iOS log file written after `since`."""
    lines = []
    try:
        with open(path) as f:
            for line in f:
                if "[UI_CALL]" not in line:
                    continue
                # Try to extract timestamp from the line itself
                lines.append(line.rstrip())
    except FileNotFoundError:
        pass
    return lines

def dump_ios_log(tc: str, path: str, since: datetime.datetime) -> None:
    lines = parse_ios_log(path, since)
    if lines:
        log("INFO", f"[{tc}] iOS UI_CALL lines:")
        for l in lines:
            print(f"  {l}")

# ---------------------------------------------------------------------------
# Test case runner
# ---------------------------------------------------------------------------
class TestCase:
    def __init__(self, tc_id: str, desc: str, callee: str, mode: str,
                 steps: list[dict]):
        self.tc_id = tc_id
        self.desc = desc
        self.callee = callee   # "ios" | "android"
        self.mode = mode       # "auto" | "human"
        self.steps = steps
        self.passed: bool | None = None
        self.notes: list[str] = []

    def run(self, args: argparse.Namespace, ios_log_path: str | None,
            android_active: bool) -> None:
        tc = self.tc_id
        log("TC", f"--- {tc}: {self.desc} ---")
        log_event(tc, "TC_START", f"callee={self.callee} mode={self.mode}")

        caller_token = TOKENS["caller"]
        callee_token = TOKENS[self.callee]
        callee_username = USERS[self.callee]

        tc_start = datetime.datetime.now()
        call_id: int | None = None

        for step in self.steps:
            action = step["action"]
            detail = step.get("detail", "")
            wait  = step.get("wait", 0)

            if action == "human_setup":
                human_prompt(detail)

            elif action == "start_call":
                call_id = start_call(caller_token, callee_username)
                CALL_IDS[tc] = call_id
                log_event(tc, "CALL_STARTED", f"call_id={call_id} callee={callee_username}")
                if wait:
                    countdown(wait, "Waiting for ring UI")

            elif action == "auto_accept":
                if call_id is None:
                    log("ERROR", "auto_accept: no call_id"); return
                countdown(int(ACCEPT_DELAY), "Auto-accepting")
                accept_call(callee_token, call_id)
                log_event(tc, "API_ACCEPT", f"call_id={call_id}")
                if wait:
                    countdown(wait, "Waiting for CONNECTED UI")

            elif action == "human_accept":
                human_prompt(detail or f"TAP ACCEPT on {self.callee.upper()} device")
                log_event(tc, "HUMAN_ACCEPT_DONE", "")
                if wait:
                    countdown(wait, "Waiting for CONNECTED UI")

            elif action == "auto_reject":
                if call_id is None:
                    log("ERROR", "auto_reject: no call_id"); return
                countdown(int(ACCEPT_DELAY), "Auto-rejecting")
                reject_call(callee_token, call_id)
                log_event(tc, "API_REJECT", f"call_id={call_id}")

            elif action == "human_reject":
                human_prompt(detail or f"TAP DECLINE on {self.callee.upper()} device")
                log_event(tc, "HUMAN_REJECT_DONE", "")

            elif action == "auto_end":
                if call_id is None:
                    log("ERROR", "auto_end: no call_id"); return
                countdown(int(END_DELAY), "Auto-ending call")
                end_call(caller_token, call_id)
                log_event(tc, "API_END", f"call_id={call_id}")

            elif action == "human_end":
                human_prompt(detail or "TAP END CALL on device or script presses end")
                log_event(tc, "HUMAN_END_DONE", "")

            elif action == "human_bg":
                human_prompt(detail or f"PUT {self.callee.upper()} app into BACKGROUND (home button)")
                log_event(tc, "HUMAN_BG", "")

            elif action == "human_fg":
                human_prompt(detail or f"BRING {self.callee.upper()} app back to FOREGROUND")
                log_event(tc, "HUMAN_FG", "")

            elif action == "human_lock":
                human_prompt(detail or f"LOCK the {self.callee.upper()} device screen")
                log_event(tc, "HUMAN_LOCK", "")

            elif action == "human_unlock":
                human_prompt(detail or f"UNLOCK the {self.callee.upper()} device screen")
                log_event(tc, "HUMAN_UNLOCK", "")

            elif action == "human_minimize":
                human_prompt(detail or f"TAP MINIMIZE (chevron-down) on {self.callee.upper()} device")
                log_event(tc, "HUMAN_MINIMIZE", "")

            elif action == "wait":
                countdown(wait or 3, detail or "Waiting")

            elif action == "check_status":
                if call_id:
                    status = get_call_status(caller_token, call_id)
                    log_event(tc, "STATUS_CHECK", f"call_id={call_id} status={status}")

            elif action == "collect_logs":
                if android_active and self.callee == "android":
                    dump_android_log(tc)
                if ios_log_path and self.callee == "ios":
                    dump_ios_log(tc, ios_log_path, tc_start)

            elif action == "verify_human":
                result = input(f"  [VERIFY] {detail} (y/n/skip) > ").strip().lower()
                passed = result in ("y", "yes")
                log_event(tc, "VERIFY", f"question={detail} result={result}")
                if not passed and result not in ("skip", "s"):
                    self.passed = False
                    self.notes.append(f"FAIL: {detail}")

        # Final log collect
        if android_active and self.callee == "android":
            dump_android_log(tc)
        if ios_log_path and self.callee == "ios":
            dump_ios_log(tc, ios_log_path, tc_start)

        if self.passed is None:
            self.passed = True
        log_event(tc, "TC_END", f"passed={self.passed} notes={self.notes}")
        log("TC", f"{'PASS' if self.passed else 'FAIL'}: {tc}")

# ---------------------------------------------------------------------------
# Test case definitions
# ---------------------------------------------------------------------------
def build_test_cases(auto: bool) -> list[TestCase]:
    a = "auto" if auto else "human"

    cases: list[TestCase] = [
        # ------------------------------------------------------------------
        # FG — Foreground tests (callee app is open and in foreground)
        # ------------------------------------------------------------------
        TestCase("FG1", "Caller calls iOS (FG), callee accepts", "ios", a, [
            {"action": "human_setup",   "detail": "Ensure teqlif (iOS) app is OPEN and in FOREGROUND"},
            {"action": "start_call",    "wait": CALL_WAIT_SECONDS},
            {"action": "verify_human",  "detail": "Did INCOMING_BAR appear on iOS?"},
            {"action": "auto_accept" if auto else "human_accept", "wait": CALL_WAIT_SECONDS},
            {"action": "verify_human",  "detail": "Did CALL_SCREEN show CONNECTED state on iOS?"},
            {"action": "auto_end",      "wait": 3},
            {"action": "verify_human",  "detail": "Did CALL_SCREEN dismiss on iOS after end?"},
            {"action": "collect_logs"},
        ]),

        TestCase("FG2", "Caller calls Android (FG), callee accepts", "android", a, [
            {"action": "human_setup",   "detail": "Ensure tesbih (Android) app is OPEN and in FOREGROUND"},
            {"action": "start_call",    "wait": CALL_WAIT_SECONDS},
            {"action": "verify_human",  "detail": "Did INCOMING_BAR appear on Android?"},
            {"action": "auto_accept" if auto else "human_accept", "wait": CALL_WAIT_SECONDS},
            {"action": "verify_human",  "detail": "Did CALL_SCREEN show CONNECTED state on Android?"},
            {"action": "auto_end",      "wait": 3},
            {"action": "verify_human",  "detail": "Did CALL_SCREEN dismiss on Android after end?"},
            {"action": "collect_logs"},
        ]),

        TestCase("FG3", "Caller calls iOS (FG), callee declines", "ios", a, [
            {"action": "human_setup",   "detail": "Ensure teqlif (iOS) app is OPEN and in FOREGROUND"},
            {"action": "start_call",    "wait": CALL_WAIT_SECONDS},
            {"action": "auto_reject" if auto else "human_reject"},
            {"action": "wait",          "wait": 3},
            {"action": "verify_human",  "detail": "Did INCOMING_BAR disappear on iOS after decline?"},
            {"action": "collect_logs"},
        ]),

        TestCase("FG4", "Caller calls Android (FG), callee declines", "android", a, [
            {"action": "human_setup",   "detail": "Ensure tesbih (Android) app is OPEN and in FOREGROUND"},
            {"action": "start_call",    "wait": CALL_WAIT_SECONDS},
            {"action": "auto_reject" if auto else "human_reject"},
            {"action": "wait",          "wait": 3},
            {"action": "verify_human",  "detail": "Did INCOMING_BAR disappear on Android after decline?"},
            {"action": "collect_logs"},
        ]),

        # ------------------------------------------------------------------
        # BG — Background tests (callee app is open but backgrounded)
        # ------------------------------------------------------------------
        TestCase("BG1", "Caller calls iOS (BG), callee brings FG and accepts", "ios", a, [
            {"action": "human_setup",   "detail": "Ensure teqlif (iOS) is running but in BACKGROUND"},
            {"action": "start_call",    "wait": CALL_WAIT_SECONDS},
            {"action": "verify_human",  "detail": "Did system notification appear on iOS?"},
            {"action": "human_fg",      "detail": "Open teqlif app from notification (bring to FG)"},
            {"action": "verify_human",  "detail": "Did INCOMING_BAR or INCOMING_SCREEN appear on iOS?"},
            {"action": "auto_accept" if auto else "human_accept", "wait": CALL_WAIT_SECONDS},
            {"action": "verify_human",  "detail": "Did CALL_SCREEN show CONNECTED?"},
            {"action": "auto_end",      "wait": 3},
            {"action": "collect_logs"},
        ]),

        TestCase("BG2", "Caller calls Android (BG), callee brings FG and accepts", "android", a, [
            {"action": "human_setup",   "detail": "Ensure tesbih (Android) is running but in BACKGROUND"},
            {"action": "start_call",    "wait": CALL_WAIT_SECONDS},
            {"action": "verify_human",  "detail": "Did system notification appear on Android?"},
            {"action": "human_fg",      "detail": "Open tesbih app from notification (bring to FG)"},
            {"action": "verify_human",  "detail": "Did INCOMING_BAR or INCOMING_SCREEN appear on Android?"},
            {"action": "auto_accept" if auto else "human_accept", "wait": CALL_WAIT_SECONDS},
            {"action": "verify_human",  "detail": "Did CALL_SCREEN show CONNECTED?"},
            {"action": "auto_end",      "wait": 3},
            {"action": "collect_logs"},
        ]),

        # ------------------------------------------------------------------
        # ACT — Active call bar and pill tests
        # ------------------------------------------------------------------
        TestCase("ACT1", "Connected iOS call: minimize to pill, tap pill to restore", "ios", a, [
            {"action": "human_setup",   "detail": "Ensure teqlif (iOS) app is OPEN and in FOREGROUND"},
            {"action": "start_call",    "wait": CALL_WAIT_SECONDS},
            {"action": "auto_accept" if auto else "human_accept", "wait": CALL_WAIT_SECONDS},
            {"action": "human_minimize","detail": "TAP MINIMIZE (chevron-down) on iOS CALL_SCREEN"},
            {"action": "wait",          "wait": 2},
            {"action": "verify_human",  "detail": "Did the green pill appear at the top of the iOS screen?"},
            {"action": "human_prompt" if True else "", "detail": "TAP the green pill on iOS to return to call screen"},
            {"action": "wait",          "wait": 2},
            {"action": "verify_human",  "detail": "Did CALL_SCREEN reopen on iOS?"},
            {"action": "auto_end",      "wait": 3},
            {"action": "collect_logs"},
        ]),

        TestCase("ACT2", "Connected Android call: minimize to pill, end from pill", "android", a, [
            {"action": "human_setup",   "detail": "Ensure tesbih (Android) app is OPEN and in FOREGROUND"},
            {"action": "start_call",    "wait": CALL_WAIT_SECONDS},
            {"action": "auto_accept" if auto else "human_accept", "wait": CALL_WAIT_SECONDS},
            {"action": "human_minimize","detail": "TAP MINIMIZE (chevron-down) on Android CALL_SCREEN"},
            {"action": "wait",          "wait": 2},
            {"action": "verify_human",  "detail": "Did the green pill appear on Android?"},
            {"action": "human_end",     "detail": "TAP the red END button on the green pill on Android"},
            {"action": "wait",          "wait": 3},
            {"action": "verify_human",  "detail": "Did the pill disappear after ending from pill?"},
            {"action": "collect_logs"},
        ]),

        TestCase("ACT3", "iOS connected, background app → ACTIVE_BAR visible", "ios", a, [
            {"action": "human_setup",   "detail": "Ensure teqlif (iOS) app is OPEN and in FOREGROUND"},
            {"action": "start_call",    "wait": CALL_WAIT_SECONDS},
            {"action": "auto_accept" if auto else "human_accept", "wait": CALL_WAIT_SECONDS},
            {"action": "verify_human",  "detail": "Is CALL_SCREEN showing CONNECTED on iOS?"},
            {"action": "human_bg",      "detail": "Put teqlif (iOS) into BACKGROUND (home swipe up)"},
            {"action": "wait",          "wait": 2},
            {"action": "human_fg",      "detail": "Bring teqlif (iOS) back to FOREGROUND"},
            {"action": "verify_human",  "detail": "Did ACTIVE_BAR appear at the top while in another screen? (or call screen restored?)"},
            {"action": "auto_end",      "wait": 3},
            {"action": "collect_logs"},
        ]),

        # ------------------------------------------------------------------
        # LIFE — Call lifecycle edge cases
        # ------------------------------------------------------------------
        TestCase("LIFE1", "Caller calls iOS, no answer (timeout)", "ios", "human", [
            {"action": "human_setup",   "detail": "Ensure teqlif (iOS) app is OPEN — do NOT accept"},
            {"action": "start_call",    "wait": 35},
            {"action": "check_status"},
            {"action": "verify_human",  "detail": "Did INCOMING_BAR disappear after timeout on iOS?"},
            {"action": "collect_logs"},
        ]),

        TestCase("LIFE2", "Caller cancels call before callee answers (iOS)", "ios", a, [
            {"action": "human_setup",   "detail": "Ensure teqlif (iOS) app is OPEN and in FOREGROUND"},
            {"action": "start_call",    "wait": 3},
            {"action": "auto_end",      "wait": 3, "detail": "Caller cancels"},
            {"action": "verify_human",  "detail": "Did INCOMING_BAR disappear on iOS after caller cancel?"},
            {"action": "collect_logs"},
        ]),

        TestCase("LIFE3", "Caller cancels call before callee answers (Android)", "android", a, [
            {"action": "human_setup",   "detail": "Ensure tesbih (Android) app is OPEN and in FOREGROUND"},
            {"action": "start_call",    "wait": 3},
            {"action": "auto_end",      "wait": 3, "detail": "Caller cancels"},
            {"action": "verify_human",  "detail": "Did INCOMING_BAR disappear on Android after caller cancel?"},
            {"action": "collect_logs"},
        ]),

        # ------------------------------------------------------------------
        # LOCK — Lock screen tests
        # ------------------------------------------------------------------
        TestCase("LOCK1", "Call arrives on locked iOS device", "ios", "human", [
            {"action": "human_setup",   "detail": "LOCK the teqlif (iOS) device screen now"},
            {"action": "start_call",    "wait": CALL_WAIT_SECONDS},
            {"action": "verify_human",  "detail": "Did lock screen notification appear on iOS?"},
            {"action": "human_unlock",  "detail": "UNLOCK the iOS device and open teqlif"},
            {"action": "verify_human",  "detail": "Did INCOMING_BAR or INCOMING_SCREEN appear after unlock?"},
            {"action": "auto_accept" if auto else "human_accept", "wait": CALL_WAIT_SECONDS},
            {"action": "verify_human",  "detail": "Did CALL_SCREEN reach CONNECTED state?"},
            {"action": "auto_end",      "wait": 3},
            {"action": "collect_logs"},
        ]),

        TestCase("LOCK2", "Call arrives on locked Android device", "android", "human", [
            {"action": "human_setup",   "detail": "LOCK the tesbih (Android) device screen now"},
            {"action": "start_call",    "wait": CALL_WAIT_SECONDS},
            {"action": "verify_human",  "detail": "Did lock screen notification appear on Android?"},
            {"action": "human_unlock",  "detail": "UNLOCK the Android device and open tesbih"},
            {"action": "verify_human",  "detail": "Did INCOMING_BAR or INCOMING_SCREEN appear after unlock?"},
            {"action": "auto_accept" if auto else "human_accept", "wait": CALL_WAIT_SECONDS},
            {"action": "verify_human",  "detail": "Did CALL_SCREEN reach CONNECTED state?"},
            {"action": "auto_end",      "wait": 3},
            {"action": "collect_logs"},
        ]),
    ]
    return cases

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    parser = argparse.ArgumentParser(description="UI call test runner")
    parser.add_argument("--auto",        action="store_true",  help="AUTO mode: script accepts/rejects via API")
    parser.add_argument("--tc",          type=str, default="",  help="Comma-separated TC IDs to run (e.g. FG1,BG2)")
    parser.add_argument("--callee",      type=str, default="",  help="ios | android (run only that callee's TCs)")
    parser.add_argument("--android-log", type=str, default="",  help="Path to file for Android adb logcat output (if pre-captured)")
    parser.add_argument("--ios-log",     type=str, default="",  help="Path to iOS Xcode console log file")
    parser.add_argument("--adb-device",  type=str, default="",  help="ADB device serial for targeted logcat")
    args = parser.parse_args()

    print("=" * 60)
    print("  Teqlif UI Call Test Suite")
    print(f"  Mode: {'AUTO' if args.auto else 'HUMAN'}")
    print(f"  Time: {ts()}")
    print("=" * 60)

    # --- Device selection (interactive if not passed via --callee) ---
    callee_filter = args.callee.lower() if args.callee else ""
    if not callee_filter:
        print()
        print("  Hangi cihazda test yapacaksın?")
        print("  [1] iOS   (teqlif)")
        print("  [2] Android (tesbih)")
        print("  [3] Her ikisi")
        choice = input("  Seçim (1/2/3): ").strip()
        callee_filter = {"1": "ios", "2": "android", "3": ""}.get(choice, "")
        if choice not in ("1", "2", "3"):
            log("ERROR", f"Geçersiz seçim: {choice}")
            sys.exit(1)

    # --- Android device serial (hardcoded default, can be overridden) ---
    adb_device = args.adb_device or ADB_SERIAL_DEFAULT

    # --- iOS log path (optional, pass via --ios-log) ---
    ios_log = args.ios_log or None

    print()

    # --- Credentials ---
    caller_pass  = input(f"Password for {USERS['caller']}: ")
    ios_pass     = input(f"Password for {USERS['ios']}:    ") if callee_filter in ("ios", "") else ""
    android_pass = input(f"Password for {USERS['android']}:  ") if callee_filter in ("android", "") else ""

    log("AUTH", "Logging in...")
    TOKENS["caller"]  = login(USERS["caller"],  caller_pass)
    if ios_pass:
        TOKENS["ios"]     = login(USERS["ios"],     ios_pass)
    if android_pass:
        TOKENS["android"] = login(USERS["android"], android_pass)
    log("AUTH", "All tokens acquired")

    # Start adb capture
    android_thread = start_android_logcat(adb_device or None)
    android_active = android_thread is not None

    # Build and filter test cases
    all_cases = build_test_cases(args.auto)

    if args.tc:
        wanted = {x.strip().upper() for x in args.tc.split(",")}
        all_cases = [c for c in all_cases if c.tc_id in wanted]
    if callee_filter:
        all_cases = [c for c in all_cases if c.callee == callee_filter]

    if not all_cases:
        log("ERROR", "No test cases matched the given filters")
        sys.exit(1)

    log("INFO", f"Running {len(all_cases)} test case(s)")
    results: list[dict] = []

    for tc in all_cases:
        print()
        try:
            tc.run(args, ios_log, android_active)
        except KeyboardInterrupt:
            log("WARN", f"TC {tc.tc_id} interrupted by user")
            tc.passed = False
            tc.notes.append("interrupted")
        except Exception as e:
            log("ERROR", f"TC {tc.tc_id} exception: {e}")
            tc.passed = False
            tc.notes.append(str(e))
        results.append({"tc": tc.tc_id, "passed": tc.passed, "notes": tc.notes})

    # Summary
    print()
    print("=" * 60)
    print("  RESULTS SUMMARY")
    print("=" * 60)
    passed = sum(1 for r in results if r["passed"])
    for r in results:
        status = "PASS" if r["passed"] else "FAIL"
        color  = "\033[32m" if r["passed"] else "\033[31m"
        print(f"  {color}{status}\033[0m  {r['tc']}  {r['notes'] or ''}")
    print()
    print(f"  {passed}/{len(results)} passed")
    print(f"  Full log: {LOG_PATH}")
    print("=" * 60)


if __name__ == "__main__":
    main()
