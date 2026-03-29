import logging
import os
from logging.handlers import TimedRotatingFileHandler

LOGS_DIR = os.path.join(os.path.dirname(__file__), "..", "logs")


def setup_logging() -> logging.Logger:
    os.makedirs(LOGS_DIR, exist_ok=True)

    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Tüm loglar (INFO+)
    app_handler = TimedRotatingFileHandler(
        os.path.join(LOGS_DIR, "app.log"),
        when="midnight",
        interval=1,
        backupCount=7,
        encoding="utf-8",
    )
    app_handler.setLevel(logging.INFO)
    app_handler.setFormatter(fmt)

    # Sadece ERROR+
    error_handler = TimedRotatingFileHandler(
        os.path.join(LOGS_DIR, "error.log"),
        when="midnight",
        interval=1,
        backupCount=7,
        encoding="utf-8",
    )
    error_handler.setLevel(logging.ERROR)
    error_handler.setFormatter(fmt)

    # Konsol (uvicorn'un zaten basar, WARNING+ göster)
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.WARNING)
    console_handler.setFormatter(fmt)

    root = logging.getLogger()
    root.setLevel(logging.INFO)
    root.addHandler(app_handler)
    root.addHandler(error_handler)
    root.addHandler(console_handler)

    return logging.getLogger("teqlif")
