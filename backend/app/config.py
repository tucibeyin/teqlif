from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str
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
