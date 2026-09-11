# /etc/nginx/sites-available/uploads-staging.teqlif.com — node3
# Scale V1.3: uploads-staging.teqlif.com DNS only → node3 5.249.165.10 direkt
# CF bypass — büyük dosya transferleri için

server {
    listen 80;
    server_name uploads-staging.teqlif.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name uploads-staging.teqlif.com;

    ssl_certificate /etc/letsencrypt/live/uploads-staging.teqlif.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/uploads-staging.teqlif.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL_UPLOADS_STAGING:5m;

    server_tokens off;
    client_max_body_size 100M;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options "nosniff" always;

    # MinIO — teqlif-staging bucket
    location / {
        proxy_pass http://127.0.0.1:9010/teqlif-staging/;
        proxy_set_header Host $http_host;
        proxy_buffering off;
        expires 365d;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    # MinIO — teqlif-dm-staging bucket (DM ekleri)
    location /dm/ {
        proxy_pass http://127.0.0.1:9010/teqlif-dm-staging/;
        proxy_set_header Host $http_host;
        proxy_buffering off;
        expires 365d;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }
}
