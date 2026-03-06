import { useRef, useEffect } from "react";
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
    onSyncStateRequest: (data: any) => void;
    onRoomClosed: () => void;
    onCountdown: (value: number) => void;
    onStageRequest: (data: any) => void;
}

export function useArenaDataChannel(handlers: DataChannelHandlers) {
    const { data: session } = useSession();
    // Use a ref to always use the latest handlers without re-registering the data channel listener
    const handlersRef = useRef(handlers);

    useEffect(() => {
        handlersRef.current = handlers;
    }, [handlers]);

    useDataChannel((msg) => {
        try {
            const raw = new TextDecoder().decode(msg.payload);
            const data = JSON.parse(raw);
            const h = handlersRef.current;

            switch (data.type) {
                case "NEW_BID": return h.onNewBid(data);
                case "BID_ACCEPTED": return h.onBidAccepted(data);
                case "BID_REJECTED": return h.onBidRejected(data, session?.user?.id);
                case "CHAT": return h.onChat(data);
                case "REACTION": return h.onReaction(data.emoji);
                case "AUCTION_START": return h.onAuctionStart();
                case "AUCTION_END": return h.onAuctionEnd();
                case "AUCTION_RESET": return h.onAuctionReset();
                case "AUCTION_SOLD": return h.onAuctionSold(data);
                case "SALE_FINALIZED": return h.onSaleFinalized(data);
                case "SYNC_STATE_RESPONSE": return h.onSyncStateResponse(data);
                case "SYNC_STATE_REQUEST": return h.onSyncStateRequest(data);
                case "ROOM_CLOSED": return h.onRoomClosed();
                case "COUNTDOWN": return h.onCountdown(data.value);
                case "REQUEST_STAGE": return h.onStageRequest(data);
                default:
                    break;
            }
        } catch {
            // Malformed payload — silently ignore
        }
    });
}
