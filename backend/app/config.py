import os

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str
    db_pool_size: int = 20
    db_max_overflow: int = 10
    db_pool_timeout: int = 30
    db_pool_recycle: int = 1800
    use_pgbouncer: bool = False
    redis_url: str = "redis://localhost:6379"
    secret_key: str
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    upload_dir: str = "/var/www/teqlif.com/uploads"
    brevo_api_key: str = ""
    brevo_sender_email: str = "noreply@teqlif.com"
    brevo_sender_name: str = "teqlif"
    # --- V1.4 EDGE MİMARİSİ (Dinamik Medya & Yayın) ---
    edge_livekit_urls: str | list[str] = []
    edge_minio_urls: str | list[str] = []
    minio_storage_quota_percent: int = 80
    edge_metrics_interval_sec: int = 3

    livekit_api_key: str = ""
    livekit_api_secret: str = ""
    
    @field_validator("edge_livekit_urls", "edge_minio_urls", mode="before")
    def parse_comma_separated_list(cls, v):
        if isinstance(v, str):
            return [url.strip() for url in v.split(",") if url.strip()]
        return v or []

    firebase_service_account: str = ""  # path to service account JSON
    sentry_backend_dsn: str | None = None
    google_client_id: str = ""
    site_url: str = "https://www.teqlif.com"
    admin_email: str = ""
    admin_password_hash: str = ""
    captcha_enabled: bool = False
    captcha_provider: str = "turnstile"
    captcha_secret_key: str = ""
    debug: bool = False  # True → localhost CORS origins eklenir (sadece geliştirme ortamı)
    web_app_enabled: bool = False  # Staging için index.html sunulmasını kontrol eder
    groq_api_key: str = ""
    gemini_api_key: str = ""
    node2_ai_proxy_url: str = ""        # ör. "http://10.10.0.3:8080" — boşsa node2 atlanır
    node3_ai_proxy_url: str = ""        # ör. "http://10.10.0.4:8080" — boşsa node3 atlanır
    ai_proxy_internal_token: str = ""   # Shared bearer token — node1, node2, node3 aynı değeri kullanır
    telegram_bot_token: str = ""
    telegram_chat_id: str = ""
    
    minio_access_key: str = ""
    minio_secret_key: str = ""
    minio_bucket: str = "teqlif"
    minio_dm_bucket: str = "teqlif-dm"   # private bucket for DM media (presigned access)
    minio_secure: bool = False
    minio_region: str = "us-east-1"      # S3 API uyumluluğu ve ağ keşfini atlamak için

    # ClickHouse analytics
    clickhouse_host: str = "localhost"
    clickhouse_port: int = 8123
    clickhouse_db: str = "default"

    # APNS VoIP Push Ayarları
    # Token-based auth (.p8) — süresi dolmaz, tercih edilen yöntem.
    # apns_key_path + apns_key_id + apns_team_id üçü set edilirse token-based kullanılır.
    apns_key_path: str = ""       # /path/to/AuthKey_XXXXXXXXXX.p8
    apns_key_id: str = ""         # 10 karakterlik Key ID (Apple Developer Portal)
    apns_team_id: str = ""        # 10 karakterlik Team ID
    # Eski sertifika bazlı auth (.pem) — yıllık yenileme gerekir, fallback olarak korundu.
    apns_cert_path: str = ""
    ios_bundle_id: str = "teqlif"
    apns_use_sandbox: bool = False

    model_config = SettingsConfigDict(
        env_file=os.environ.get("TEQLIF_ENV_FILE", ".env.production"),
        env_ignore_empty=True,
        extra="ignore"
    )


settings = Settings()
