# /etc/nginx/sites-available/uploads.teqlif.com — node1
# Scale V1.0: uploads.teqlif.com DNS only → node1 135.125.175.223 direkt
# Gateway'i bypass eder — büyük dosya transferleri için Netcup throttle'ı aşar

server {
    listen 80;
    server_name uploads.teqlif.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name uploads.teqlif.com;

    ssl_certificate /etc/letsencrypt/live/uploads.teqlif.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/uploads.teqlif.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL_UPLOADS:5m;

    server_tokens off;
    client_max_body_size 100M;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options "nosniff" always;

    # MinIO — uploads bucket
    location / {
        proxy_pass http://127.0.0.1:9010/teqlif/;
        proxy_set_header Host $http_host;
        proxy_buffering off;
        expires 365d;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }
}
