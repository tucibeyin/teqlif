import { useState, useCallback } from "react";
import type { StageRequest } from "../types";

async function callStageApi(adId: string, targetIdentity: string, action: "invite" | "accept" | "revoke") {
    const res = await fetch("/api/livekit/stage", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ adId, targetIdentity, action }),
    });
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.error ?? "Stage API hatası");
    }
}

export function useStageRequests(adId: string) {
    const [requests, setRequests] = useState<StageRequest[]>([]);

    const onStageRequest = useCallback((data: any) => {
        if (!data.userId) return;
        setRequests(prev => {
            if (prev.find(r => r.id === data.userId)) return prev;
            return [...prev, { id: data.userId, name: data.userName ?? "Katılımcı" }];
        });
    }, []);

    /**
     * Host bir kullanıcıya sahne daveti gönderir.
     * Backend, hedef katılımcıya yalnızca ona görünür INVITE_TO_STAGE DataChannel sinyali iletir.
     */
    const inviteToStage = useCallback(async (targetIdentity: string) => {
        try {
            await callStageApi(adId, targetIdentity, "invite");
        } catch (e) {
            console.error("[Stage] Davet gönderilemedi:", e);
        }
    }, [adId]);

    /** Host, sahne isteği listesinden birini onaylayıp davet gönderir. */
    const acceptRequest = useCallback(async (req: StageRequest) => {
        if (!confirm(`${req.name} adlı kullanıcıyı sahneye davet etmek istiyor musunuz?`)) {
            setRequests(prev => prev.filter(r => r.id !== req.id));
            return;
        }
        await inviteToStage(req.id);
        setRequests(prev => prev.filter(r => r.id !== req.id));
    }, [inviteToStage]);

    const dismissRequest = useCallback((id: string) => {
        setRequests(prev => prev.filter(r => r.id !== id));
    }, []);

    /**
     * Host bir katılımcıyı sahneden çıkarır (veya katılımcı kendi isteğiyle ayrılır).
     * Backend updateParticipant(canPublish: false) + tüm odaya STAGE_UPDATE broadcast yapar.
     * Katılımcı odadan KOPMAZ — yalnızca yayın yetkisi anında geri alınır.
     */
    const kickFromStage = useCallback(async (targetIdentity: string) => {
        try {
            await callStageApi(adId, targetIdentity, "revoke");
        } catch (e) {
            console.error("[Stage] Sahneden çıkarma başarısız:", e);
        }
    }, [adId]);

    return { requests, onStageRequest, inviteToStage, acceptRequest, dismissRequest, kickFromStage };
}
