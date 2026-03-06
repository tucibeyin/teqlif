"use client";

import React from "react";
import { RemoteParticipant } from "livekit-client";

const T = {
    glass: "rgba(255,255,255,0.03)",
    glassBorder: "rgba(255,255,255,0.06)",
    teal: "#06C8E0",
    tealDark: "#059AAF",
    text: "#EDF2F7",
    muted: "#3D526A",
    display: "'Syne', system-ui, sans-serif",
};

interface ParticipantsModalProps {
    isOpen: boolean;
    onClose: () => void;
    participants: RemoteParticipant[];
    onInvite: (userId: string) => void;
}

export function ParticipantsModal({ isOpen, onClose, participants, onInvite }: ParticipantsModalProps) {
    if (!isOpen) return null;

    return (
        <div style={{
            position: "fixed",
            inset: 0,
            zIndex: 1000,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            background: "rgba(0,0,0,0.6)",
            backdropFilter: "blur(4px)",
        }} onClick={onClose}>
            <style>{`
        @keyframes tq-modalFadeIn {
          from { opacity: 0; transform: scale(0.95) translateY(10px); }
          to   { opacity: 1; transform: scale(1) translateY(0); }
        }
        .participant-item:hover {
          background: rgba(255,255,255,0.03);
        }
        .invite-btn:hover {
          filter: brightness(1.2);
          transform: translateY(-1px);
        }
        .invite-btn:active {
          transform: translateY(1px);
        }
      `}</style>

            <div
                style={{
                    width: "90%",
                    maxWidth: 400,
                    background: "rgba(10,14,24,0.95)",
                    border: `1px solid ${T.glassBorder}`,
                    borderRadius: 24,
                    padding: 24,
                    boxShadow: "0 20px 50px rgba(0,0,0,0.5)",
                    animation: "tq-modalFadeIn 0.3s ease-out",
                    display: "flex",
                    flexDirection: "column",
                    maxHeight: "80vh",
                }}
                onClick={e => e.stopPropagation()}
            >
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
                    <h3 style={{ margin: 0, fontFamily: T.display, fontWeight: 800, color: T.text, fontSize: 18 }}>
                        Katılımcılar ({participants.length})
                    </h3>
                    <button
                        onClick={onClose}
                        style={{
                            background: "transparent", border: "none", color: T.muted, cursor: "pointer", fontSize: 24,
                            padding: 4
                        }}
                    >
                        ×
                    </button>
                </div>

                <div style={{ flex: 1, overflowY: "auto", minHeight: 100 }}>
                    {participants.length === 0 ? (
                        <div style={{ textAlign: "center", padding: "40px 0", color: T.muted }}>
                            <p style={{ fontSize: 14 }}>Henüz katılımcı yok.</p>
                        </div>
                    ) : (
                        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                            {participants.map((p) => (
                                <div
                                    key={p.identity}
                                    className="participant-item"
                                    style={{
                                        display: "flex",
                                        justifyContent: "space-between",
                                        alignItems: "center",
                                        padding: "12px 16px",
                                        borderRadius: 12,
                                        background: "rgba(255,255,255,0.015)",
                                        transition: "all 0.2s",
                                    }}
                                >
                                    <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                                        <div style={{
                                            width: 32, height: 32, borderRadius: "50%",
                                            background: `linear-gradient(135deg, ${T.teal}, ${T.tealDark})`,
                                            display: "flex", alignItems: "center", justifyContent: "center",
                                            fontSize: 12, fontWeight: 700, color: "white"
                                        }}>
                                            {(p.name || p.identity).charAt(0).toUpperCase()}
                                        </div>
                                        <span style={{ color: T.text, fontSize: 14, fontWeight: 600 }}>
                                            {p.name || p.identity}
                                        </span>
                                    </div>
                                    <button
                                        className="invite-btn"
                                        onClick={() => {
                                            onInvite(p.identity);
                                            onClose();
                                        }}
                                        style={{
                                            background: "rgba(99,102,241,0.15)",
                                            border: "1px solid rgba(99,102,241,0.3)",
                                            color: "#818CF8",
                                            borderRadius: 100,
                                            padding: "6px 14px",
                                            fontSize: 12,
                                            fontWeight: 700,
                                            cursor: "pointer",
                                            transition: "all 0.15s",
                                        }}
                                    >
                                        Davet Et
                                    </button>
                                </div>
                            ))}
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
}
