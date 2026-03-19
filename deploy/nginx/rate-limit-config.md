# Nginx Rate Limiting - Kurulum

## Adım 1: nginx.conf'u düzenleyin

```bash
sudo nano /etc/nginx/nginx.conf
```

http { bölümüne şunları ekleyin:

```nginx
http {
    # ... mevcut ayarlar ...
    
    # Rate limiting - ekleyin
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=auth_limit:10m rate=5r/m;
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
}
```

## Adım 2: teqlif config'i güncelleyin

```bash
sudo nano /etc/nginx/sites-available/teqlif
```

location /api/ bölümlerine limit_req ekleyin:

```nginx
location /api/auth {
    limit_req zone=auth_limit burst=5 nodelay;
    limit_conn conn_limit 3;
    proxy_pass http://127.0.0.1:8000;
    ...
}

location /api/ {
    limit_req zone=api_limit burst=10 nodelay;
    proxy_pass http://127.0.0.1:8000;
    ...
}
```

## Adım 3: Test ve yeniden başlat

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## Test

```bash
# Rate limit test
for i in {1..15}; do curl -I https://teqlif.com/api/categories & done
```
