from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime, Table
from sqlalchemy.orm import relationship
from database import Base
from datetime import datetime

# Takipçi İlişki Tablosu (Many-to-Many)
followers_table = Table(
    'followers', Base.metadata,
    Column('follower_id', Integer, ForeignKey('users.id'), primary_key=True),
    Column('followed_id', Integer, ForeignKey('users.id'), primary_key=True)
)

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    username = Column(String, unique=True, index=True)
    password_hash = Column(String)
    
    # 🔥 EKSİK OLAN DOĞRULAMA ALANLARI EKLENDİ 🔥
    verification_code = Column(String, nullable=True)
    is_verified = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Yayın Bilgileri
    is_live = Column(Boolean, default=False)
    stream_title = Column(String, nullable=True)
    stream_category = Column(String, default="Genel")
    thumbnail = Column(String, nullable=True)
    
    # Elmas ve Mezat Bilgileri
    diamonds = Column(Integer, default=500)
    current_price = Column(Integer, default=0)
    highest_bidder = Column(String, nullable=True)
    is_auction_active = Column(Boolean, default=False)

    # İlişkiler
    followed = relationship(
        "User", 
        secondary=followers_table,
        primaryjoin=id==followers_table.c.follower_id,
        secondaryjoin=id==followers_table.c.followed_id,
        backref="followers"
    )

class StreamMessage(Base):
    __tablename__ = "stream_messages"

    id = Column(Integer, primary_key=True, index=True)
    room_name = Column(String, index=True)
    sender = Column(String)
    message = Column(String)
    is_bid = Column(Boolean, default=False)
    
    # Hediye Bilgileri
    is_gift = Column(Boolean, default=False)
    gift_type = Column(String, nullable=True)
    
    created_at = Column(DateTime, default=datetime.utcnow)