from pydantic_settings import BaseSettings


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
    livekit_url: str = "wss://teqlif.com/rtc"
    livekit_api_key: str = ""
    livekit_api_secret: str = ""
    # LiveKit admin API URL'si (boşsa livekit_url'dan path çıkarılarak türetilir)
    livekit_api_url: str = ""

    @property
    def livekit_api_base(self) -> str:
        """Admin API çağrıları için path içermeyen URL döndürür."""
        if self.livekit_api_url:
            return self.livekit_api_url
        from urllib.parse import urlparse
        parsed = urlparse(self.livekit_url)
        return f"{parsed.scheme}://{parsed.netloc}"
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
    groq_api_key: str = ""
    telegram_bot_token: str = ""
    telegram_chat_id: str = ""
    minio_endpoint: str = "localhost:9000"
    minio_access_key: str = ""
    minio_secret_key: str = ""
    minio_bucket: str = "teqlif"
    minio_secure: bool = False

    # APNS VoIP Push Ayarları
    apns_cert_path: str = ""
    ios_bundle_id: str = "teqlif"
    apns_use_sandbox: bool = False

    class Config:
        env_file = ".env"


settings = Settings()
