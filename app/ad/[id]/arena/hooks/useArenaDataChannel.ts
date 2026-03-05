import { useDataChannel } from "@livekit/components-react";
import { useSession } from "next-auth/react";

interface DataChannelHandlers {
    onNewBid: (data: any) => void;
    onBidAccepted: (data: any) => void;
    onBidRejected: (data: any, currentUserId?: string) => void;
    onChat: (data: any) => void;
    onReaction: (emoji: string) => void;
    onAuctionStart: () => void;
    onAuctionEnd: () => void;
    onAuctionReset: () => void;
    onAuctionSold: (data: any) => void;
    onSaleFinalized: (data: any) => void;
    onSyncStateResponse: (data: any) => void;
    onRoomClosed: () => void;
    onCountdown: (value: number) => void;
    onStageRequest: (data: any) => void;
}

export function useArenaDataChannel(handlers: DataChannelHandlers) {
    const { data: session } = useSession();

    useDataChannel((msg) => {
        try {
            const raw = new TextDecoder().decode(msg.payload);
            const data = JSON.parse(raw);

            switch (data.type) {
                case "NEW_BID":              return handlers.onNewBid(data);
                case "BID_ACCEPTED":         return handlers.onBidAccepted(data);
                case "BID_REJECTED":         return handlers.onBidRejected(data, session?.user?.id);
                case "CHAT":                 return handlers.onChat(data);
                case "REACTION":             return handlers.onReaction(data.emoji);
                case "AUCTION_START":        return handlers.onAuctionStart();
                case "AUCTION_END":          return handlers.onAuctionEnd();
                case "AUCTION_RESET":        return handlers.onAuctionReset();
                case "AUCTION_SOLD":         return handlers.onAuctionSold(data);
                case "SALE_FINALIZED":       return handlers.onSaleFinalized(data);
                case "SYNC_STATE_RESPONSE":  return handlers.onSyncStateResponse(data);
                case "ROOM_CLOSED":          return handlers.onRoomClosed();
                case "COUNTDOWN":            return handlers.onCountdown(data.value);
                case "REQUEST_STAGE":        return handlers.onStageRequest(data);
                default:
                    break;
            }
        } catch {
            // Malformed payload — silently ignore
        }
    });
}
