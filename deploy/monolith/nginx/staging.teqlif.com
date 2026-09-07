# /etc/nginx/sites-available/staging.teqlif.com
# Certbot tarafından yönetilir — ssl blokları certbot tarafından eklendi

server {
    server_name staging.teqlif.com;

    client_max_body_size 50M;

    location /uploads/ {
        proxy_pass http://127.0.0.1:9010/teqlif-staging/;
        proxy_set_header Host $http_host;
        proxy_buffering off;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    listen [::]:443 ssl ipv6only=on; # managed by Certbot
    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/staging.teqlif.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/staging.teqlif.com/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}

server {
    if ($host = staging.teqlif.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    server_name staging.teqlif.com;
    listen 80;
    listen [::]:80;
    return 404; # managed by Certbot
}
