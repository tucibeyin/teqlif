from sqlalchemy import Column, Integer, String, DateTime, Boolean, Table, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base

followers_table = Table('followers', Base.metadata,
    Column('follower_id', Integer, ForeignKey('users.id'), primary_key=True),
    Column('followed_id', Integer, ForeignKey('users.id'), primary_key=True)
)

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    username = Column(String, unique=True, index=True, nullable=True)
    password_hash = Column(String)
    verification_code = Column(String)
    is_verified = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    is_live = Column(Boolean, default=False)       
    is_auction_active = Column(Boolean, default=False)
    stream_title = Column(String, default="")      
    thumbnail = Column(String, default="")
    
    current_price = Column(Integer, default=0)
    highest_bidder = Column(String, nullable=True)

    followed = relationship(
        "User", 
        secondary=followers_table,
        primaryjoin=(followers_table.c.follower_id == id),
        secondaryjoin=(followers_table.c.followed_id == id),
        backref="followers"
    )

class StreamMessage(Base):
    __tablename__ = "stream_messages"
    id = Column(Integer, primary_key=True, index=True)
    room_name = Column(String, index=True)
    sender = Column(String)
    message = Column(String)
    is_bid = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)