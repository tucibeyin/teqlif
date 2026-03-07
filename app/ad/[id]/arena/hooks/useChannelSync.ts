import { useState, useCallback, useEffect, useRef } from "react";
import { useConnectionState } from "@livekit/components-react";
import { ConnectionState } from "livekit-client";
import type { ChannelSyncResponse } from "@/app/api/livekit/channel/sync/route";

interface UseChannelSyncOptions {
    /** Kanalın sahibi (host) kullanıcı ID'si. null verilirse hook pasif kalır. */
    hostId: string | null;
}

interface UseChannelSyncReturn {
    /** Kanalda şu an satılan ürünün ID'si. null = ürün sabitlenmemiş. */
    activeAdId: string | null;
    channelStatus: ChannelSyncResponse["channelStatus"];
    /** Manuel veya reconnect tetiklemeli senkronizasyon. */
    syncChannelState: () => Promise<void>;
    /** ITEM_PINNED DataChannel sinyali geldiğinde çağrılır — activeAdId'yi anında günceller. */
    onItemPinned: (adId: string) => void;
}

/**
 * Yayıncı kanalının anlık durumunu yönetir.
 *
 * - İlk mount'ta ve reconnect sonrasında GET /api/livekit/channel/sync?hostId=... çağırır.
 * - ITEM_PINNED sinyali geldiğinde onItemPinned() ile activeAdId anında güncellenir
 *   (sayfa yenilemesi olmaz).
 */
export function useChannelSync({ hostId }: UseChannelSyncOptions): UseChannelSyncReturn {
    const [activeAdId, setActiveAdId] = useState<string | null>(null);
    const [channelStatus, setChannelStatus] = useState<ChannelSyncResponse["channelStatus"]>(null);

    const connectionState = useConnectionState();
    const prevConnectionStateRef = useRef<ConnectionState | null>(null);

    const syncChannelState = useCallback(async () => {
        if (!hostId) return;
        try {
            const res = await fetch(`/api/livekit/channel/sync?hostId=${encodeURIComponent(hostId)}`);
            if (!res.ok) return;
            const data: ChannelSyncResponse = await res.json();
            setChannelStatus(data.channelStatus);
            // Sadece yükselt; null'a düşürme DataChannel (ITEM_PINNED) üzerinden olur
            if (data.activeAdId) setActiveAdId(data.activeAdId);
        } catch {
            // Sync hatası kritik değil — sessizce geç
        }
    }, [hostId]);

    // İlk mount: late joiner için başlangıç durumunu çek
    useEffect(() => {
        syncChannelState();
    }, []); // eslint-disable-line react-hooks/exhaustive-deps

    // Reconnection sync: Reconnecting → Connected geçişinde çalışır
    useEffect(() => {
        const wasReconnecting = prevConnectionStateRef.current === ConnectionState.Reconnecting;
        prevConnectionStateRef.current = connectionState;
        if (connectionState === ConnectionState.Connected && wasReconnecting) {
            syncChannelState();
        }
    }, [connectionState, syncChannelState]);

    /** ITEM_PINNED DataChannel sinyali aldığında çağrılır. */
    const onItemPinned = useCallback((adId: string) => {
        setActiveAdId(adId);
    }, []);

    return { activeAdId, channelStatus, syncChannelState, onItemPinned };
}
