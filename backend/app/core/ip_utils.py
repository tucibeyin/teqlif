"""KVKK/GDPR uyumluluğu için IP adresi maskeleme yardımcısı."""

import ipaddress


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
