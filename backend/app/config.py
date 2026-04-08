from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str
    db_pool_size: int = 20
    db_max_overflow: int = 50
    db_pool_timeout: int = 30
    db_pool_recycle: int = 1800
    redis_url: str = "redis://localhost:6379"
    secret_key: str
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60
    upload_dir: str = "/var/www/teqlif/uploads"
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
    # Firebase Web SDK config (public — kayit.html'e /api/config/public üzerinden servis edilir)
    firebase_web_api_key: str = ""
    firebase_web_auth_domain: str = ""
    firebase_web_project_id: str = ""
    firebase_web_storage_bucket: str = ""
    firebase_web_messaging_sender_id: str = ""
    firebase_web_app_id: str = ""
    sentry_backend_dsn: str | None = None
    google_client_id: str = ""
    admin_email: str = ""
    admin_password: str = ""
    admin_password_hash: str = ""
    captcha_enabled: bool = False
    captcha_provider: str = "turnstile"
    captcha_secret_key: str = ""

    class Config:
        env_file = ".env"


settings = Settings()
