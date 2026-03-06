import { useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import type { Room } from "livekit-client";
import type { AuctionStatus, AuctionResult } from "../types";

interface UseAuctionOptions {
    adId: string;
    sellerId: string;
    room: Room | null;
    initialHighestBid: number;
    initialIsAuctionActive: boolean;
}

export function useAuction({
    adId,
    sellerId,
    room,
    initialHighestBid,
    initialIsAuctionActive,
}: UseAuctionOptions) {
    const router = useRouter();
    const [highestBid, setHighestBid] = useState(initialHighestBid);
    const [highestBidId, setHighestBidId] = useState<string | null>(null);
    const [highestBidderId, setHighestBidderId] = useState<string | null>(null);
    const [highestBidderName, setHighestBidderName] = useState<string | null>(null);
    const [lastAcceptedBidId, setLastAcceptedBidId] = useState<string | null>(null);
    const [status, setStatus] = useState<AuctionStatus>(initialIsAuctionActive ? "ACTIVE" : "IDLE");
    const [notification, setNotification] = useState<string | null>(null);
    const [flashBid, setFlashBid] = useState(false);
    const [result, setResult] = useState<AuctionResult | null>(null);
    const [showSoldOverlay, setShowSoldOverlay] = useState(false);
    const [finalizedWinner, setFinalizedWinner] = useState<string | null>(null);
    const [finalizedAmount, setFinalizedAmount] = useState<number | null>(null);
    const [showFinalization, setShowFinalization] = useState(false);
    const [loading, setLoading] = useState(false);

    const notify = (msg: string, duration = 4000) => {
        setNotification(msg);
        setTimeout(() => setNotification(null), duration);
    };

    const publish = useCallback(
        (payload: object) => {
            if (!room) return;
            room.localParticipant.publishData(
                new TextEncoder().encode(JSON.stringify(payload)),
                { reliable: true }
            );
        },
        [room]
    );

    // ── Incoming event handlers (called from useArenaDataChannel) ──

    const onNewBid = useCallback(
        (data: any) => {
            setHighestBid(data.amount);
            setHighestBidId(data.bidId ?? null);
            setHighestBidderId(data.bidderId ?? null);
            if (data.bidderName) setHighestBidderName(data.bidderName);
            setLastAcceptedBidId(null);
            setFlashBid(true);
            setTimeout(() => setFlashBid(false), 300);
        },
        []
    );

    const onBidAccepted = useCallback((data: any) => {
        setHighestBid(data.amount);
        setHighestBidId(data.bidId ?? null);
        setHighestBidderId(data.bidderId ?? null);
        if (data.bidderName) setHighestBidderName(data.bidderName);
        setLastAcceptedBidId(data.bidId ?? null);
        setFlashBid(true);
        setTimeout(() => setFlashBid(false), 300);
    }, []);

    const onBidRejected = useCallback(
        (data: any, currentUserId?: string) => {
            if (currentUserId === data.bidderId) {
                alert("Teklifiniz satıcı tarafından reddedildi.");
            }
            setHighestBid(initialHighestBid);
            setHighestBidId(null);
            setHighestBidderId(null);
            setHighestBidderName(null);
            notify("📣 Son Teklif Reddedildi", 3000);
        },
        [initialHighestBid]
    );

    const onAuctionStart = useCallback(() => {
        setStatus("ACTIVE");
        notify("📣 AÇIK ARTTIRMA BAŞLADI!");
    }, []);

    const onAuctionEnd = useCallback(() => {
        setStatus("IDLE");
        notify("📣 AÇIK ARTTIRMA DURDURULDU");
    }, []);

    const onAuctionReset = useCallback(() => {
        setHighestBid(0);
        setHighestBidId(null);
        setHighestBidderId(null);
        setHighestBidderName(null);
        setStatus("IDLE");
        setResult(null);
        setShowSoldOverlay(false);
        setFinalizedWinner(null);
        setFinalizedAmount(null);
        setShowFinalization(false);
        notify("📣 Yeni Ürüne Geçildi! Teklif Bekleniyor...");
    }, [initialHighestBid]);

    const onSaleFinalized = useCallback((data: any) => {
        setFinalizedWinner(data.winnerName || "Katılımcı");
        setFinalizedAmount(data.amount ?? null);
        setShowFinalization(true);
    }, []);

    const onAuctionSold = useCallback((data: any) => {
        setResult({ winnerName: data.winnerName || "Katılımcı", price: data.price ?? 0 });
        setShowSoldOverlay(true);
        setStatus("IDLE");
    }, []);

    const onSyncStateResponse = useCallback((data: any) => {
        if (data.auctionStatus) setStatus(data.auctionStatus);
        if (data.liveHighestBid) setHighestBid(data.liveHighestBid);
        if (data.liveHighestBidderName) setHighestBidderName(data.liveHighestBidderName);
    }, []);

    const broadcastState = useCallback(() => {
        if (!room) return;
        const payload = {
            type: "SYNC_STATE_RESPONSE",
            auctionStatus: status,
            liveHighestBid: highestBid,
            liveHighestBidderName: highestBidderName,
        };
        publish(payload);
    }, [room, status, highestBid, highestBidderName, publish]);

    // ── Host actions ──

    const start = useCallback(async () => {
        if (!room) return;
        setLoading(true);
        try {
            await fetch(`/api/ads/${adId}/live`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ isAuctionActive: true }),
            });
            publish({ type: "AUCTION_START" });
            setStatus("ACTIVE");
            notify("📣 AÇIK ARTTIRMA BAŞLADI!");
        } catch (e) {
            console.error(e);
        } finally {
            setLoading(false);
        }
    }, [room, adId, publish]);

    const stop = useCallback(async () => {
        if (!room) return;
        setLoading(true);
        try {
            await fetch(`/api/ads/${adId}/live`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ isAuctionActive: false }),
            });
            publish({ type: "AUCTION_END" });
            setStatus("IDLE");
            notify("📣 AÇIK ARTTIRMA DURDURULDU");
        } catch (e) {
            console.error(e);
        } finally {
            setLoading(false);
        }
    }, [room, adId, publish]);

    const reset = useCallback(async () => {
        if (!room) return;
        if (!confirm("Açık arttırmayı sıfırlamak istiyor musunuz? Tüm teklifler arşivlenecek ve başlangıç fiyatına dönülecektir.")) return;
        setLoading(true);
        try {
            const res = await fetch("/api/livekit/reset", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ adId }),
            });
            if (res.ok) {
                publish({ type: "AUCTION_RESET" });
                onAuctionReset();
            }
        } catch (e) {
            console.error("Reset Auction Error:", e);
        } finally {
            setLoading(false);
        }
    }, [room, adId, publish]);

    const accept = useCallback(async () => {
        if (!highestBidId) return;
        if (!confirm("Dikkat! Bu teqlifi kabul edip satışı tamamlıyorsunuz?")) return;
        setLoading(true);
        try {
            const res = await fetch(`/api/bids/${highestBidId}/accept`, { method: "PATCH" });
            if (res.ok) {
                setLastAcceptedBidId(highestBidId);
                const auctionSoldPayload = {
                    type: "AUCTION_SOLD",
                    winnerName: highestBidderName,
                    price: highestBid,
                };
                publish(auctionSoldPayload);
                setResult({ winnerName: highestBidderName || "Katılımcı", price: highestBid });
                setShowSoldOverlay(true);
            }
        } catch (e) {
            console.error(e);
        } finally {
            setLoading(false);
        }
    }, [highestBidId, highestBidderName, highestBid, publish]);

    const reject = useCallback(async () => {
        if (!highestBidId) return;
        setLoading(true);
        try {
            const res = await fetch(`/api/bids/${highestBidId}/reject`, { method: "PATCH" });
            if (res.ok) {
                setHighestBid(initialHighestBid);
                setHighestBidId(null);
                setHighestBidderId(null);
                setHighestBidderName(null);
                publish({ type: "BID_REJECTED", bidId: highestBidId, bidderId: highestBidderId });
                notify("📣 Son Teklif Reddedildi", 3000);
            }
        } catch (e) {
            console.error(e);
        } finally {
            setLoading(false);
        }
    }, [highestBidId, highestBidderId, initialHighestBid, publish]);

    const buyNow = useCallback(async () => {
        setLoading(true);
        try {
            const res = await fetch("/api/conversations", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ userId: sellerId, adId }),
            });
            if (res.ok) {
                const conversation = await res.json();
                router.push(`/dashboard/messages?id=${conversation.id}`);
            }
        } catch (e) {
            console.error(e);
        } finally {
            setLoading(false);
        }
    }, [sellerId, adId, router]);

    return {
        // State
        highestBid, highestBidId, highestBidderId, highestBidderName,
        lastAcceptedBidId, status, notification, flashBid,
        result, showSoldOverlay, setShowSoldOverlay,
        finalizedWinner, finalizedAmount, showFinalization, setShowFinalization,
        loading,
        // Incoming event handlers
        onNewBid, onBidAccepted, onBidRejected,
        onAuctionStart, onAuctionEnd, onAuctionReset,
        onSaleFinalized, onAuctionSold, onSyncStateResponse,
        // Host actions
        start, stop, reset, accept, reject, buyNow, broadcastState,
    };
}
