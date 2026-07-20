import enum

class ListingStatus(str, enum.Enum):
    ACTIVE = "active"
    PASSIVE = "passive"
    SOLD = "sold"
    SUSPENDED = "suspended"
    EXPIRED = "expired"
    DELETED = "deleted"

class UserStatus(str, enum.Enum):
    ACTIVE = "active"
    PASSIVE = "passive"
    BANNED = "banned"
    DELETED = "deleted"

class CategoryStatus(str, enum.Enum):
    ACTIVE = "active"
    PASSIVE = "passive"

class SearchAlertStatus(str, enum.Enum):
    ACTIVE = "active"
    PASSIVE = "passive"
