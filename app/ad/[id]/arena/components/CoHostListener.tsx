"use client";

import { useState } from "react";
import { useDataChannel, useRoomContext } from "@livekit/components-react";

interface CoHostListenerProps {
    setRole: (role: string) => void;
    setWantsToPublish: (val: boolean) => void;
}

export function CoHostListener({ setRole, setWantsToPublish }: CoHostListenerProps) {
    const [inviteVisible, setInviteVisible] = useState(false);
    const room = useRoomContext();

    useDataChannel((msg) => {
        try {
            const data = JSON.parse(new TextDecoder().decode(msg.payload));
            if (data.type === "INVITE_TO_STAGE") {
                setInviteVisible(true);
            } else if (data.type === "KICK_FROM_STAGE") {
                if (data.targetIdentity === room.localParticipant.identity) {
                    setWantsToPublish(false);
                    setRole("viewer");
                    alert("Sahneden alındınız.");
                    room.disconnect();
                }
            }
        } catch {
            // ignore
        }
    });

    if (!inviteVisible) return null;

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
                    <b>Kameranız açılacaktır.</b> Kabul ediyor musunuz?
                </p>

                <div style={{ display: "flex", gap: "12px", justifyContent: "center", marginTop: "24px" }}>
                    <button
                        onClick={() => setInviteVisible(false)}
                        style={{
                            background: "rgba(255,255,255,0.1)",
                            color: "white",
                            border: "1px solid rgba(255,255,255,0.2)",
                            borderRadius: "100px",
                            padding: "12px 24px",
                            fontWeight: 700,
                            cursor: "pointer",
                        }}
                    >
                        Reddet
                    </button>
                    <button
                        onClick={async () => {
                            setInviteVisible(false);
                            await room.disconnect();
                            setRole("guest");
                        }}
                        style={{
                            background: "linear-gradient(135deg, #00B4CC, #008da1)",
                            color: "white",
                            border: "none",
                            borderRadius: "100px",
                            padding: "12px 24px",
                            fontWeight: 800,
                            cursor: "pointer",
                            boxShadow: "0 8px 20px rgba(0,180,204,0.4)",
                        }}
                    >
                        Kabul Et
                    </button>
                </div>
            </div>
        </div>
    );
}
