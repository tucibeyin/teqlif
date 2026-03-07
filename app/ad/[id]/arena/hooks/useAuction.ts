import { useState, useCallback, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { useConnectionState } from "@livekit/components-react";
import { ConnectionState } from "livekit-client";
import type { Room } from "livekit-client";
import type { AuctionStatus, AuctionResult } from "../types";
import type { AuctionEndedPayload } from "./useArenaDataChannel";
import type { SyncResponse } from "@/app/api/livekit/sync/route";

interface UseAuctionOptions {
    adId: string;
    sellerId: string;
    room: Room | null;
    initialHighestBid: number;
    initialIsAuctionActive: boolean;
    isQuickLive?: boolean;
    /** Kanal modunda useChannelSync'ten gelen aktif ürün ID'si. */
    activeAdId?: string | null;
}

export function useAuction({
    adId,
    sellerId,
    room,
    initialHighestBid,
    initialIsAuctionActive,
    isQuickLive = false,
    activeAdId: externalActiveAdId = null,
}: UseAuctionOptions) {
    const router = useRouter();
    // Kanal modunda aktif adId değişebilir; ref kullanarak NEW_BID filtresi stale closure'dan etkilenmez.
    const activeAdIdRef = useRef<string>(adId);

    // useChannelSync'ten gelen activeAdId değiştiğinde ref'i güncelle.
    // Late-joiner ve reconnect senaryolarında doğru ürünün filtrelenmesini sağlar.
    useEffect(() => {
        if (externalActiveAdId) {
            activeAdIdRef.current = externalActiveAdId;
        }
    }, [externalActiveAdId]);

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

    // ── Sync (Late Joiner / Reconnection) ──────────────────────────────────────

    const connectionState = useConnectionState();
    const prevConnectionStateRef = useRef<ConnectionState | null>(null);

    const syncAuctionState = useCallback(async () => {
        // Kanal modunda activeAdIdRef.current, ITEM_PINNED veya externalActiveAdId ile güncellenir.
        // Klasik modda adId'ye eşittir. Her iki durumda da doğru ürünü senkronize eder.
        const syncAdId = activeAdIdRef.current;
        try {
            const res = await fetch(`/api/livekit/sync?adId=${syncAdId}`);
            if (!res.ok) return;
            const data: SyncResponse = await res.json();

            setStatus(data.isAuctionActive ? "ACTIVE" : "IDLE");

            // PHASE 21: Protect against downgrading the local bid (race condition)
            if (data.highestBid > highestBid) {
                setHighestBid(data.highestBid);
                if (data.highestBidder) setHighestBidderId(data.highestBidder);
            }
        } catch {
            // Sync hatası kritik değil — sessizce geç
        }
    }, [highestBid]); // adId yerine ref kullanıldı; stale closure riski yok

    // Mount sync: odaya geç katılanlar için ilk yüklemede bir kez çalışır
    useEffect(() => {
        syncAuctionState();
    }, []); // eslint-disable-line react-hooks/exhaustive-deps

    // Reconnection sync: bağlantı Reconnecting → Connected'a döndüğünde çalışır
    useEffect(() => {
        const wasReconnecting = prevConnectionStateRef.current === ConnectionState.Reconnecting;
        prevConnectionStateRef.current = connectionState;
        if (connectionState === ConnectionState.Connected && wasReconnecting) {
            syncAuctionState();
        }
    }, [connectionState, syncAuctionState]);

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
            // Kanal modunda: payload'daki adId, şu an aktif ürünle eşleşmiyorsa sessizce yut.
            if (data.adId && data.adId !== activeAdIdRef.current) return;
            setHighestBid(data.amount);
            setHighestBidId(data.bidId ?? null);
            // Yeni backend: bidderIdentity (userId). Eski: bidderId. Her ikisini destekle.
            setHighestBidderId(data.bidderIdentity ?? data.bidderId ?? null);
            if (data.bidderName) setHighestBidderName(data.bidderName);
            setLastAcceptedBidId(null);
            setFlashBid(true);
            setTimeout(() => setFlashBid(false), 300);
        },
        [] // activeAdIdRef ref'i — dependency gerekmez
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

    /**
     * ITEM_PINNED geldiğinde: tüm ihale state'ini sıfırla, yeni ürünü aktifle.
     * activeAdIdRef güncellenerek sonraki NEW_BID'ler doğru filtrelenir.
     */
    const onItemPinned = useCallback(
        (data: { adId: string; startingBid: number }) => {
            activeAdIdRef.current = data.adId;
            setHighestBid(data.startingBid || 0);
            setHighestBidId(null);
            setHighestBidderId(null);
            setHighestBidderName(null);
            setLastAcceptedBidId(null);
            setStatus("IDLE");
            setResult(null);
            setShowSoldOverlay(false);
            setFinalizedWinner(null);
            setFinalizedAmount(null);
            setShowFinalization(false);
            notify("📦 Yeni ürün sahnede! Teklif verebilirsiniz.");
        },
        [] // Tüm setter'lar ve activeAdIdRef ref'i stabil
    );

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

    const formatWinnerName = (name: string | null) => {
        if (!name) return "Katılımcı";
        const parts = name.trim().split(" ");
        if (parts.length === 1) return parts[0];
        const firstName = parts[0];
        const lastPart = parts[parts.length - 1];
        return `${firstName} ${lastPart[0]}.`;
    };

    const onSaleFinalized = useCallback((data: any) => {
        setFinalizedWinner(formatWinnerName(data.winnerName));
        setFinalizedAmount(data.amount ?? null);
        setShowFinalization(true);
    }, []);

    /**
     * Backend'in /api/livekit/finalize'dan broadcast ettiği AUCTION_ENDED sinyali.
     * Redis'ten gelen nihai kazanan ve fiyatı içerir — client'a güvenilmez.
     */
    const onAuctionEnded = useCallback((data: AuctionEndedPayload) => {
        setStatus("IDLE");
        setFinalizedWinner(formatWinnerName(data.winner));
        setFinalizedAmount(data.amount);
        setShowFinalization(true);
        notify("🎉 İhale tamamlandı!");
    }, []);

    const onAuctionSold = useCallback((data: any) => {
        setResult({ winnerName: formatWinnerName(data.winnerName), price: data.price ?? 0 });
        setShowSoldOverlay(true);
        setStatus("IDLE");
    }, []);

    const onSyncStateResponse = useCallback((data: any) => {
        if (data.isAuctionActive !== undefined) setStatus(data.isAuctionActive ? "ACTIVE" : "IDLE");

        // PHASE 21: Protect against downgrading the local bid (race condition)
        if (data.highestBid !== undefined && data.highestBid > highestBid) {
            setHighestBid(data.highestBid);
            if (data.highestBidderName) setHighestBidderName(data.highestBidderName);
        }

        if (data.isSold !== undefined) setShowSoldOverlay(data.isSold);
    }, [highestBid]);

    const broadcastState = useCallback(() => {
        if (!room) return;
        const payload = {
            type: "SYNC_STATE_RESPONSE",
            isAuctionActive: status === "ACTIVE",
            highestBid: highestBid,
            highestBidderName: highestBidderName,
            isSold: showSoldOverlay,
        };
        publish(payload);
    }, [room, status, highestBid, highestBidderName, showSoldOverlay, publish]);

    // ── Host actions ──

    const start = useCallback(async () => {
        if (!room) return;
        setLoading(true);
        try {
            await fetch(`/api/ads/${activeAdIdRef.current}/live`, {
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
    }, [room, publish]);

    const stop = useCallback(async () => {
        if (!room) return;
        setLoading(true);
        try {
            await fetch(`/api/ads/${activeAdIdRef.current}/live`, {
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
    }, [room, publish]);

    const reset = useCallback(async () => {
        if (!room) return;
        if (!confirm("Açık arttırmayı sıfırlamak istiyor musunuz? Tüm teklifler arşivlenecek ve başlangıç fiyatına dönülecektir.")) return;
        setLoading(true);
        try {
            const res = await fetch("/api/livekit/reset", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ adId: activeAdIdRef.current }),
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
    }, [room, publish]);

    const accept = useCallback(async () => {
        if (!confirm("Dikkat! Bu teqlifi kabul edip satışı tamamlıyorsunuz?")) return;
        setLoading(true);
        try {
            // Kazanan ve fiyat artık backend'de Redis'ten okunuyor.
            // Client'tan winnerId / finalPrice gönderilmez — manipülasyon riski ortadan kalkar.
            const res = await fetch("/api/livekit/finalize", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ adId: activeAdIdRef.current, isQuickLive, channelHostId: sellerId }),
            });
            if (!res.ok) {
                const data = await res.json();
                notify(data.error || "Satış tamamlanamadı.");
            }
            // Başarılı: backend AUCTION_ENDED sinyalini tüm katılımcılara broadcast eder.
            // onAuctionEnded handler'ı çalışarak UI'ı günceller — burada manuel state değişikliğine gerek yok.
        } catch (e) {
            console.error("[accept] finalize error:", e);
            notify("Bağlantı hatası.");
        } finally {
            setLoading(false);
        }
    }, [isQuickLive, notify]);

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
                body: JSON.stringify({ userId: sellerId, adId: activeAdIdRef.current }),
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
    }, [sellerId, router]);

    return {
        // State
        highestBid, highestBidId, highestBidderId, highestBidderName,
        lastAcceptedBidId, status, notification, flashBid,
        result, showSoldOverlay, setShowSoldOverlay,
        finalizedWinner, finalizedAmount, showFinalization, setShowFinalization,
        loading,
        // Incoming event handlers
        onNewBid, onBidAccepted, onBidRejected,
        onAuctionStart, onAuctionEnd, onAuctionReset, onItemPinned,
        onAuctionEnded, onSaleFinalized, onAuctionSold, onSyncStateResponse,
        // Host actions
        start, stop, reset, accept, reject, buyNow, broadcastState,
        // Sync
        syncAuctionState,
    };
}
