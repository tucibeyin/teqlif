from typing import Any, Dict, Type, TypeVar

T = TypeVar("T")

class Container:
    """
    Uygulama geneli basit bir Dependency Injection (DI) Container.
    
    FastAPI (Depends) haricinde çalışan ARQ worker'ları ve
    servis katmanları için global bağımlılık (Service Locator) sağlar.
    """
    def __init__(self):
        self._services: Dict[Type, Any] = {}

    def register(self, interface: Type[T], implementation: T):
        self._services[interface] = implementation

    def resolve(self, interface: Type[T]) -> T:
        if interface not in self._services:
            raise KeyError(f"Service {interface.__name__} not registered in DI container.")
        return self._services[interface]

container = Container()

def inject(interface: Type[T]):
    """
    FastAPI endpoint'lerinde kullanılmak üzere bağımlılık sağlayıcı (Provider).
    Örnek kullanım:
        def my_route(my_service: MyService = Depends(inject(MyService))):
            ...
    """
    def _dependency() -> T:
        return container.resolve(interface)
    return _dependency

def init_di():
    """
    Uygulama başlarken DI Container'a tüm interface ve adapter'ları kaydeder.
    FirebaseAdapter, firebase_admin.messaging yerine google-auth + requests ile
    FCM V1 REST API'yi doğrudan çağırır.
    """
    from app.core.ports.push_notification_port import PushNotificationPort
    from app.infrastructure.adapters.firebase_adapter import FirebaseAdapter
    from app.config import settings
    import logging
    import json
    _log = logging.getLogger(__name__)

    project_id = None
    sa_path = settings.firebase_service_account or None

    if sa_path:
        try:
            with open(sa_path) as f:
                sa_data = json.load(f)
            project_id = sa_data.get("project_id")
            _log.info(
                "[DI] Service account okundu | project=%s | sa_path=%s",
                project_id,
                sa_path,
            )
        except Exception as exc:
            _log.error("[DI] Service account okunamadı: %s", exc, exc_info=True)
    else:
        _log.warning("[DI] FIREBASE_SERVICE_ACCOUNT ayarlanmamış — push devre dışı")

    container.register(
        PushNotificationPort,
        FirebaseAdapter(project_id=project_id, sa_path=sa_path if project_id else None),
    )

