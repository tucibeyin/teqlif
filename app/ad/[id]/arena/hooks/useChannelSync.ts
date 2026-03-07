import { useState, useCallback, useEffect, useRef } from "react";
import { useConnectionState } from "@livekit/components-react";
import { ConnectionState } from "livekit-client";
import type { ChannelSyncResponse } from "@/app/api/livekit/channel/sync/route";
import type { ActiveItem } from "../types";

interface UseChannelSyncOptions {
    /** Kanalın sahibi (host) kullanıcı ID'si. null verilirse hook pasif kalır. */
    hostId: string | null;
}

interface UseChannelSyncReturn {
    /** Kanala sabitlenmiş ürün. null = ürün sabitlenmemiş. */
    activeItem: ActiveItem | null;
    channelStatus: ChannelSyncResponse["status"];
    /** Manuel veya reconnect tetiklemeli senkronizasyon. */
    syncChannelState: () => Promise<void>;
    /** ITEM_PINNED DataChannel sinyali geldiğinde çağrılır — activeItem'ı anında günceller. */
    onItemPinned: (item: ActiveItem) => void;
}

/**
 * Yayıncı kanalının anlık durumunu yönetir.
 *
 * - İlk mount'ta ve reconnect sonrasında GET /api/livekit/channel/sync?hostId=... çağırır.
 * - ITEM_PINNED sinyali geldiğinde onItemPinned() ile activeItem anında güncellenir.
 */
export function useChannelSync({ hostId }: UseChannelSyncOptions): UseChannelSyncReturn {
    const [activeItem, setActiveItem] = useState<ActiveItem | null>(null);
    const [channelStatus, setChannelStatus] = useState<ChannelSyncResponse["status"]>(null);

    const connectionState = useConnectionState();
    const prevConnectionStateRef = useRef<ConnectionState | null>(null);

    const syncChannelState = useCallback(async () => {
        if (!hostId) return;
        try {
            const res = await fetch(`/api/livekit/channel/sync?hostId=${encodeURIComponent(hostId)}`);
            if (!res.ok) return;
            const data: ChannelSyncResponse = await res.json();
            setChannelStatus(data.status);
            if (data.activeItem) setActiveItem(data.activeItem);
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
    const onItemPinned = useCallback((item: ActiveItem) => {
        setActiveItem(item);
    }, []);

    return { activeItem, channelStatus, syncChannelState, onItemPinned };
}
