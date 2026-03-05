"use client";

import type { Reaction } from "../types";

interface FlyingEmojisProps {
    reactions: Reaction[];
}

export function FlyingEmojis({ reactions }: FlyingEmojisProps) {
    return (
        <>
            <style>{`
                @keyframes floatUp {
                    0%   { transform: translateY(0) scale(1);   opacity: 1; }
                    100% { transform: translateY(-250px) scale(1.5); opacity: 0; }
                }
            `}</style>
            {reactions.map((r) => (
                <div
                    key={r.id}
                    className="animate-[floatUp_2.5s_ease-out_forwards]"
                    style={{
                        position: "absolute",
                        bottom: "20%",
                        left: `${r.left}%`,
                        fontSize: "2.5rem",
                        pointerEvents: "none",
                        zIndex: 300,
                    }}
                >
                    {r.emoji}
                </div>
            ))}
        </>
    );
}

interface ReactionBarProps {
    onReact: (emoji: string) => void;
}

const EMOJIS = ["❤️", "🔥", "😍", "👏", "💸"];

export function ReactionBar({ onReact }: ReactionBarProps) {
    return (
        <div style={{ display: "flex", gap: "8px" }}>
            {EMOJIS.map((emoji) => (
                <button
                    key={emoji}
                    onClick={() => onReact(emoji)}
                    style={{
                        background: "rgba(0,0,0,0.4)",
                        backdropFilter: "blur(10px)",
                        border: "1px solid rgba(255,255,255,0.15)",
                        borderRadius: "50%",
                        width: "42px",
                        height: "42px",
                        fontSize: "1.3rem",
                        cursor: "pointer",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        transition: "transform 0.1s",
                    }}
                    onMouseDown={(e) => (e.currentTarget.style.transform = "scale(0.85)")}
                    onMouseUp={(e) => (e.currentTarget.style.transform = "scale(1)")}
                >
                    {emoji}
                </button>
            ))}
        </div>
    );
}
