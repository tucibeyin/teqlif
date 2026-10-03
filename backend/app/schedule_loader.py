"""
Merkezi zamanlama konfigürasyonunu okur.

deploy/scale/V2.1/schedule.yaml — tek kaynak.
worker.py: build_cron_jobs() ile ARQ cron listesi oluşturur.
teqlif-agent/watchdog.py: load_watchdog_registry() ile interval'ları okur.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml
from arq import cron

# backend/app/ → teqlif/ → deploy/scale/V2.1/schedule.yaml
_SCHEDULE_PATH = Path(__file__).parents[2] / "deploy" / "scale" / "V2.1" / "schedule.yaml"


def _load() -> dict[str, Any]:
    with open(_SCHEDULE_PATH) as f:
        return yaml.safe_load(f)


def build_cron_jobs(task_functions: dict) -> list:
    """
    schedule.yaml'daki batch bölümünden ARQ cron job listesi oluşturur.

    task_functions: {job_name: callable} — worker.py'deki tüm batch fonksiyonları.
    Bilinmeyen isimler (task_functions'da yoksa) sessizce atlanır.
    """
    cfg = _load()
    jobs = []
    for entry in cfg.get("batch", []):
        name = entry["name"]
        fn = task_functions.get(name)
        if fn is None:
            continue
        kwargs: dict[str, Any] = {}
        for key in ("hour", "minute", "weekday", "day"):
            if key not in entry:
                continue
            val = entry[key]
            kwargs[key] = set(val) if isinstance(val, list) else val
        jobs.append(cron(fn, **kwargs))
    return jobs


def load_watchdog_registry() -> dict[str, int]:
    """
    Tüm batch ve backup job'ların beklenen interval'larını döner.
    {job_name: dakika} — watchdog._JOB_REGISTRY için.
    """
    cfg = _load()
    registry: dict[str, int] = {}
    for entry in cfg.get("batch", []):
        if "watchdog_m" in entry:
            registry[entry["name"]] = int(entry["watchdog_m"])
    for entry in cfg.get("backup", []):
        if "watchdog_m" in entry:
            registry[entry["name"]] = int(entry["watchdog_m"])
    return registry


def get_ttl(key: str, default: int = 0) -> int:
    """schedule.yaml ttl bölümünden bir değer okur."""
    cfg = _load()
    return int(cfg.get("ttl", {}).get(key, default))
