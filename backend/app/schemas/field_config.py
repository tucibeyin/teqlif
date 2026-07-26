from pydantic import BaseModel


class FieldOptionSchema(BaseModel):
    value: str
    label: str
    parent_option_value: str | None = None
    exclusion_group: str | None = None
    is_exclusive: bool = False

    model_config = {"from_attributes": True}


class ExtraFieldSchema(BaseModel):
    key: str
    label_key: str
    type: str  # text | number | dropdown
    required: bool
    position: int
    unit: str | None = None
    depends_on: str | None = None
    options: list[FieldOptionSchema] = []

    model_config = {"from_attributes": True}


class FieldConfigResponse(BaseModel):
    subcategory: str
    fields: list[ExtraFieldSchema]
