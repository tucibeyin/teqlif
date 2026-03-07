"use client";

import { useEffect, useState } from "react";
import { useLocalParticipant } from "@livekit/components-react";
import { ParticipantEvent } from "livekit-client";

interface CoHostListenerProps {
    adId: string;
    /** Görünür davet dialogu — CustomArenaLayout'tan kontrol edilir */
    showInviteDialog: boolean;
    onDecline: () => void;
    /** isCoHost değiştiğinde parent'ı bilgilendir */
    onCoHostStatusChange: (isCoHost: boolean) => void;
}

export function CoHostListener({
    adId,
    showInviteDialog,
    onDecline,
    onCoHostStatusChange,
}: CoHostListenerProps) {
    const { localParticipant } = useLocalParticipant();
    const [isAccepting, setIsAccepting] = useState(false);

    // ── İzin değişikliği dinleyicisi ────────────────────────────────────────
    // Host, backend üzerinden updateParticipant(canPublish: false) yaptığında
    // bu event tetiklenir. Odadan KOPMADAN kamera/mikrofon kapatılır.
    useEffect(() => {
        const handlePermissionChange = (prevPermissions?: { canPublish?: boolean }) => {
            const nowCanPublish = localParticipant.permissions?.canPublish;
            const wasCanPublish = prevPermissions?.canPublish;

            if (wasCanPublish === true && nowCanPublish === false) {
                // Yetki geri alındı — sessizce kapat, disconnect YOK
                localParticipant.setCameraEnabled(false).catch(() => {});
                localParticipant.setMicrophoneEnabled(false).catch(() => {});
                onCoHostStatusChange(false);
            }
        };

        localParticipant.on(ParticipantEvent.ParticipantPermissionsChanged, handlePermissionChange);
        return () => {
            localParticipant.off(ParticipantEvent.ParticipantPermissionsChanged, handlePermissionChange);
        };
    }, [localParticipant, onCoHostStatusChange]);

    // ── Kabul et ─────────────────────────────────────────────────────────────
    const handleAccept = async () => {
        setIsAccepting(true);
        try {
            const res = await fetch("/api/livekit/stage", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    adId,
                    targetIdentity: localParticipant.identity,
                    action: "accept",
                }),
            });

            if (res.ok) {
                // Backend updateParticipant(canPublish: true) yaptı.
                // Artık kamera/mikrofon açılabilir — disconnect YOK.
                await localParticipant.setCameraEnabled(true);
                await localParticipant.setMicrophoneEnabled(true);
                onCoHostStatusChange(true);
            } else {
                const data = await res.json().catch(() => ({}));
                console.error("[CoHost] Kabul hatası:", data.error);
                onDecline();
            }
        } catch (e) {
            console.error("[CoHost] Kabul isteği başarısız:", e);
            onDecline();
        } finally {
            setIsAccepting(false);
        }
    };

    if (!showInviteDialog) return null;

    return (
        <div style={{
            position: "absolute",
            inset: 0,
            background: "rgba(0,0,0,0.8)",
            backdropFilter: "blur(12px)",
            WebkitBackdropFilter: "blur(12px)",
            display: "flex",
            justifyContent: "center",
            alignItems: "center",
            zIndex: 9999,
        }}>
            <div style={{
                background: "rgba(255,255,255,0.05)",
                padding: "32px",
                borderRadius: "24px",
                maxWidth: "340px",
                textAlign: "center",
                border: "1px solid rgba(255,255,255,0.2)",
                boxShadow: "0 25px 50px -12px rgba(0,0,0,0.7)",
            }}>
                <div style={{ fontSize: "3rem", marginBottom: "16px" }}>🎤</div>
                <h3 style={{ marginTop: 0, color: "white", fontSize: "1.5rem", fontWeight: 900 }}>
                    Sahneye Davet!
                </h3>
                <p style={{ fontSize: "0.95rem", color: "rgba(255,255,255,0.7)", lineHeight: 1.5 }}>
                    Yayıncı sizinle beraber yayına katılmanızı istiyor.{" "}
                    <b>Kameranız ve mikrofonunuz açılacak.</b> Kabul ediyor musunuz?
                </p>

                <div style={{ display: "flex", gap: "12px", justifyContent: "center", marginTop: "24px" }}>
                    <button
                        onClick={onDecline}
                        disabled={isAccepting}
                        style={{
                            background: "rgba(255,255,255,0.1)",
                            color: "white",
                            border: "1px solid rgba(255,255,255,0.2)",
                            borderRadius: "100px",
                            padding: "12px 24px",
                            fontWeight: 700,
                            cursor: "pointer",
                            opacity: isAccepting ? 0.5 : 1,
                        }}
                    >
                        Reddet
                    </button>
                    <button
                        onClick={handleAccept}
                        disabled={isAccepting}
                        style={{
                            background: "linear-gradient(135deg, #00B4CC, #008da1)",
                            color: "white",
                            border: "none",
                            borderRadius: "100px",
                            padding: "12px 24px",
                            fontWeight: 800,
                            cursor: isAccepting ? "not-allowed" : "pointer",
                            boxShadow: "0 8px 20px rgba(0,180,204,0.4)",
                            opacity: isAccepting ? 0.7 : 1,
                            minWidth: 110,
                        }}
                    >
                        {isAccepting ? "Bağlanıyor..." : "Kabul Et"}
                    </button>
                </div>
            </div>
        </div>
    );
}
