#!/usr/bin/env python3
"""
crowdsec-cf-sync — CrowdSec ban decisions → Cloudflare IP list sync

Cloudflare Firewall Rules API deprecated (error 10020) olduğu için
crowdsec-cloudflare-bouncer v0.3.0 çalışmıyor. Bu script bouncer'ın
yapması gereken tek işi doğrudan yapar:
  1. CrowdSec'ten aktif ban kararlarını al  (cscli decisions list)
  2. Cloudflare'daki crowdsec_block IP listesini diff ile güncelle

Çalışma şekli:
  - systemd timer (crowdsec-cf-sync.timer) tarafından 60s'de bir tetiklenir
  - Type=oneshot: çalışır, biter, journal'a yazar
  - Başarılı sync sonunda opsiyonel Uptime Kuma heartbeat gönderir

Gerekli izinler (token):
  - Account Filter Lists: Edit   (IP listesi okuma/yazma)

Credentials kaynağı:
  /etc/crowdsec/bouncers/crowdsec-cloudflare-bouncer.yaml
  (apply_secrets tarafından doldurulur)
"""

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

BOUNCER_CFG   = '/etc/crowdsec/bouncers/crowdsec-cloudflare-bouncer.yaml'
CF_API        = 'https://api.cloudflare.com/client/v4'
IP_LIST_NAME  = 'crowdsec_block'
CSCLI         = '/usr/bin/cscli'


def _creds():
    txt = open(BOUNCER_CFG).read()
    # "    - id: <hex>" veya "      id: <hex>" formatlarını destekle
    m_id = re.search(r'[-\s]+id:\s+([a-f0-9]{20,})', txt, re.M)
    if not m_id:
        raise RuntimeError(f'account id bulunamadı: {BOUNCER_CFG}')
    account_id = m_id.group(1)
    # Token single/double quote veya bare olabilir
    m_tok = re.search(r"^\s+token:\s+['\"]?([^\s'\"]+)['\"]?", txt, re.M)
    if not m_tok:
        raise RuntimeError(f'token bulunamadı: {BOUNCER_CFG}')
    token = m_tok.group(1)
    return account_id, token


def _api(method, path, body=None, *, token):
    req = urllib.request.Request(
        CF_API + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={
            'Authorization': f'Bearer {token}',
            'Content-Type':  'application/json',
        },
    )
    try:
        return json.loads(urllib.request.urlopen(req, timeout=15).read())
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f'CF API {exc.code}: {exc.read().decode()[:300]}') from exc


def _list_id(account_id, token):
    r = _api('GET', f'/accounts/{account_id}/rules/lists', token=token)
    for lst in r.get('result') or []:
        if lst['name'] == IP_LIST_NAME:
            return lst['id']
    raise RuntimeError(f"IP list '{IP_LIST_NAME}' bulunamadı — bouncer henüz çalışmadı mı?")


def _list_items(account_id, list_id, token):
    """Mevcut listedeki tüm item'ları {ip: id} olarak döndürür (paginated)."""
    items, cursor = {}, None
    while True:
        path = f'/accounts/{account_id}/rules/lists/{list_id}/items'
        if cursor:
            path += f'?cursor={cursor}'
        r = _api('GET', path, token=token)
        for item in r.get('result') or []:
            items[item['ip']] = item['id']
        cursor = ((r.get('result_info') or {}).get('cursors') or {}).get('after')
        if not cursor:
            break
    return items


def _ban_ips():
    """CrowdSec'teki aktif ban kararlarından IP/CIDR kümesi döndürür."""
    r = subprocess.run(
        [CSCLI, 'decisions', 'list', '--type', 'ban', '-o', 'json'],
        capture_output=True, text=True, timeout=15,
    )
    if r.returncode != 0:
        raise RuntimeError(f'cscli başarısız: {r.stderr.strip()[:200]}')
    decisions = json.loads(r.stdout or 'null') or []
    return {d['value'] for d in decisions if d.get('value')}


def _heartbeat(url):
    if not url:
        return
    try:
        urllib.request.urlopen(url, timeout=5)
    except Exception:
        pass  # heartbeat opsiyonel — başarısız olsa bile sync OK


def main():
    account_id, token = _creds()
    list_id = _list_id(account_id, token)

    want = _ban_ips()
    have = _list_items(account_id, list_id, token)

    to_add = want - have.keys()
    to_rem = have.keys() - want

    if to_add:
        _api('POST',
             f'/accounts/{account_id}/rules/lists/{list_id}/items',
             [{'ip': ip} for ip in sorted(to_add)],
             token=token)

    if to_rem:
        _api('DELETE',
             f'/accounts/{account_id}/rules/lists/{list_id}/items',
             {'items': [{'id': have[ip]} for ip in sorted(to_rem)]},
             token=token)

    print(f'+{len(to_add)} -{len(to_rem)} total={len(want)}')
    _heartbeat(os.environ.get('HEARTBEAT_URL', ''))


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
