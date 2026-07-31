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
    Firebase, lazy değil eager olarak burada initialize edilir — worker/uvicorn
    başladığı anda credentials doğrulanır, singleton belirsizliği ortadan kalkar.
    """
    from app.core.ports.push_notification_port import PushNotificationPort
    from app.infrastructure.adapters.firebase_adapter import FirebaseAdapter
    from app.config import settings
    import logging
    _log = logging.getLogger(__name__)

    firebase_app = None
    if settings.firebase_service_account:
        try:
            import firebase_admin
            from firebase_admin import credentials
            cred = credentials.Certificate(settings.firebase_service_account)
            try:
                firebase_app = firebase_admin.get_app()
                _log.info("[DI] Firebase app zaten mevcut, yeniden kullanılıyor.")
            except ValueError:
                firebase_app = firebase_admin.initialize_app(cred)
                _log.info("[DI] Firebase başarıyla başlatıldı | project=%s", cred.project_id)
        except Exception as exc:
            _log.error("[DI] Firebase init başarısız: %s", exc, exc_info=True)
    else:
        _log.warning("[DI] FIREBASE_SERVICE_ACCOUNT ayarlanmamış — push devre dışı")

    container.register(PushNotificationPort, FirebaseAdapter(firebase_app))

