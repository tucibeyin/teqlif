import asyncio
import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dotenv import load_dotenv
backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load_dotenv(os.path.join(backend_dir, ".env"))

from sqlalchemy import delete, select
from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.listing import Listing
from app.models.stream import LiveStream, LiveStreamViewer
from app.models.like import ListingLike, StreamLike
from app.models.auction import Auction
from app.models.bid import Bid
from app.models.purchase import Purchase
from app.models.analytics import AnalyticsEvent, UserInteraction

async def cleanup():
    print("🧹 Mock Veriler Temizleniyor...")
    
    async with AsyncSessionLocal() as session:
        # Mock kullanıcıları tespit et (@example.com olanlar)
        stmt = select(User.id).where(User.email.like("%@example.com%"))
        result = await session.execute(stmt)
        user_ids = [row[0] for row in result]
        
        if not user_ids:
            print("Silinecek mock kullanıcı bulunamadı.")
            return

        print(f"🗑️ {len(user_ids)} adet mock kullanıcıya ait bağımlı veriler siliniyor...")
        
        # Foreign key constraint hatalarını engellemek için bağımlılık sırasına göre siliyoruz
        
        await session.execute(delete(AnalyticsEvent).where(AnalyticsEvent.user_id.in_(user_ids)))
        await session.execute(delete(UserInteraction).where(UserInteraction.user_id.in_(user_ids)))
        
        await session.execute(delete(LiveStreamViewer).where(LiveStreamViewer.user_id.in_(user_ids)))
        await session.execute(delete(StreamLike).where(StreamLike.user_id.in_(user_ids)))
        await session.execute(delete(LiveStream).where(LiveStream.host_id.in_(user_ids)))
        
        await session.execute(delete(Purchase).where(Purchase.buyer_id.in_(user_ids)))
        await session.execute(delete(Bid).where(Bid.bidder_id.in_(user_ids)))
        
        # find auctions belonging to listings owned by these users, or simply delete auctions by checking listing owner
        # since cascading delete isn't guaranteed here, let's just delete auctions where winner_id is in user_ids to be safe, 
        # or delete all auctions and purchases since they are mock anyway.
        # It's better to just delete auctions where listing owner is mock user.
        stmt_listings = select(Listing.id).where(Listing.user_id.in_(user_ids))
        result_listings = await session.execute(stmt_listings)
        listing_ids = [row[0] for row in result_listings]
        
        if listing_ids:
            await session.execute(delete(Purchase).where(Purchase.listing_id.in_(listing_ids)))
            await session.execute(delete(Bid).where(Bid.listing_id.in_(listing_ids)))
            await session.execute(delete(Auction).where(Auction.listing_id.in_(listing_ids)))
            await session.execute(delete(ListingLike).where(ListingLike.listing_id.in_(listing_ids)))
            await session.execute(delete(Listing).where(Listing.id.in_(listing_ids)))
            
        await session.execute(delete(ListingLike).where(ListingLike.user_id.in_(user_ids)))
        
        await session.execute(delete(User).where(User.id.in_(user_ids)))
        
        await session.commit()
        print("✅ Başarılı! Tüm mock veriler (ilanlar, yayınlar, beğeniler, analitik ve kullanıcılar) veritabanından tamamen silindi.")

if __name__ == "__main__":
    asyncio.run(cleanup())
