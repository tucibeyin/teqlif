from decimal import Decimal
from pydantic import BaseModel, ConfigDict


class BaseSchema(BaseModel):
    """Tüm response schema'ların türetileceği temel sınıf.
    Decimal alanlar JSON'a float olarak serialize edilir (Flutter uyumlu).
    """
    model_config = ConfigDict(
        from_attributes=True,
        json_encoders={Decimal: float},
    )
