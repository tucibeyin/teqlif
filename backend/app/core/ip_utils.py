"""KVKK/GDPR uyumluluğu için IP adresi maskeleme yardımcısı."""


def mask_ip(ip: str | None) -> str | None:
    """IPv4 son oktetini sıfırlar (x.x.x.0). IPv6 saklanmaz (None döner)."""
    if not ip:
        return None
    parts = ip.split(".")
    if len(parts) == 4:
        return f"{parts[0]}.{parts[1]}.{parts[2]}.0"
    return None  # IPv6 saklanmıyor
