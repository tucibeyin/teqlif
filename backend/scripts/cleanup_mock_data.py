import asyncio
import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dotenv import load_dotenv
load_dotenv(os.environ.get("TEQLIF_ENV_FILE", ""))

from sqlalchemy import delete, select
from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.listing import Listing
from app.models.stream import LiveStream, LiveStreamViewer
from app.models.like import ListingLike, StreamLike, StoryLike
from app.models.auction import Auction
from app.models.bid import Bid
from app.models.purchase import Purchase
from app.models.analytics import AnalyticsEvent, UserInteraction
from app.models.follow import Follow
from app.models.favorite import Favorite
from app.models.listing_offer import ListingOffer
from app.models.listing_impression import ListingImpression
from app.models.notification import Notification
from app.models.message_thread import MessageThread
from app.models.message import DirectMessage
from app.models.rating import Rating
from app.models.user_interest import UserInterest
from app.models.tuci_transaction import TuciTransaction
from app.models.story import Story, StoryView
from app.models.search_alert import SearchAlert
from app.models.referral import Referral


async def cleanup():
    print("🧹 Mock Veriler Temizleniyor...")

    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(User.id).where(User.email.like("%@example.com%"))
        )
        user_ids = [row[0] for row in result]

        if not user_ids:
            print("Silinecek mock kullanıcı bulunamadı.")
            return

        print(f"🗑️  {len(user_ids)} mock kullanıcıya ait veriler siliniyor...")

        result_streams = await session.execute(
            select(LiveStream.id).where(LiveStream.host_id.in_(user_ids))
        )
        stream_ids = [row[0] for row in result_streams]

        result_listings = await session.execute(
            select(Listing.id).where(Listing.user_id.in_(user_ids))
        )
        listing_ids = [row[0] for row in result_listings]

        result_stories = await session.execute(
            select(Story.id).where(Story.user_id.in_(user_ids))
        )
        story_ids = [row[0] for row in result_stories]

        result_threads = await session.execute(
            select(MessageThread.user_a_id, MessageThread.user_b_id).where(
                MessageThread.user_a_id.in_(user_ids) | MessageThread.user_b_id.in_(user_ids)
            )
        )
        thread_pairs = result_threads.fetchall()

        # Analytics
        await session.execute(delete(AnalyticsEvent).where(AnalyticsEvent.user_id.in_(user_ids)))
        await session.execute(delete(UserInteraction).where(UserInteraction.user_id.in_(user_ids)))

        # Social
        await session.execute(delete(Follow).where(
            Follow.follower_id.in_(user_ids) | Follow.followed_id.in_(user_ids)
        ))
        await session.execute(delete(UserInterest).where(UserInterest.user_id.in_(user_ids)))
        await session.execute(delete(Referral).where(
            Referral.referrer_id.in_(user_ids) | Referral.referred_id.in_(user_ids)
        ))
        await session.execute(delete(TuciTransaction).where(TuciTransaction.user_id.in_(user_ids)))
        await session.execute(delete(SearchAlert).where(SearchAlert.user_id.in_(user_ids)))
        await session.execute(delete(Notification).where(Notification.user_id.in_(user_ids)))
        await session.execute(delete(Rating).where(
            Rating.rater_id.in_(user_ids) | Rating.rated_id.in_(user_ids)
        ))

        # Messages
        await session.execute(delete(DirectMessage).where(
            DirectMessage.sender_id.in_(user_ids) | DirectMessage.receiver_id.in_(user_ids)
        ))
        if thread_pairs:
            for a_id, b_id in thread_pairs:
                await session.execute(
                    delete(MessageThread).where(
                        MessageThread.user_a_id == a_id,
                        MessageThread.user_b_id == b_id,
                    )
                )

        # Stories
        if story_ids:
            await session.execute(delete(StoryView).where(StoryView.story_id.in_(story_ids)))
            await session.execute(delete(StoryLike).where(StoryLike.story_id.in_(story_ids)))
        await session.execute(delete(StoryView).where(StoryView.viewer_id.in_(user_ids)))
        await session.execute(delete(StoryLike).where(StoryLike.user_id.in_(user_ids)))
        if story_ids:
            await session.execute(delete(Story).where(Story.id.in_(story_ids)))

        # Stream-dependent
        if stream_ids:
            await session.execute(delete(Bid).where(Bid.stream_id.in_(stream_ids)))
            await session.execute(delete(LiveStreamViewer).where(LiveStreamViewer.stream_id.in_(stream_ids)))
            await session.execute(delete(StreamLike).where(StreamLike.stream_id.in_(stream_ids)))
            await session.execute(delete(Purchase).where(Purchase.auction_id.in_(
                select(Auction.id).where(Auction.stream_id.in_(stream_ids))
            )))
            await session.execute(delete(Auction).where(Auction.stream_id.in_(stream_ids)))

        # User-dependent stream/bid/purchase leftovers
        await session.execute(delete(Bid).where(Bid.bidder_id.in_(user_ids)))
        await session.execute(delete(Purchase).where(Purchase.buyer_id.in_(user_ids)))
        await session.execute(delete(LiveStreamViewer).where(LiveStreamViewer.user_id.in_(user_ids)))
        await session.execute(delete(StreamLike).where(StreamLike.user_id.in_(user_ids)))

        # Listing-dependent
        if listing_ids:
            await session.execute(delete(ListingOffer).where(ListingOffer.listing_id.in_(listing_ids)))
            await session.execute(delete(ListingImpression).where(ListingImpression.listing_id.in_(listing_ids)))
            await session.execute(delete(Favorite).where(Favorite.listing_id.in_(listing_ids)))
            await session.execute(delete(Purchase).where(Purchase.listing_id.in_(listing_ids)))
            await session.execute(delete(Auction).where(Auction.listing_id.in_(listing_ids)))
            await session.execute(delete(ListingLike).where(ListingLike.listing_id.in_(listing_ids)))

        await session.execute(delete(ListingOffer).where(ListingOffer.user_id.in_(user_ids)))
        await session.execute(delete(ListingImpression).where(ListingImpression.user_id.in_(user_ids)))
        await session.execute(delete(Favorite).where(Favorite.user_id.in_(user_ids)))
        await session.execute(delete(ListingLike).where(ListingLike.user_id.in_(user_ids)))

        # Primary entities
        if stream_ids:
            await session.execute(delete(LiveStream).where(LiveStream.id.in_(stream_ids)))
        if listing_ids:
            await session.execute(delete(Listing).where(Listing.id.in_(listing_ids)))
        await session.execute(delete(User).where(User.id.in_(user_ids)))

        await session.commit()
        print("✅ Tüm mock veriler başarıyla silindi.")


if __name__ == "__main__":
    asyncio.run(cleanup())
