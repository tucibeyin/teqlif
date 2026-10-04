"""teqlif-agent — Node kimliği ve yapılandırma."""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

# cluster.yaml her cycle'da yeniden okunur — modül seviyesinde cache'lenmez.
_CLUSTER_YAML_PATH = (
    Path(__file__).parent / "cluster.yaml"          # prod: /opt/teqlif-agent/cluster.yaml
    if (Path(__file__).parent / "cluster.yaml").exists()
    else Path(__file__).parent.parent / "cluster.yaml"  # dev: deploy/scale/V2.1/cluster.yaml
)


def load_cluster_config() -> dict[str, Any]:
    """cluster.yaml'ı okur. Her çağrıda taze veri döner (hot-reload)."""
    try:
        with _CLUSTER_YAML_PATH.open() as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


@dataclass
class PeerConfig:
    node_id: str
    priority: int      # küçük = daha öncelikli (nodeMonitor=1)
    wg_ip:   str


@dataclass
class AgentConfig:
    node_id:        str
    priority:       int
    wg_ip:          str
    gossip_port:    int
    gossip_token:   str
    peers:          list[PeerConfig]

    db_path:        Path
    log_level:      str

    # Telegram
    telegram_bot_token: str
    telegram_chat_id:   str

    # Redis (job sinyalleri için)
    redis_url:      str

    # Cycle
    cycle_interval: int   # saniye — ana döngü aralığı
    gossip_timeout: int   # saniye — peer HTTP timeout

    # Port izleme: bu node'da hangi servisler çalışıyor (boş = hepsini kontrol et)
    monitor_services: list[str] = field(default_factory=list)

    @property
    def all_nodes(self) -> list[PeerConfig]:
        """Kendi dahil tüm node'lar."""
        me = PeerConfig(node_id=self.node_id, priority=self.priority, wg_ip=self.wg_ip)
        return sorted([me, *self.peers], key=lambda p: p.priority)

    @property
    def higher_priority_peers(self) -> list[PeerConfig]:
        return [p for p in self.peers if p.priority < self.priority]

    def recording_config_for(self, service_name: str) -> dict[str, Any] | None:
        """Verilen servis adı için cluster.yaml'dan recording config döner."""
        cluster = load_cluster_config()
        return (
            cluster
            .get("recording", {})
            .get("services", {})
            .get(service_name)
        )

    @property
    def cluster_recording(self) -> dict[str, Any]:
        """cluster.yaml'daki recording bölümünü döner (servis config'leri hariç)."""
        cluster = load_cluster_config()
        rec = dict(cluster.get("recording", {}))
        rec.pop("services", None)
        return rec


def load_config(path: str | None = None) -> AgentConfig:
    cfg_path = Path(path or os.getenv("AGENT_CONFIG", "/etc/teqlif-agent/config.yaml"))
    with cfg_path.open() as f:
        raw = yaml.safe_load(f)

    peers = [
        PeerConfig(
            node_id=p["id"],
            priority=p["priority"],
            wg_ip=p["wg_ip"],
        )
        for p in raw.get("peers", [])
        if p["id"] != raw["node_id"]
    ]

    return AgentConfig(
        node_id      = raw["node_id"],
        priority     = raw["priority"],
        wg_ip        = raw["wg_ip"],
        gossip_port  = raw.get("gossip_port", 19100),
        gossip_token = raw["gossip_token"],
        peers        = peers,
        db_path      = Path(raw.get("db_path", "/var/lib/teqlif-agent/state.db")),
        log_level    = raw.get("log_level", "INFO"),
        telegram_bot_token = raw.get("telegram_bot_token", ""),
        telegram_chat_id   = raw.get("telegram_chat_id", ""),
        redis_url    = raw.get("redis_url", "redis://127.0.0.1:6379/0"),
        cycle_interval  = raw.get("cycle_interval", 60),
        gossip_timeout  = raw.get("gossip_timeout", 5),
        monitor_services = raw.get("monitor_services", []),
    )
