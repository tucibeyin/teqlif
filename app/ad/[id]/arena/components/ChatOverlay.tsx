"use client";

import type { ArenaMessage } from "../types";

interface ChatOverlayProps {
    messages: ArenaMessage[];
    inputValue: string;
    onInputChange: (val: string) => void;
    onSend: () => void;
    currentUserId?: string;
    onInviteToStage?: (userId: string) => void;
}

export function ChatOverlay({
    messages,
    inputValue,
    onInputChange,
    onSend,
    currentUserId,
    onInviteToStage,
}: ChatOverlayProps) {
    return (
        <div style={{ display: "flex", flexDirection: "column", height: "100%", gap: "8px" }}>
            {/* Message list */}
            <div style={{
                flex: 1,
                overflowY: "auto",
                display: "flex",
                flexDirection: "column",
                gap: "4px",
                maskImage: "linear-gradient(to bottom, transparent, black 30%)",
                WebkitMaskImage: "linear-gradient(to bottom, transparent, black 30%)",
            }}>
                {messages.map((msg) => (
                    <div
                        key={msg.id}
                        style={{
                            background: "rgba(0,0,0,0.35)",
                            backdropFilter: "blur(8px)",
                            borderRadius: "12px",
                            padding: "6px 10px",
                            display: "flex",
                            alignItems: "flex-start",
                            gap: "6px",
                        }}
                    >
                        <span style={{ color: "rgba(255,255,255,0.7)", fontWeight: 800, fontSize: "0.8rem", whiteSpace: "nowrap" }}>
                            {msg.sender}:
                        </span>
                        <span style={{ color: "white", fontSize: "0.8rem", flex: 1 }}>
                            {msg.text}
                        </span>
                        {onInviteToStage && msg.senderId && msg.senderId !== currentUserId && (
                            <button
                                onClick={() => onInviteToStage(msg.senderId!)}
                                title="Sahneye Davet Et"
                                style={{
                                    background: "rgba(59,130,246,0.2)",
                                    border: "none",
                                    borderRadius: "50%",
                                    width: "20px",
                                    height: "20px",
                                    cursor: "pointer",
                                    display: "flex",
                                    alignItems: "center",
                                    justifyContent: "center",
                                    flexShrink: 0,
                                }}
                            >
                                🎤
                            </button>
                        )}
                    </div>
                ))}
            </div>

            {/* Input */}
            <div style={{ display: "flex", gap: "8px" }}>
                <input
                    value={inputValue}
                    onChange={(e) => onInputChange(e.target.value)}
                    onKeyDown={(e) => e.key === "Enter" && onSend()}
                    placeholder="Mesaj yaz..."
                    style={{
                        flex: 1,
                        height: "40px",
                        background: "rgba(255,255,255,0.1)",
                        backdropFilter: "blur(10px)",
                        border: "1px solid rgba(255,255,255,0.15)",
                        borderRadius: "20px",
                        padding: "0 16px",
                        color: "white",
                        fontSize: "0.85rem",
                        outline: "none",
                    }}
                />
                <button
                    onClick={onSend}
                    style={{
                        width: "40px",
                        height: "40px",
                        borderRadius: "50%",
                        background: "rgba(0, 180, 204, 0.8)",
                        border: "none",
                        color: "white",
                        fontSize: "1.1rem",
                        cursor: "pointer",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                    }}
                >
                    ➤
                </button>
            </div>
        </div>
    );
}
