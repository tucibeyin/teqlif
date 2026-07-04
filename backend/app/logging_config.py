import logging
import os
from logging.handlers import TimedRotatingFileHandler
from pythonjsonlogger import jsonlogger

LOGS_DIR = os.path.join(os.path.dirname(__file__), "..", "logs")

# JSON alanları: timestamp, level, logger, message + varsa exc_info
_JSON_FIELDS = "%(asctime)s %(levelname)s %(name)s %(message)s"


def _make_json_handler(path: str, level: int) -> TimedRotatingFileHandler:
    handler = TimedRotatingFileHandler(
        path,
        when="midnight",
        interval=1,
        backupCount=7,
        encoding="utf-8",
    )
    handler.setLevel(level)
    handler.setFormatter(jsonlogger.JsonFormatter(
        _JSON_FIELDS,
        datefmt="%Y-%m-%dT%H:%M:%SZ",
        rename_fields={"asctime": "timestamp", "levelname": "level", "name": "logger"},
    ))
    return handler


def setup_logging() -> logging.Logger:
    os.makedirs(LOGS_DIR, exist_ok=True)

    # Konsol — uvicorn zaten basar, WARNING+ göster (düz metin yeterli)
    console_fmt = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.WARNING)
    console_handler.setFormatter(console_fmt)

    root = logging.getLogger()
    root.setLevel(logging.INFO)
    root.addHandler(_make_json_handler(os.path.join(LOGS_DIR, "app.log"), logging.INFO))
    root.addHandler(_make_json_handler(os.path.join(LOGS_DIR, "error.log"), logging.ERROR))
    root.addHandler(_make_json_handler(os.path.join(LOGS_DIR, "worker.log"), logging.INFO))
    root.addHandler(console_handler)

    # worker.log sadece arq worker kayıtlarını alsın — diğer handler'lar root'tan devralır
    worker_logger = logging.getLogger("arq")
    worker_file = _make_json_handler(os.path.join(LOGS_DIR, "worker.log"), logging.INFO)
    worker_logger.addHandler(worker_file)
    worker_logger.propagate = True

    return logging.getLogger("teqlif")
