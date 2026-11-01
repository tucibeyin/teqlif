"""KVKK/GDPR uyumluluğu için IP adresi maskeleme ve tespit yardımcıları."""

import ipaddress
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import Request


def get_client_ip(request: "Request") -> str:
    """Gerçek istemci IP'sini döner (proxy zincirine güvenli).

    Öncelik: CF-Connecting-IP → X-Real-IP → X-Forwarded-For → ASGI host.
    CF-Connecting-IP: Cloudflare Proxied modunda tek güvenilir kaynak.
    X-Real-IP: Nginx'in $remote_addr/$http_cf_connecting_ip ile set ettiği header.
    """
    cf_ip = request.headers.get("cf-connecting-ip")
    if cf_ip:
        return cf_ip.strip()
    real_ip = request.headers.get("x-real-ip")
    if real_ip:
        return real_ip.strip()
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else "0.0.0.0"


def mask_ip(ip: str | None) -> str | None:
    """IPv4'ü /24 (x.x.x.0), IPv6'yı /64 alt ağ adresine maskeler.

    SRE-114: IPv6 için None yerine /64 ağ adresi dönerek
    shill bidding korumasının by-pass edilmesini engeller.
    """
    if not ip:
        return None
    try:
        addr = ipaddress.ip_address(ip)
        if addr.version == 4:
            return str(ipaddress.ip_network(f"{ip}/24", strict=False).network_address)
        return str(ipaddress.ip_network(f"{ip}/64", strict=False).network_address)
    except ValueError:
        return None
