import { useState, useCallback } from "react";
import { useRoomContext } from "@livekit/components-react";
import type { StageRequest } from "../types";

export function useStageRequests() {
    const room = useRoomContext();
    const [requests, setRequests] = useState<StageRequest[]>([]);

    const onStageRequest = useCallback((data: any) => {
        if (!data.userId) return;
        setRequests(prev => {
            if (prev.find(r => r.id === data.userId)) return prev;
            return [...prev, { id: data.userId, name: data.userName ?? "Katılımcı" }];
        });
    }, []);

    const acceptRequest = useCallback((req: StageRequest) => {
        // Sadece bir kişi sahnede olabilsin kontrolü
        const isStageBusy = Array.from(room.remoteParticipants.values()).some(
            p => p.isCameraEnabled || p.isMicrophoneEnabled
        );

        if (isStageBusy) {
            alert("Şu anda sahnede başka bir konuk var. Yeni bir davet gönderilemez.");
            return;
        }

        if (!confirm(`${req.name} adlı kullanıcıyı sahneye davet etmek istiyor musunuz?`)) {
            setRequests(prev => prev.filter(r => r.id !== req.id));
            return;
        }
        const payload = JSON.stringify({ type: "INVITE_TO_STAGE", targetIdentity: req.id });
        room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
        setRequests(prev => prev.filter(r => r.id !== req.id));
    }, [room]);

    const dismissRequest = useCallback((id: string) => {
        setRequests(prev => prev.filter(r => r.id !== id));
    }, []);

    const kickFromStage = useCallback((targetIdentity: string) => {
        const payload = JSON.stringify({ type: "KICK_FROM_STAGE", targetIdentity });
        room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
    }, [room]);

    return { requests, onStageRequest, acceptRequest, dismissRequest, kickFromStage };
}
